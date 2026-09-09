package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

type appConfig struct {
	root   string
	domain string
	getenv func(string) string
	now    func() time.Time
}

type inventoryRecord struct {
	gitWorktreeRecord
	Common  string
	InScope bool
}

type repoFamily struct {
	common  string
	anchor  string
	records []inventoryRecord
}

type inventory struct {
	families []*repoFamily
	records  []*inventoryRecord
	errors   []error
	scope    string
}

type targetSpec struct {
	owner    string
	repo     string
	branch   string
	repoRoot string
	path     string
}

var componentPattern = regexp.MustCompile(`^[A-Za-z0-9_.-]+$`)

func scopeRoot(cfg appConfig) string { return filepath.Join(cfg.root, cfg.domain) }

// Generated environment and dependency directories are outside the managed
// workspace search. A direct .git marker is checked before this boundary is
// applied, so a worktree whose root itself uses one of these names remains
// discoverable; nested legacy worktrees below generated trees are excluded.
func skipDiscoverySubtree(name string) bool {
	return name == ".direnv" || name == "node_modules"
}

func gitAnchorAt(path string) (bool, error) {
	gitPath := filepath.Join(path, ".git")
	info, err := os.Lstat(gitPath)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("inspect %s: %w", gitPath, err)
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return false, nil
	}
	return info.IsDir() || info.Mode().IsRegular(), nil
}

// discoverAnchorCandidates uses the configured owner/repository container as
// a structural boundary. Once any anchor is found there, Git's worktree list
// is authoritative for every nested legacy path in that repository family;
// only containers with no direct anchor need the exhaustive fallback scan.

func discoverAnchorCandidates(scope string) ([]string, []string, []error) {
	anchors := make([]string, 0)
	fallbackRoots := make([]string, 0)
	discoveryErrors := make([]error, 0)
	anchor, err := gitAnchorAt(scope)
	if err != nil {
		return nil, nil, []error{err}
	}
	if anchor {
		return []string{scope}, nil, nil
	}
	owners, err := os.ReadDir(scope)
	if err != nil {
		return nil, nil, []error{fmt.Errorf("walk %s: %w", scope, err)}
	}
	for _, owner := range owners {
		if owner.Type()&os.ModeSymlink != 0 || !owner.IsDir() || owner.Name() == ".git" {
			continue
		}
		ownerPath := filepath.Join(scope, owner.Name())
		ownerAnchor, ownerErr := gitAnchorAt(ownerPath)
		if ownerErr != nil {
			discoveryErrors = append(discoveryErrors, ownerErr)
			continue
		}
		if ownerAnchor {
			anchors = append(anchors, ownerPath)
			continue
		}
		repos, readErr := os.ReadDir(ownerPath)
		if readErr != nil {
			discoveryErrors = append(discoveryErrors, fmt.Errorf("walk %s: %w", ownerPath, readErr))
			continue
		}
		for _, repo := range repos {
			if repo.Type()&os.ModeSymlink != 0 || !repo.IsDir() || repo.Name() == ".git" {
				continue
			}
			repoPath := filepath.Join(ownerPath, repo.Name())
			repoAnchor, repoErr := gitAnchorAt(repoPath)
			if repoErr != nil {
				discoveryErrors = append(discoveryErrors, repoErr)
				continue
			}
			if repoAnchor {
				anchors = append(anchors, repoPath)
				continue
			}
			entries, readErr := os.ReadDir(repoPath)
			if readErr != nil {
				discoveryErrors = append(discoveryErrors, fmt.Errorf("walk %s: %w", repoPath, readErr))
				continue
			}
			foundDirect := false
			for _, entry := range entries {
				if entry.Type()&os.ModeSymlink != 0 || !entry.IsDir() || entry.Name() == ".git" {
					continue
				}
				path := filepath.Join(repoPath, entry.Name())
				branchAnchor, branchErr := gitAnchorAt(path)
				if branchErr != nil {
					discoveryErrors = append(discoveryErrors, branchErr)
					continue
				}
				if branchAnchor {
					anchors = append(anchors, path)
					foundDirect = true
				}
			}
			if !foundDirect {
				fallbackRoots = append(fallbackRoots, repoPath)
			}
		}
	}
	return anchors, fallbackRoots, discoveryErrors
}

// fastGitMarkerAt validates enough of a .git marker to avoid listing arbitrary
// directories, without invoking Git. Full Git identity remains authoritative
// whenever a listing selection is opened or another command reconciles state.
func fastGitMarkerAt(path string) bool {
	marker := filepath.Join(path, ".git")
	info, err := os.Lstat(marker)
	if err != nil || info.Mode()&os.ModeSymlink != 0 {
		return false
	}
	if info.IsDir() {
		for _, name := range []string{"HEAD", "config"} {
			child, childErr := os.Stat(filepath.Join(marker, name))
			if childErr != nil || !child.Mode().IsRegular() {
				return false
			}
		}
		return true
	}
	if !info.Mode().IsRegular() {
		return false
	}
	data, err := os.ReadFile(marker)
	if err != nil {
		return false
	}
	const prefix = "gitdir: "
	line := strings.TrimSpace(string(data))
	if !strings.HasPrefix(line, prefix) {
		return false
	}
	adminDir := filepath.Clean(strings.TrimSpace(strings.TrimPrefix(line, prefix)))
	if !filepath.IsAbs(adminDir) {
		adminDir = filepath.Join(path, adminDir)
	}
	adminInfo, err := os.Stat(adminDir)
	if err != nil || !adminInfo.IsDir() {
		return false
	}
	for _, name := range []string{"HEAD", "commondir", "gitdir"} {
		child, childErr := os.Stat(filepath.Join(adminDir, name))
		if childErr != nil || !child.Mode().IsRegular() {
			return false
		}
	}
	back, err := os.ReadFile(filepath.Join(adminDir, "gitdir"))
	return err == nil && filepath.Clean(strings.TrimSpace(string(back))) == filepath.Clean(marker)
}

// linkedWorktreePaths reads Git's administrative gitdir pointers without
// invoking Git or descending into the anchor's source tree.
func linkedWorktreePaths(anchor, scope string) ([]string, error) {
	gitPath := filepath.Join(anchor, ".git")
	gitInfo, err := os.Lstat(gitPath)
	if err != nil {
		return nil, err
	}
	adminRoot := ""
	if gitInfo.IsDir() {
		adminRoot = filepath.Join(gitPath, "worktrees")
	} else if gitInfo.Mode().IsRegular() {
		data, readErr := os.ReadFile(gitPath)
		if readErr != nil {
			return nil, readErr
		}
		const prefix = "gitdir: "
		line := strings.TrimSpace(string(data))
		if !strings.HasPrefix(line, prefix) {
			return nil, fmt.Errorf("invalid gitdir pointer %s", gitPath)
		}
		adminDir := filepath.Clean(strings.TrimSpace(strings.TrimPrefix(line, prefix)))
		if !filepath.IsAbs(adminDir) {
			adminDir = filepath.Join(anchor, adminDir)
		}
		commonData, readErr := os.ReadFile(filepath.Join(adminDir, "commondir"))
		if readErr != nil {
			return nil, readErr
		}
		commonDir := strings.TrimSpace(string(commonData))
		if !filepath.IsAbs(commonDir) {
			commonDir = filepath.Join(adminDir, commonDir)
		}
		adminRoot = filepath.Join(filepath.Clean(commonDir), "worktrees")
	} else {
		return nil, nil
	}
	entries, err := os.ReadDir(adminRoot)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.Type()&os.ModeSymlink != 0 || !entry.IsDir() {
			continue
		}
		gitdirPath := filepath.Join(adminRoot, entry.Name(), "gitdir")
		data, readErr := os.ReadFile(gitdirPath)
		if readErr != nil {
			continue
		}
		worktreeGitdir := filepath.Clean(strings.TrimSpace(string(data)))
		if !filepath.IsAbs(worktreeGitdir) || filepath.Base(worktreeGitdir) != ".git" {
			continue
		}
		worktree := filepath.Dir(worktreeGitdir)
		if !pathInside(worktree, scope) {
			continue
		}
		info, statErr := os.Lstat(worktree)
		if statErr != nil || info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
			continue
		}
		if fastGitMarkerAt(worktree) {
			paths = append(paths, filepath.Clean(worktree))
		}
	}
	sort.Strings(paths)
	return paths, nil
}

// discoverFilesystemWorktrees finds marker-bearing directories without invoking
// Git or statting every file. It is used only for the non-destructive listing
// modes; selected paths are revalidated against Git before they are opened.
func discoverFilesystemWorktrees(scope string) ([]string, error) {
	scope = canonicalPath(scope)
	info, err := os.Stat(scope)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("workspace scope %s is not a directory", scope)
	}
	owners, err := os.ReadDir(scope)
	if err != nil {
		return nil, fmt.Errorf("walk %s: %w", scope, err)
	}
	paths := make([]string, 0)
	var walkErrors []error
	var walk func(string)
	walk = func(path string) {
		entries, readErr := os.ReadDir(path)
		if readErr != nil {
			walkErrors = append(walkErrors, fmt.Errorf("walk %s: %w", path, readErr))
			return
		}
		if fastGitMarkerAt(path) {
			paths = append(paths, filepath.Clean(path))
			linked, linkedErr := linkedWorktreePaths(path, scope)
			if linkedErr != nil && !errors.Is(linkedErr, os.ErrNotExist) {
				walkErrors = append(walkErrors, fmt.Errorf("inspect linked worktrees in %s: %w", path, linkedErr))
			} else {
				paths = append(paths, linked...)
			}
			return
		}
		for _, entry := range entries {
			if entry.Type()&os.ModeSymlink != 0 || !entry.IsDir() || entry.Name() == ".git" {
				continue
			}
			child := filepath.Join(path, entry.Name())
			if skipDiscoverySubtree(entry.Name()) {
				if fastGitMarkerAt(child) {
					paths = append(paths, filepath.Clean(child))
				}
				continue
			}
			walk(child)
		}
	}
	for _, owner := range owners {
		if owner.Type()&os.ModeSymlink != 0 || !owner.IsDir() || owner.Name() == ".git" {
			continue
		}
		ownerPath := filepath.Join(scope, owner.Name())
		repos, readErr := os.ReadDir(ownerPath)
		if readErr != nil {
			walkErrors = append(walkErrors, fmt.Errorf("walk %s: %w", ownerPath, readErr))
			continue
		}
		for _, repo := range repos {
			if repo.Type()&os.ModeSymlink != 0 || !repo.IsDir() || repo.Name() == ".git" {
				continue
			}
			repoPath := filepath.Join(ownerPath, repo.Name())
			repoAnchor := fastGitMarkerAt(repoPath)
			if repoAnchor {
				paths = append(paths, filepath.Clean(repoPath))
				linked, linkedErr := linkedWorktreePaths(repoPath, scope)
				if linkedErr != nil && !errors.Is(linkedErr, os.ErrNotExist) {
					walkErrors = append(walkErrors, fmt.Errorf("inspect linked worktrees in %s: %w", repoPath, linkedErr))
				} else {
					paths = append(paths, linked...)
				}
				continue
			}
			walk(repoPath)
		}
	}
	sort.Strings(paths)
	paths = slices.Compact(paths)
	if len(walkErrors) != 0 {
		return paths, walkErrors[0]
	}
	return paths, nil
}

func fastListInventory(ctx context.Context, cfg appConfig, stderr io.Writer) (*inventory, *advisoryStore, map[usageKey]sql.NullInt64) {
	scope := canonicalPath(scopeRoot(cfg))
	paths, err := discoverFilesystemWorktrees(scope)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "Warning: %v\n", err)
	}
	inv := &inventory{scope: scope}
	for _, path := range paths {
		inv.records = append(inv.records, &inventoryRecord{
			gitWorktreeRecord: gitWorktreeRecord{Path: path, Branch: filesystemBranch(scope, path)},
			InScope:           true,
		})
	}
	store, storeErr := openStore(ctx, cfg.getenv)
	if storeErr != nil {
		_, _ = fmt.Fprintf(stderr, "Warning: SQLite advisory state unavailable: %v\n", storeErr)
		return inv, nil, nil
	}
	usage, usageErr := store.usage(ctx)
	if usageErr != nil {
		_, _ = fmt.Fprintf(stderr, "Warning: SQLite usage read failed: %v\n", usageErr)
		usage = nil
	}
	usageByPath := make(map[string]usageKey, len(usage))
	for key := range usage {
		usageByPath[key.path] = key
	}
	for _, record := range inv.records {
		if key, ok := usageByPath[filepath.Clean(record.Path)]; ok {
			record.Common = key.common
		}
	}
	return inv, store, usage
}

func filesystemBranch(scope, path string) string {
	rel, err := filepath.Rel(scope, path)
	if err != nil {
		return ""
	}
	parts := strings.Split(rel, string(filepath.Separator))
	if len(parts) < 3 {
		return ""
	}
	branch, err := url.PathUnescape(strings.Join(parts[2:], "/"))
	if err != nil {
		return strings.Join(parts[2:], "/")
	}
	return branch
}

func discoverInventory(ctx context.Context, cfg appConfig) (*inventory, error) {
	scope := scopeRoot(cfg)
	inv := &inventory{scope: scope}
	info, err := os.Stat(scope)
	if errors.Is(err, os.ErrNotExist) {
		return inv, nil
	}
	if err != nil {
		return inv, err
	}
	if !info.IsDir() {
		return inv, fmt.Errorf("workspace scope %s is not a directory", scope)
	}
	anchors, fallbackRoots, discoveryErrors := discoverAnchorCandidates(scope)

	// Search every directory in repository roots without a direct anchor,
	// preserving arbitrary branch depth and marker-driven stopping. A direct
	// anchor establishes the repository family; Git worktree enumeration below
	// supplies all of that family's worktrees, including nested legacy paths.
	var queueMu sync.Mutex
	queueCond := sync.NewCond(&queueMu)
	queue := append([]string(nil), fallbackRoots...)
	pending := len(queue)
	add := func(path string) {
		queueMu.Lock()
		queue = append(queue, path)
		pending++
		queueCond.Signal()
		queueMu.Unlock()
	}
	next := func() (string, bool) {
		queueMu.Lock()
		defer queueMu.Unlock()
		for len(queue) == 0 && pending > 0 {
			queueCond.Wait()
		}
		if len(queue) == 0 {
			return "", false
		}
		last := len(queue) - 1
		path := queue[last]
		queue = queue[:last]
		return path, true
	}
	done := func() {
		queueMu.Lock()
		pending--
		if pending == 0 {
			queueCond.Broadcast()
		}
		queueMu.Unlock()
	}
	var resultMu sync.Mutex
	walkErrors := append([]error(nil), discoveryErrors...)
	recordError := func(err error) {
		resultMu.Lock()
		walkErrors = append(walkErrors, err)
		resultMu.Unlock()
	}
	recordAnchor := func(path string) {
		resultMu.Lock()
		anchors = append(anchors, path)
		resultMu.Unlock()
	}

	workerCount := runtime.GOMAXPROCS(0) * 4
	if workerCount < 4 {
		workerCount = 4
	}
	if workerCount > 32 {
		workerCount = 32
	}
	var workers sync.WaitGroup
	workers.Add(workerCount)
	for i := 0; i < workerCount; i++ {
		go func() {
			defer workers.Done()
			for {
				path, ok := next()
				if !ok {
					return
				}
				entries, readErr := os.ReadDir(path)
				if readErr != nil {
					recordError(fmt.Errorf("walk %s: %w", path, readErr))
					done()
					continue
				}

				gitEntry := os.DirEntry(nil)
				for _, entry := range entries {
					if entry.Name() == ".git" {
						gitEntry = entry
						break
					}
				}
				if gitEntry != nil && gitEntry.Type()&os.ModeSymlink == 0 {
					gitPath := filepath.Join(path, ".git")
					gitInfo, statErr := os.Lstat(gitPath)
					if statErr == nil && (gitInfo.IsDir() || gitInfo.Mode().IsRegular()) {
						recordAnchor(path)
						done()
						continue
					}
					if statErr != nil && !errors.Is(statErr, os.ErrNotExist) {
						recordError(fmt.Errorf("inspect %s: %w", gitPath, statErr))
					}
				}

				for _, entry := range entries {
					if entry.Type()&os.ModeSymlink != 0 || !entry.IsDir() || entry.Name() == ".git" {
						continue
					}
					childPath := filepath.Join(path, entry.Name())
					if skipDiscoverySubtree(entry.Name()) {
						anchor, anchorErr := gitAnchorAt(childPath)
						if anchorErr != nil {
							recordError(anchorErr)
						} else if anchor {
							recordAnchor(childPath)
						}
						continue
					}
					add(childPath)
				}
				done()
			}
		}()
	}
	workers.Wait()
	sort.Slice(walkErrors, func(i, j int) bool { return walkErrors[i].Error() < walkErrors[j].Error() })
	inv.errors = append(inv.errors, walkErrors...)
	sort.Strings(anchors)
	families := make(map[string]*repoFamily)
	for _, anchor := range anchors {
		common, err := gitCommonDir(ctx, anchor)
		if err != nil {
			inv.errors = append(inv.errors, fmt.Errorf("enumerate %s: %w", anchor, err))
			continue
		}
		if _, ok := families[common]; ok {
			continue
		}
		records, err := gitWorktrees(ctx, anchor)
		if err != nil {
			inv.errors = append(inv.errors, fmt.Errorf("enumerate worktrees in %s: %w", anchor, err))
			continue
		}
		family := &repoFamily{common: common, anchor: canonicalPath(anchor)}
		for _, record := range records {
			r := inventoryRecord{gitWorktreeRecord: record, Common: common}
			r.InScope = pathInside(record.Path, scope)
			family.records = append(family.records, r)
		}
		if anchorPath := usableFamilyAnchor(family.records); anchorPath != "" {
			family.anchor = anchorPath
		}
		families[common] = family
	}
	keys := make([]string, 0, len(families))
	for key := range families {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		family := families[key]
		inv.families = append(inv.families, family)

		for i := range family.records {
			inv.records = append(inv.records, &family.records[i])
		}
	}
	return inv, nil
}

func sortedFastListRecords(inv *inventory, usage map[usageKey]sql.NullInt64) []*inventoryRecord {
	records := append([]*inventoryRecord(nil), inv.records...)
	usageByPath := make(map[string]sql.NullInt64, len(usage))
	for key, value := range usage {
		usageByPath[key.path] = value
	}
	sort.Slice(records, func(i, j int) bool {
		a, b := usageByPath[records[i].Path], usageByPath[records[j].Path]
		if a.Valid != b.Valid {
			return a.Valid
		}
		if a.Valid && a.Int64 != b.Int64 {
			return a.Int64 > b.Int64
		}
		return records[i].Path < records[j].Path
	})
	return records
}

func (inv *inventory) familyForCommon(common string) *repoFamily {
	for _, family := range inv.families {
		if family.common == common {
			return family
		}
	}
	return nil
}

func (inv *inventory) inScopeRecords() []*inventoryRecord {
	out := make([]*inventoryRecord, 0)
	for _, record := range inv.records {
		if record.InScope {
			out = append(out, record)
		}
	}
	return out
}

func (inv *inventory) familyForRepo(repoRoot string) *repoFamily {
	for _, family := range inv.families {
		for _, record := range family.records {
			if pathInside(record.Path, repoRoot) {
				return family
			}
		}
	}
	return nil
}

func reconcileInventory(ctx context.Context, inv *inventory, store *advisoryStore, stderr io.Writer) bool {
	ok := len(inv.errors) == 0
	for _, err := range inv.errors {
		_, _ = fmt.Fprintf(stderr, "Warning: %v\n", err)
	}
	if store == nil {
		return ok
	}
	for _, family := range inv.families {
		current := make([]gitWorktreeRecord, len(family.records))
		for i := range family.records {
			current[i] = family.records[i].gitWorktreeRecord
		}
		if err := store.reconcileFamilyRecords(ctx, family, current); err != nil {
			_, _ = fmt.Fprintf(stderr, "Warning: SQLite reconciliation for %s failed: %v\n", family.common, err)
			ok = false
		}
	}
	return ok
}

func prepareInventory(ctx context.Context, cfg appConfig, stderr io.Writer) (*inventory, *advisoryStore, bool) {
	inv, err := discoverInventory(ctx, cfg)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "Warning: %v\n", err)
		inv = &inventory{scope: scopeRoot(cfg), errors: []error{err}}
	}
	store, storeErr := openStore(ctx, cfg.getenv)
	if storeErr != nil {
		_, _ = fmt.Fprintf(stderr, "Warning: SQLite advisory state unavailable: %v\n", storeErr)
		store = nil
	}
	ok := reconcileInventory(ctx, inv, store, stderr)
	if !ok {
		inv.errors = append(inv.errors, fmt.Errorf("reconciliation incomplete"))
	}
	if store != nil {
		complete, markerErr := store.marker(ctx)
		if markerErr != nil {
			_, _ = fmt.Fprintf(stderr, "Warning: SQLite import marker unavailable: %v\n", markerErr)
		} else if !complete {
			if summary, importErr := importFilesystem(ctx, cfg, inv, store, false, stderr); importErr != nil {
				_, _ = fmt.Fprintf(stderr, "Warning: initial filesystem import incomplete: %v\n", importErr)
			} else if summary.failed > 0 || len(inv.errors) > 0 {
				_, _ = fmt.Fprintf(stderr, "Warning: initial filesystem import incomplete (%d failed)\n", summary.failed)
			}
		}
	}
	return inv, store, ok
}

func parseTarget(cfg appConfig, target string) (targetSpec, error) {
	first := strings.IndexByte(target, '/')
	if first <= 0 || first == len(target)-1 {
		return targetSpec{}, fmt.Errorf("target must be owner/repo/branch; repo/branch is ambiguous")
	}
	secondRel := strings.IndexByte(target[first+1:], '/')
	if secondRel < 0 {
		return targetSpec{}, fmt.Errorf("target must include owner, repository, and branch; repo/branch is ambiguous")
	}
	second := first + 1 + secondRel
	owner, repo, branch := target[:first], target[first+1:second], target[second+1:]
	if !componentPattern.MatchString(owner) || owner == "." || owner == ".." || !componentPattern.MatchString(repo) || repo == "." || repo == ".." {
		return targetSpec{}, fmt.Errorf("invalid owner or repository in target %q", target)
	}
	if branch == "" {
		return targetSpec{}, fmt.Errorf("branch must not be empty")
	}
	return targetSpec{owner: owner, repo: repo, branch: branch, repoRoot: filepath.Join(scopeRoot(cfg), owner, repo)}, nil
}

func rejectCaseFoldCollision(parent, desired string) error {
	entries, err := os.ReadDir(parent)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.Name() != desired && strings.EqualFold(entry.Name(), desired) {
			return fmt.Errorf("path component %s collides by case with %s", desired, entry.Name())
		}
	}
	return nil
}

func validateDestination(spec targetSpec, registered map[string]bool) error {
	root := canonicalPath(spec.repoRoot)
	if !pathInside(root, scopeRootFromRepo(spec.repoRoot, root)) {
		// The explicit checks below are the meaningful guard; this branch is
		// intentionally unreachable for ordinary absolute workspace roots.
		return fmt.Errorf("destination escapes workspace scope")
	}
	if info, err := os.Lstat(spec.repoRoot); err == nil {
		if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
			return fmt.Errorf("repository parent %s is not a real directory", spec.repoRoot)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if info, err := os.Lstat(spec.path); err == nil {
		if info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("destination %s is a symlink", spec.path)
		}
		if !info.IsDir() {
			return fmt.Errorf("destination %s is not a directory", spec.path)
		}
		if !registered[canonicalPath(spec.path)] {
			return fmt.Errorf("destination %s is occupied by a non-worktree directory", spec.path)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if entries, err := os.ReadDir(spec.repoRoot); err == nil {
		want := filepath.Base(spec.path)
		for _, entry := range entries {
			if entry.Name() != want && strings.EqualFold(entry.Name(), want) {
				return fmt.Errorf("destination %s collides by case with %s", spec.path, entry.Name())
			}
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

// scopeRootFromRepo returns the parent of owner/repo. It is kept separate to
// make the path containment assertion auditable at the only destination guard.
func scopeRootFromRepo(repoRoot, _ string) string {
	return filepath.Dir(filepath.Dir(repoRoot))
}

func ensureDirectoryParents(path, rejectWithin string) ([]string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	boundary := ""
	if rejectWithin != "" {
		boundary, err = filepath.Abs(filepath.Clean(rejectWithin))
		if err != nil {
			return nil, err
		}
	}
	parts := strings.Split(filepath.Clean(abs), string(filepath.Separator))
	if len(parts) == 0 {
		return nil, nil
	}
	current := parts[0]
	if current == "" {
		current = string(filepath.Separator)
	}
	created := make([]string, 0)
	for _, part := range parts[1:] {
		if part == "" {
			continue
		}
		current = filepath.Join(current, part)
		info, statErr := os.Lstat(current)
		if statErr == nil {
			if info.Mode()&os.ModeSymlink != 0 {
				if boundary != "" {
					rel, relErr := filepath.Rel(boundary, current)
					if relErr == nil && (rel == "." || (rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) && !filepath.IsAbs(rel))) {
						return created, fmt.Errorf("path component %s is a symlink", current)
					}
				}
				resolved, resolveErr := os.Stat(current)
				if resolveErr != nil || !resolved.IsDir() {
					if resolveErr != nil {
						return created, resolveErr
					}
					return created, fmt.Errorf("path component %s is not a directory", current)
				}
				continue
			}
			if !info.IsDir() {
				return created, fmt.Errorf("path component %s is not a directory", current)
			}
			continue
		}
		if !errors.Is(statErr, os.ErrNotExist) {
			return created, statErr
		}
		if err := os.Mkdir(current, 0o755); err != nil {
			return created, err
		}
		created = append(created, current)
	}
	return created, nil
}

func cleanupEmptyDirs(paths []string) {
	for i := len(paths) - 1; i >= 0; i-- {
		info, statErr := os.Stat(paths[i])
		if statErr != nil || !info.IsDir() {
			continue
		}
		entries, readErr := os.ReadDir(paths[i])
		if readErr == nil && len(entries) == 0 {
			_ = os.Remove(paths[i])
		}
	}
}

func (cfg appConfig) remoteURL(owner, repo string) string {
	return "git@" + cfg.domain + ":" + owner + "/" + repo + ".git"
}

func registeredPaths(family *repoFamily) map[string]bool {
	out := make(map[string]bool)
	if family == nil {
		return out
	}
	for _, record := range family.records {
		out[canonicalPath(record.Path)] = true
	}
	return out
}
func liveInventoryRecord(record *inventoryRecord) bool {
	if record == nil || record.Prunable || record.Path == "" {
		return false
	}
	info, err := os.Stat(record.Path)
	return err == nil && info.IsDir()
}

func findBranchRecord(family *repoFamily, branch string) (*inventoryRecord, error) {
	if family == nil {
		return nil, nil
	}
	var found *inventoryRecord
	for i := range family.records {
		record := &family.records[i]
		if record.Branch != branch {
			continue
		}
		if found != nil {
			return nil, fmt.Errorf("Git reports branch %q in more than one worktree", branch)
		}
		found = record
	}
	return found, nil
}

func resolveTarget(ctx context.Context, cfg appConfig, spec targetSpec, create bool, stderr io.Writer) (*inventoryRecord, *repoFamily, *inventory, error) {
	if _, err := gitCheckBranch(ctx, spec.branch); err != nil {
		return nil, nil, nil, fmt.Errorf("invalid branch %q: %w", spec.branch, err)
	}
	if err := rejectCaseFoldCollision(cfg.root, cfg.domain); err != nil {
		return nil, nil, nil, err
	}
	if err := rejectCaseFoldCollision(filepath.Join(cfg.root, cfg.domain), spec.owner); err != nil {
		return nil, nil, nil, err
	}
	if err := rejectCaseFoldCollision(filepath.Join(cfg.root, cfg.domain, spec.owner), spec.repo); err != nil {
		return nil, nil, nil, err
	}
	inv, err := discoverInventory(ctx, cfg)
	if err != nil {
		return nil, nil, inv, err
	}
	family := inv.familyForRepo(spec.repoRoot)
	if family != nil {
		record, err := findBranchRecord(family, spec.branch)
		if err != nil {
			return nil, family, inv, err
		}
		if record != nil && liveInventoryRecord(record) {
			if !record.InScope {
				return nil, family, inv, fmt.Errorf("branch %q is checked out outside the configured workspace root", spec.branch)
			}
			return record, family, inv, nil
		}
		if !create {
			return nil, family, inv, fmt.Errorf("no registered worktree for %s/%s/%s", spec.owner, spec.repo, spec.branch)
		}
		spec.path = filepath.Join(spec.repoRoot, url.PathEscape(spec.branch))
		if err := validateDestination(spec, registeredPaths(family)); err != nil {
			return nil, family, inv, err
		}
		record, err = addWorktree(ctx, cfg, spec, family, stderr)
		return record, family, inv, err
	}
	if !create {
		return nil, nil, inv, fmt.Errorf("repository %s/%s is not present", spec.owner, spec.repo)
	}
	if info, statErr := os.Stat(spec.repoRoot); statErr == nil {
		if !info.IsDir() {
			return nil, nil, inv, fmt.Errorf("repository root %s is not a directory", spec.repoRoot)
		}
		entries, readErr := os.ReadDir(spec.repoRoot)
		if readErr != nil {
			return nil, nil, inv, readErr
		}
		if len(entries) != 0 {
			return nil, nil, inv, fmt.Errorf("repository root %s is occupied but is not a registered Git repository", spec.repoRoot)
		}
	} else if !errors.Is(statErr, os.ErrNotExist) {
		return nil, nil, inv, statErr
	}
	defaultBranch, err := gitRemoteHead(ctx, "", cfg.remoteURL(spec.owner, spec.repo))
	if err != nil {
		return nil, nil, inv, fmt.Errorf("resolve remote default branch: %w", err)
	}
	if _, err := gitCheckBranch(ctx, defaultBranch); err != nil {
		return nil, nil, inv, fmt.Errorf("remote default branch %q is invalid: %w", defaultBranch, err)
	}
	defaultPath := filepath.Join(spec.repoRoot, url.PathEscape(defaultBranch))
	if spec.branch == defaultBranch {
		spec.path = defaultPath
	} else {
		spec.path = filepath.Join(spec.repoRoot, url.PathEscape(spec.branch))
	}
	if err := validateDestination(spec, map[string]bool{}); err != nil {
		return nil, nil, inv, err
	}
	defaultSpec := spec
	defaultSpec.path = defaultPath
	if err := validateDestination(defaultSpec, map[string]bool{}); err != nil {
		return nil, nil, inv, err
	}
	created, err := ensureDirectoryParents(spec.repoRoot, cfg.root)
	if err != nil {
		return nil, nil, inv, err
	}
	created = append(created, defaultPath)
	cloneArgs := []string{"clone", "--origin", "origin", "--branch", defaultBranch, cfg.remoteURL(spec.owner, spec.repo), defaultPath}
	if err := gitRun(ctx, "", cloneArgs, nil, io.Discard, stderr); err != nil {
		cleanupEmptyDirs(created)
		if leftoverInventory, discoverErr := discoverInventory(ctx, cfg); discoverErr == nil {
			if leftoverFamily := leftoverInventory.familyForRepo(spec.repoRoot); leftoverFamily != nil {
				if leftover, findErr := findBranchRecord(leftoverFamily, spec.branch); findErr == nil && leftover != nil {
					_, _ = fmt.Fprintf(stderr, "Warning: failed clone left Git worktree %s registered\n", leftover.Path)
				}
			}
		}
		return nil, nil, inv, err
	}
	// A default checkout is the primary worktree; enumerate again instead of
	// attempting to add a second worktree at the same path.
	fresh, freshErr := discoverInventory(ctx, cfg)
	if freshErr != nil {
		return nil, nil, fresh, freshErr
	}
	family = fresh.familyForRepo(spec.repoRoot)
	if family == nil {
		return nil, nil, fresh, fmt.Errorf("clone succeeded but Git did not enumerate the repository")
	}
	if spec.branch == defaultBranch {
		record, err := findBranchRecord(family, defaultBranch)
		if err != nil || record == nil {
			if err == nil {
				err = fmt.Errorf("cloned default worktree was not registered")
			}
			return nil, family, fresh, err
		}
		enableDirenv(ctx, record.Path, stderr)
		return record, family, fresh, nil
	}
	spec.path = filepath.Join(spec.repoRoot, url.PathEscape(spec.branch))
	if err := validateDestination(spec, registeredPaths(family)); err != nil {
		return nil, family, fresh, err
	}
	record, err := addWorktree(ctx, cfg, spec, family, stderr)
	return record, family, fresh, err
}

func worktreeAddArgs(path, branch string, local, remote bool, defaultBranch string) []string {
	if local {
		return []string{"worktree", "add", path, branch}
	}
	if remote {
		return []string{"worktree", "add", "--track", "-b", branch, path, "origin/" + branch}
	}
	return []string{"worktree", "add", "-b", branch, path, "refs/remotes/origin/" + defaultBranch}
}

func addWorktree(ctx context.Context, cfg appConfig, spec targetSpec, family *repoFamily, stderr io.Writer) (*inventoryRecord, error) {
	if family == nil || family.anchor == "" {
		return nil, fmt.Errorf("repository has no usable Git anchor")
	}
	if err := validateDestination(spec, registeredPaths(family)); err != nil {
		return nil, err
	}
	created, err := ensureDirectoryParents(filepath.Dir(spec.path), cfg.root)
	if err != nil {
		return nil, err
	}
	created = append(created, spec.path)
	succeeded := false
	defer func() {
		if !succeeded {
			cleanupEmptyDirs(created)
		}
	}()
	local, err := gitCheckRef(ctx, family.anchor, "refs/heads/"+spec.branch)
	if err != nil {
		return nil, err
	}
	var args []string
	if local {
		args = worktreeAddArgs(spec.path, spec.branch, true, false, "")
	} else {
		if err := gitRun(ctx, family.anchor, []string{"fetch", "--prune", "origin"}, nil, io.Discard, stderr); err != nil {
			return nil, err
		}
		remote, err := gitCheckRef(ctx, family.anchor, "refs/remotes/origin/"+spec.branch)
		if err != nil {
			return nil, err
		}
		if remote {
			args = worktreeAddArgs(spec.path, spec.branch, false, true, "")
		} else {
			defaultBranch, err := gitRemoteHead(ctx, family.anchor, "origin")
			if err != nil {
				return nil, err
			}
			if _, err := gitCheckBranch(ctx, defaultBranch); err != nil {
				return nil, err
			}
			ok, err := gitCheckRef(ctx, family.anchor, "refs/remotes/origin/"+defaultBranch)
			if err != nil {
				return nil, err
			}
			if !ok {
				return nil, fmt.Errorf("origin/%s is not available after fetch", defaultBranch)
			}
			args = worktreeAddArgs(spec.path, spec.branch, false, false, defaultBranch)
		}
	}
	if err := gitRun(ctx, family.anchor, args, nil, io.Discard, stderr); err != nil {
		if leftoverFamily, enumerateErr := enumerateFamily(ctx, family.anchor, scopeRootFromRepo(spec.repoRoot, spec.repoRoot)); enumerateErr == nil {
			if leftover, findErr := findBranchRecord(leftoverFamily, spec.branch); findErr == nil && leftover != nil {
				_, _ = fmt.Fprintf(stderr, "Warning: failed worktree add left Git worktree %s registered\n", leftover.Path)
			}
		}
		return nil, err
	}
	fresh, err := enumerateFamily(ctx, family.anchor, scopeRootFromRepo(spec.repoRoot, spec.repoRoot))
	if err != nil {
		return nil, err
	}
	record, err := findBranchRecord(fresh, spec.branch)
	if err != nil {
		return nil, err
	}
	if record == nil || canonicalPath(record.Path) != canonicalPath(spec.path) || !record.InScope {
		return nil, fmt.Errorf("Git add completed but requested worktree was not registered at %s", spec.path)
	}
	enableDirenv(ctx, record.Path, stderr)
	succeeded = true
	return record, nil
}

func enumerateFamily(ctx context.Context, anchor, scope string) (*repoFamily, error) {
	common, err := gitCommonDir(ctx, anchor)
	if err != nil {
		return nil, err
	}
	records, err := gitWorktrees(ctx, anchor)
	if err != nil {
		return nil, err
	}
	family := &repoFamily{common: common, anchor: canonicalPath(anchor)}
	for _, record := range records {
		r := inventoryRecord{gitWorktreeRecord: record, Common: common, InScope: pathInside(record.Path, scope)}
		family.records = append(family.records, r)
	}
	if anchorPath := usableFamilyAnchor(family.records); anchorPath != "" {
		family.anchor = anchorPath
	}
	return family, nil
}

func usableFamilyAnchor(records []inventoryRecord) string {
	for _, record := range records {
		if info, err := os.Stat(record.Path); err == nil && info.IsDir() {
			return record.Path
		}
	}
	if len(records) != 0 {
		return records[0].Path
	}
	return ""
}

func enableDirenv(ctx context.Context, worktree string, stderr io.Writer) {
	if _, err := gitCapture(ctx, worktree, "ls-files", "--error-unmatch", "--", ".envrc"); err != nil {
		return
	}
	cmd := exec.CommandContext(ctx, "direnv", "allow", filepath.Join(worktree, ".envrc"))
	if err := cmd.Run(); err != nil {
		_, _ = fmt.Fprintf(stderr, "Warning: direnv allow failed for %s: %v\n", worktree, err)
	}
}

func runTarget(ctx context.Context, cfg appConfig, target string, printOnly, ensureOnly bool, stdin io.Reader, stdout, stderr io.Writer) (int, error) {
	spec, err := parseTarget(cfg, target)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "Error: %v\n", err)
		printUsage(stderr)
		return 2, err
	}
	inv, store, _ := prepareInventory(ctx, cfg, stderr)
	if store != nil {
		defer store.close()
	}
	wantCreate := !printOnly
	record, family, _, err := resolveTarget(ctx, cfg, spec, wantCreate, stderr)
	if err != nil {
		reportGitError(stderr, err)
		return 1, err
	}
	_ = inv
	if family == nil {
		return 1, fmt.Errorf("worktree family unavailable")
	}
	if store != nil {
		// Reconcile the family again after a clone/add and only then record use.
		if refreshed, refreshErr := enumerateFamily(ctx, family.anchor, scopeRoot(cfg)); refreshErr == nil {
			family = refreshed
			if err := store.reconcileFamily(ctx, family); err != nil {
				_, _ = fmt.Fprintf(stderr, "Warning: SQLite reconciliation failed: %v\n", err)
			}
			if refreshedRecord, findErr := findBranchRecord(family, spec.branch); findErr == nil && liveInventoryRecord(refreshedRecord) {
				record = refreshedRecord
			}
		}
	}
	if printOnly || ensureOnly {
		if store != nil {
			if err := store.upsertUsage(ctx, pathKey(record.Common, record.Path), unixMillis(cfg.now)); err != nil {
				_, _ = fmt.Fprintf(stderr, "Warning: could not record worktree use: %v\n", err)
			}
		}
		_, _ = fmt.Fprintln(stdout, record.Path)
		return 0, nil
	}
	if err := openTmux(ctx, cfg, record, stdin, stdout, stderr); err != nil {
		return 1, err
	}
	if store != nil {
		if err := store.upsertUsage(ctx, pathKey(record.Common, record.Path), unixMillis(cfg.now)); err != nil {
			_, _ = fmt.Fprintf(stderr, "Warning: could not record worktree use: %v\n", err)
		}
	}
	return 0, nil
}

func unixMillis(now func() time.Time) int64 {
	if now == nil {
		return 0
	}
	value := now().UnixMilli()
	if value < 0 {
		return 0
	}
	return value
}

func runList(ctx context.Context, cfg appConfig, stdout, stderr io.Writer) error {
	inv, store, usage := fastListInventory(ctx, cfg, stderr)
	if store != nil {
		defer store.close()
	}
	records := sortedFastListRecords(inv, usage)
	for _, record := range records {
		_, _ = fmt.Fprintln(stdout, record.Path)
	}
	return nil
}

func sortedLiveRecords(inv *inventory, usage map[usageKey]sql.NullInt64) []*inventoryRecord {
	records := make([]*inventoryRecord, 0)
	for _, record := range inv.inScopeRecords() {
		info, err := os.Stat(record.Path)
		if err != nil || !info.IsDir() || record.Prunable {
			continue
		}
		records = append(records, record)
	}
	sort.Slice(records, func(i, j int) bool {
		a, b := usageValue(usage, records[i].Common, records[i].Path), usageValue(usage, records[j].Common, records[j].Path)
		if a.Valid != b.Valid {
			return a.Valid
		}
		if a.Valid && a.Int64 != b.Int64 {
			return a.Int64 > b.Int64
		}
		return records[i].Path < records[j].Path
	})
	return records
}

func logicalLabel(cfg appConfig, record *inventoryRecord) string {
	branch := record.Branch
	if branch == "" {
		head := record.HEAD
		if len(head) > 12 {
			head = head[:12]
		}
		branch = "(detached@" + head + ")"
	}
	rel, err := filepath.Rel(scopeRoot(cfg), record.Path)
	if err == nil {
		parts := strings.Split(rel, string(filepath.Separator))
		if len(parts) >= 2 {
			return cfg.domain + "/" + strings.Join(parts[:2], "/") + "/" + branch
		}
	}
	return cfg.domain + "/" + branch
}

func resolveListedRecord(ctx context.Context, cfg appConfig, path string) (*inventoryRecord, error) {
	family, err := enumerateFamily(ctx, path, scopeRoot(cfg))
	if err != nil {
		return nil, fmt.Errorf("could not validate listed worktree %s: %w", path, err)
	}
	for i := range family.records {
		record := &family.records[i]
		if canonicalPath(record.Path) != canonicalPath(path) {
			continue
		}
		if !record.InScope {
			return nil, fmt.Errorf("listed worktree %s is outside the configured workspace root", path)
		}
		if !liveInventoryRecord(record) {
			return nil, fmt.Errorf("listed worktree %s is not live", path)
		}
		return record, nil
	}
	return nil, fmt.Errorf("listed path %s is not a Git worktree", path)
}

func runListFZF(ctx context.Context, cfg appConfig, stdin io.Reader, stdout, stderr io.Writer) error {
	inv, store, usage := fastListInventory(ctx, cfg, stderr)
	if store != nil {
		defer store.close()
	}
	records := sortedFastListRecords(inv, usage)
	var input strings.Builder
	byRow := make(map[string]*inventoryRecord)
	for _, record := range records {
		label := logicalLabel(cfg, record)
		byRow[label+"\x00"+canonicalPath(record.Path)] = record

		display := record.Path[(len(cfg.root) + len(cfg.domain) + 2):]
		input.WriteString(display)
		input.WriteByte('\n')
	}
	previewString := "--preview=git -C " + cfg.root + "/" + cfg.domain + "/{} --no-pager show"
	cmd := exec.CommandContext(ctx, "fzf", "--print-query", "--scheme=path", previewString)
	cmd.Stdin = strings.NewReader(input.String())
	var out, errOut bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errOut
	err := cmd.Run()
	status := 0
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			status = exitErr.ExitCode()
		} else {
			return err
		}
	}
	if status == 130 {
		return nil
	}
	lines := strings.Split(strings.TrimSuffix(out.String(), "\n"), "\n")
	if out.Len() == 0 {
		lines = nil
	}
	if status == 0 {
		if len(lines) != 2 || lines[1] == "" {
			return fmt.Errorf("fzf returned malformed selection")
		}
		selection := strings.Split(lines[1], "\t")
		if len(selection) != 2 {
			return fmt.Errorf("fzf returned an unknown selection")
		}
		candidate := byRow[selection[0]+"\x00"+canonicalPath(selection[1])]
		if candidate == nil {
			return fmt.Errorf("fzf returned an unknown selection")
		}
		record, err := resolveListedRecord(ctx, cfg, candidate.Path)
		if err != nil {
			return err
		}
		if err := openTmux(ctx, cfg, record, stdin, stdout, stderr); err != nil {
			return err
		}
		if store != nil {
			if err := store.upsertUsage(ctx, pathKey(record.Common, record.Path), unixMillis(cfg.now)); err != nil {
				_, _ = fmt.Fprintf(stderr, "Warning: could not record worktree use: %v\n", err)
			}
		}
		return nil
	}
	if status == 1 {
		if len(lines) > 1 {
			return fmt.Errorf("fzf returned malformed query")
		}
		query := ""
		if len(lines) > 0 {
			query = lines[0]
		}
		if query == "" {
			return nil
		}
		spec, parseErr := parseTarget(cfg, query)
		if parseErr != nil {
			return exitCodeError{code: 2, err: parseErr}
		}
		if _, branchErr := gitCheckBranch(ctx, spec.branch); branchErr != nil {
			return exitCodeError{code: 2, err: branchErr}
		}
		record, family, _, resolveErr := resolveTarget(ctx, cfg, spec, true, stderr)
		if resolveErr != nil {
			return resolveErr
		}
		if err := openTmux(ctx, cfg, record, stdin, stdout, stderr); err != nil {
			return err
		}
		if store != nil {
			_ = store.reconcileFamily(ctx, family)
			if err := store.upsertUsage(ctx, pathKey(record.Common, record.Path), unixMillis(cfg.now)); err != nil {
				_, _ = fmt.Fprintf(stderr, "Warning: could not record worktree use: %v\n", err)
			}
		}
		return nil
	}
	if errOut.Len() != 0 {
		return fmt.Errorf("fzf failed with status %d: %s", status, strings.TrimSpace(errOut.String()))
	}
	return fmt.Errorf("fzf failed with status %d", status)
}

func openTmux(ctx context.Context, cfg appConfig, record *inventoryRecord, stdin io.Reader, stdout, stderr io.Writer) error {
	if record == nil {
		return fmt.Errorf("cannot open an empty worktree")
	}
	branch := record.Branch
	if branch == "" {
		branch = "detached-" + record.HEAD
	}
	slug := cfg.domain + "-" + branch
	// The owner/repository are included in the path-derived label when known.
	if rel, err := filepath.Rel(scopeRoot(cfg), record.Path); err == nil {
		parts := strings.Split(rel, string(filepath.Separator))
		if len(parts) >= 2 {
			slug = parts[0] + "-" + parts[1] + "-" + branch
		}
	}
	var b strings.Builder
	for _, r := range slug {
		if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
			b.WriteRune(r)
		} else {
			b.WriteByte('-')
		}
	}
	slugBytes := []byte(b.String())
	if len(slugBytes) > 48 {
		slugBytes = slugBytes[:48]
	}
	hash := sha256.Sum256([]byte(canonicalPath(record.Path)))
	session := "f-" + string(slugBytes) + "-" + hex.EncodeToString(hash[:])[:12]
	has := exec.CommandContext(ctx, "tmux", "has-session", "-t", session)
	has.Stderr = stderr
	if err := has.Run(); err != nil {
		var exitErr *exec.ExitError
		if !errors.As(err, &exitErr) || exitErr.ExitCode() != 1 {
			return fmt.Errorf("tmux has-session failed: %w", err)
		}
		create := exec.CommandContext(ctx, "tmux", "new-session", "-ds", session, "-c", record.Path)
		if out, err := create.CombinedOutput(); err != nil {
			return fmt.Errorf("tmux new-session failed: %s: %w", strings.TrimSpace(string(out)), err)
		}
	}
	if cfg.getenv("TMUX") == "" {
		cmd := exec.CommandContext(ctx, "tmux", "attach-session", "-t", session)
		cmd.Stdin = stdin
		cmd.Stdout = stdout
		cmd.Stderr = stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("tmux attach-session failed: %w", err)
		}
	} else {
		cmd := exec.CommandContext(ctx, "tmux", "switch-client", "-t", session)
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("tmux switch-client failed: %s: %w", strings.TrimSpace(string(out)), err)
		}
	}
	return nil
}

func parseDays(value string) (int64, error) {
	if value == "" {
		return 0, fmt.Errorf("day count must not be empty")
	}
	for _, r := range value {
		if r < '0' || r > '9' {
			return 0, fmt.Errorf("day count must be a nonnegative decimal integer")
		}
	}
	days, err := strconv.ParseUint(value, 10, 64)
	if err != nil || days > uint64(^uint64(0)>>1)/uint64(24*time.Hour/time.Millisecond) {
		return 0, fmt.Errorf("day count overflows timestamp arithmetic")
	}
	return int64(days), nil
}

func ageCutoff(now time.Time, days int64) int64 {
	n := unixMillis(func() time.Time { return now })
	const dayMS = int64(24 * time.Hour / time.Millisecond)
	if days > (1<<63-1)/dayMS {
		return -(1 << 63)
	}
	delta := days * dayMS
	return n - delta
}
func importFilesystem(ctx context.Context, cfg appConfig, inv *inventory, store *advisoryStore, explicit bool, stderr io.Writer) (importSummary, error) {
	if store == nil {
		return importSummary{}, fmt.Errorf("SQLite advisory state unavailable")
	}
	now := unixMillis(cfg.now)
	// Each worktree is independent; overlap the metadata-heavy walks before the single database transaction.
	records := inv.inScopeRecords()
	type scanResult struct {
		scan    *importScan
		warning string
	}
	results := make([]*scanResult, len(records))
	jobs := make(chan int)
	workerCount := runtime.GOMAXPROCS(0)
	if workerCount < 4 {
		workerCount = 4
	}
	if workerCount > 16 {
		workerCount = 16
	}
	var workers sync.WaitGroup
	workers.Add(workerCount)
	for i := 0; i < workerCount; i++ {
		go func() {
			defer workers.Done()
			for index := range jobs {
				record := records[index]
				result := &scanResult{}
				if info, statErr := os.Stat(record.Path); errors.Is(statErr, os.ErrNotExist) {
					results[index] = result
					continue
				} else if statErr != nil || !info.IsDir() {
					result.scan = &importScan{key: pathKey(record.Common, record.Path), failed: true}
					if statErr != nil {
						result.warning = fmt.Sprintf("Warning: scan %s failed: %v\n", record.Path, statErr)
					}
					results[index] = result
					continue
				}
				value, scanErr := scanWorktree(record.Path, now)
				result.scan = &importScan{key: pathKey(record.Common, record.Path), value: value}
				if scanErr != nil {
					result.scan.failed = true
					result.warning = fmt.Sprintf("Warning: scan %s failed: %v\n", record.Path, scanErr)
				}
				results[index] = result
			}
		}()
	}
	for index := range records {
		jobs <- index
	}
	close(jobs)
	workers.Wait()

	scans := make([]importScan, 0, len(records))
	for _, result := range results {
		if result == nil {
			continue
		}
		if result.warning != "" {
			_, _ = io.WriteString(stderr, result.warning)
		}
		if result.scan != nil {
			scans = append(scans, *result.scan)
		}
	}
	complete := len(inv.errors) == 0
	for _, scan := range scans {
		if scan.failed {
			complete = false
		}
	}
	summary, err := store.applyImport(ctx, scans, complete)
	if err != nil {
		summary = importSummary{failed: len(scans)}
	}
	if explicit {
		_, _ = fmt.Fprintf(stderr, "Synced %d worktrees: %d updated, %d unchanged, %d unknown, %d failed\n", len(scans), summary.updated, summary.unchanged, summary.unknown, summary.failed)
	}
	if err != nil {
		return summary, err
	}
	if !complete {
		return summary, fmt.Errorf("filesystem import incomplete")
	}
	return summary, nil
}

func scanWorktree(path string, now int64) (*int64, error) {
	info, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("worktree path is not a directory")
	}
	var newest int64
	found := false
	err = filepath.WalkDir(path, func(current string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry == nil {
			return nil
		}
		if current != path && entry.Type()&os.ModeSymlink != 0 {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if current != path && (entry.Name() == ".git" || entry.Name() == "node_modules") {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if entry.IsDir() {
			return nil
		}
		if !entry.Type().IsRegular() {
			return nil
		}
		stat, err := entry.Info()
		if err != nil {
			return err
		}
		value := stat.ModTime().UnixMilli()
		if value < 0 {
			value = 0
		}
		if value > now {
			value = now
		}
		if !found || value > newest {
			newest, found = value, true
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	if !found {
		return nil, nil
	}
	return &newest, nil
}
func runSync(ctx context.Context, cfg appConfig, stdout, stderr io.Writer, stdin io.Reader) error {
	store, err := openStore(ctx, cfg.getenv)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "Error: SQLite advisory state unavailable: %v\n", err)
		return err
	}
	defer store.close()
	inv, discoverErr := discoverInventory(ctx, cfg)
	if discoverErr != nil {
		inv.errors = append(inv.errors, discoverErr)
	}
	reconcileOK := reconcileInventory(ctx, inv, store, stderr)
	if !reconcileOK {
		// Successful families are still scanned and committed; the marker is
		// deliberately withheld so a later sync retries the failed families.
		_, _ = fmt.Fprintln(stderr, "Warning: one or more Git repositories could not be reconciled")
	}
	if !reconcileOK {
		inv.errors = append(inv.errors, fmt.Errorf("SQLite reconciliation failed"))
	}
	_, importErr := importFilesystem(ctx, cfg, inv, store, true, stderr)
	if importErr != nil || !reconcileOK {
		if importErr != nil {
			_, _ = fmt.Fprintf(stderr, "Error: filesystem sync incomplete: %v\n", importErr)
		}
		return fmt.Errorf("sync incomplete")
	}
	return nil
}

type cleanupCandidate struct {
	record *inventoryRecord
	family *repoFamily
	label  string
	dead   bool
	stale  bool
	when   sql.NullInt64
	status string
}

func runCleanup(ctx context.Context, cfg appConfig, clean bool, dayText string, stdin io.Reader, stdout, stderr io.Writer) error {
	days, err := parseDays(dayText)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "Error: %v\n", err)
		return err
	}
	store, err := openStore(ctx, cfg.getenv)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "Error: SQLite advisory state unavailable: %v\n", err)
		return err
	}
	defer store.close()
	inv, discoverErr := discoverInventory(ctx, cfg)
	if discoverErr != nil {
		return discoverErr
	}
	if len(inv.errors) != 0 {
		for _, item := range inv.errors {
			_, _ = fmt.Fprintf(stderr, "Error: %v\n", item)
		}
		return fmt.Errorf("cannot safely reconcile all repositories")
	}
	if !reconcileInventory(ctx, inv, store, stderr) {
		return fmt.Errorf("cannot safely reconcile SQLite advisory state")
	}
	marked, err := store.marker(ctx)
	if err != nil {
		return err
	}
	if !marked {
		if _, importErr := importFilesystem(ctx, cfg, inv, store, false, stderr); importErr != nil {
			return fmt.Errorf("filesystem import has not completed: %w", importErr)
		}
		marked, err = store.marker(ctx)
		if err != nil {
			return err
		}
	}
	if !marked {
		return fmt.Errorf("filesystem import has not completed; run f sync")
	}
	usage, err := store.usage(ctx)
	if err != nil {
		return err
	}
	now := cfg.now()
	cutoff := ageCutoff(now, days)
	candidates := collectCleanupCandidates(cfg, inv, usage, cutoff, ctx, stderr)
	if len(candidates) == 0 {
		_, _ = fmt.Fprintf(stderr, "No worktrees found older than %s days\n", dayText)
		return nil
	}
	for _, candidate := range candidates {
		_, _ = fmt.Fprintf(stderr, "%s\t%s\t%s\n", candidate.status, candidate.label, candidate.record.Path)
	}
	if !clean {
		return nil
	}
	_, _ = fmt.Fprint(stderr, "Are you sure you want to delete these worktrees? (y/N): ")
	confirmation, readErr := readConfirmation(stdin)
	if readErr != nil {
		return readErr
	}
	if confirmation != "y" && confirmation != "Y" {
		_, _ = fmt.Fprintln(stderr, "Clean cancelled")
		return nil
	}
	removed, skipped, failed := 0, 0, 0
	for _, candidate := range candidates {
		if !candidate.dead {
			latestUsage, usageErr := store.usage(ctx)
			if usageErr != nil {
				return usageErr
			}
			latest := usageValue(latestUsage, candidate.record.Common, candidate.record.Path)
			if !latest.Valid || latest.Int64 > ageCutoff(cfg.now(), days) {
				skipped++
				continue
			}
		}
		ok, removedErr := removeCandidate(ctx, cfg, candidate, store, stderr)
		if removedErr != nil {
			failed++
			_, _ = fmt.Fprintf(stderr, "Failed %s: %v\n", candidate.record.Path, removedErr)
		} else if ok {
			removed++
		} else {
			skipped++
		}
	}
	_, _ = fmt.Fprintf(stderr, "Clean complete: removed %d, skipped %d, failed %d\n", removed, skipped, failed)
	if failed != 0 {
		return fmt.Errorf("one or more requested removals failed")
	}
	return nil
}

func readConfirmation(r io.Reader) (string, error) {
	line, err := bufio.NewReader(r).ReadString('\n')
	if err != nil && err != io.EOF {
		return "", err
	}
	return strings.TrimSpace(line), nil

}

func collectCleanupCandidates(cfg appConfig, inv *inventory, usage map[usageKey]sql.NullInt64, cutoff int64, ctx context.Context, stderr io.Writer) []cleanupCandidate {
	var candidates []cleanupCandidate
	for _, record := range inv.inScopeRecords() {
		family := inv.familyForCommon(record.Common)
		if record.Primary {
			continue
		}
		value := usageValue(usage, record.Common, record.Path)
		info, statErr := os.Stat(record.Path)
		missing := errors.Is(statErr, os.ErrNotExist) || (statErr == nil && (info == nil || !info.IsDir()))
		if statErr != nil && !missing {
			_, _ = fmt.Fprintf(stderr, "Warning: cannot inspect %s: %v\n", record.Path, statErr)
			continue
		}
		if missing {
			if record.Locked {
				candidates = append(candidates, cleanupCandidate{record: record, family: family, label: logicalLabel(cfg, record), dead: true, status: "locked"})
			} else {
				candidates = append(candidates, cleanupCandidate{record: record, family: family, label: logicalLabel(cfg, record), dead: true, status: "dead"})
			}
			continue
		}
		if info == nil || !info.IsDir() || !value.Valid || value.Int64 > cutoff {
			continue
		}
		status := "stale"
		if record.Locked {
			status = "locked"
		} else if dirty, err := gitStatusDirty(ctx, record.Path); err != nil {
			status = "dirty"
		} else if dirty {
			status = "dirty"
		} else if tmuxWorktreeActive(ctx, cfg, record) {
			status = "active"
		}
		candidates = append(candidates, cleanupCandidate{record: record, family: family, label: logicalLabel(cfg, record), stale: true, when: value, status: status})
	}
	sort.SliceStable(candidates, func(i, j int) bool {
		if candidates[i].dead != candidates[j].dead {
			return !candidates[i].dead
		}
		if candidates[i].when.Valid != candidates[j].when.Valid {
			return !candidates[i].when.Valid
		}
		if candidates[i].when.Valid && candidates[i].when.Int64 != candidates[j].when.Int64 {
			return candidates[i].when.Int64 < candidates[j].when.Int64
		}
		return candidates[i].record.Path < candidates[j].record.Path
	})
	return candidates
}

func tmuxWorktreeActive(ctx context.Context, cfg appConfig, record *inventoryRecord) bool {
	branch := record.Branch
	if branch == "" {
		branch = "detached-" + record.HEAD
	}
	slug := branch
	if rel, err := filepath.Rel(scopeRoot(cfg), record.Path); err == nil {
		parts := strings.Split(rel, string(filepath.Separator))
		if len(parts) >= 2 {
			slug = parts[0] + "-" + parts[1] + "-" + branch
		}
	}
	var b strings.Builder
	for _, r := range slug {
		if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
			b.WriteRune(r)
		} else {
			b.WriteByte('-')
		}
	}
	s := []byte(b.String())
	if len(s) > 48 {
		s = s[:48]
	}
	h := sha256.Sum256([]byte(canonicalPath(record.Path)))
	session := "f-" + string(s) + "-" + hex.EncodeToString(h[:])[:12]
	check := exec.CommandContext(ctx, "tmux", "has-session", "-t", session)
	if err := check.Run(); err == nil {
		return true
	} else {
		var ee *exec.ExitError
		if !errors.As(err, &ee) || ee.ExitCode() != 1 {
			return true
		}
	}
	pane := exec.CommandContext(ctx, "tmux", "list-panes", "-a", "-F", "#{pane_current_path}")
	out, err := pane.Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) && ee.ExitCode() == 1 && strings.Contains(strings.ToLower(string(ee.Stderr)), "no server") {
			return false // no tmux server
		}
		return true
	}
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if line != "" && (canonicalPath(line) == canonicalPath(record.Path) || pathInside(line, record.Path)) {
			return true
		}
	}
	return false
}

func removeCandidate(ctx context.Context, cfg appConfig, candidate cleanupCandidate, store *advisoryStore, stderr io.Writer) (bool, error) {
	record := candidate.record
	family := candidate.family
	if family == nil || family.anchor == "" {
		return false, fmt.Errorf("worktree family anchor is unavailable")
	}
	freshFamily, err := enumerateFamily(ctx, family.anchor, scopeRoot(cfg))
	if err != nil {
		return false, err
	}
	family = freshFamily
	fresh, findErr := findBranchRecord(family, record.Branch)
	if record.Branch == "" {
		for i := range family.records {
			if canonicalPath(family.records[i].Path) == canonicalPath(record.Path) {
				fresh = &family.records[i]
			}
		}
	} else if findErr != nil || fresh == nil || canonicalPath(fresh.Path) != canonicalPath(record.Path) {
		return false, nil
	}
	if fresh == nil || fresh.Primary || fresh.Locked {
		return false, nil
	}
	info, statErr := os.Stat(record.Path)
	if errors.Is(statErr, os.ErrNotExist) {
		if candidate.dead || candidate.status == "dead" {
			return pruneDead(ctx, cfg, family, record, store, stderr)
		}
		return false, nil
	}
	if statErr != nil || !info.IsDir() {
		return false, nil
	}

	dirty, err := gitStatusDirty(ctx, record.Path)
	if err != nil || dirty {
		return false, nil
	}
	if tmuxWorktreeActive(ctx, cfg, record) {
		return false, nil
	}
	if err := gitRun(ctx, family.anchor, []string{"worktree", "remove", record.Path}, nil, io.Discard, stderr); err != nil {
		return false, err
	}
	if store != nil {
		if err := store.deleteUsage(ctx, pathKey(record.Common, record.Path)); err != nil {
			return true, err
		}
	}
	return true, nil
}

func pruneDead(ctx context.Context, cfg appConfig, family *repoFamily, record *inventoryRecord, store *advisoryStore, stderr io.Writer) (bool, error) {
	entries, err := os.ReadDir(filepath.Join(family.common, "worktrees"))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, nil
		}
		return false, err
	}
	allowed := make(map[string]bool)
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		gitdir, err := os.ReadFile(filepath.Join(family.common, "worktrees", entry.Name(), "gitdir"))
		if err != nil {
			return false, err
		}
		path := strings.TrimSpace(string(gitdir))
		if !filepath.IsAbs(path) {
			path = filepath.Join(family.common, path)
		}
		path = canonicalPath(filepath.Dir(path))
		if path == canonicalPath(record.Path) && pathInside(path, scopeRoot(cfg)) && !record.Locked {
			allowed[entry.Name()] = true
		}
	}
	if len(allowed) == 0 {
		return false, nil
	}
	dryOut, dryErr := runGitPruneDry(ctx, family.anchor)
	if dryErr != nil {
		return false, dryErr
	}
	for _, line := range strings.Split(dryOut, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if !strings.HasPrefix(line, "Removing ") {
			return false, nil
		}
		rest := strings.TrimPrefix(line, "Removing ")
		name := rest
		if index := strings.IndexByte(name, ':'); index >= 0 {
			name = name[:index]
		}
		name = filepath.Base(filepath.Clean(name))
		if !allowed[name] {
			return false, nil
		}
	}
	if err := gitRun(ctx, family.anchor, []string{"worktree", "prune", "--expire=now"}, nil, io.Discard, stderr); err != nil {
		return false, err
	}
	fresh, freshErr := enumerateFamily(ctx, family.anchor, scopeRoot(cfg))
	if freshErr != nil {
		return false, freshErr
	}
	for _, freshRecord := range fresh.records {
		if canonicalPath(freshRecord.Path) == canonicalPath(record.Path) {
			return false, nil
		}
	}
	if store != nil {
		if err := store.deleteUsage(ctx, pathKey(record.Common, record.Path)); err != nil {
			return true, err
		}
	}
	return true, nil
}

func runGitPruneDry(ctx context.Context, anchor string) (string, error) {
	cmd := gitCommand(ctx, anchor, "worktree", "prune", "--dry-run", "--verbose", "--expire=now")
	cmd.Env = append(os.Environ(), "LC_ALL=C")
	var out, errOut bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errOut
	if err := cmd.Run(); err != nil {
		return "", &gitFailure{op: "worktree prune --dry-run --verbose --expire=now", stderr: errOut.String(), err: err}
	}
	return out.String(), nil
}

func runDelete(ctx context.Context, cfg appConfig, target string, stdin io.Reader, stdout, stderr io.Writer) error {
	inv, store, _ := prepareInventory(ctx, cfg, stderr)
	if store != nil {
		defer store.close()
	}
	var record *inventoryRecord
	var err error
	if target != "" {
		spec, parseErr := parseTarget(cfg, target)
		if parseErr != nil {
			_, _ = fmt.Fprintf(stderr, "Error: %v\n", parseErr)
			printUsage(stderr)
			return exitCodeError{code: 2, err: parseErr}
		}
		for _, candidate := range inv.inScopeRecords() {
			if candidate.Branch == spec.branch && pathInside(candidate.Path, spec.repoRoot) {
				record = candidate
				break
			}
		}
		if record == nil {
			return fmt.Errorf("requested worktree is not registered")
		}
	} else {
		// Deletion without a target uses the same inventory rows as -l. The
		// first fzf output is intentionally required to identify one exact row.
		record, err = chooseFZFRecord(ctx, cfg, inv, stderr)
		if err != nil {
			return err
		}
		if record == nil {
			return nil
		}
	}
	_, _ = fmt.Fprintf(stderr, "Delete %s (%s)? (y/N): ", logicalLabel(cfg, record), record.Path)
	answer, err := readConfirmation(stdin)
	if err != nil {
		return err
	}
	if answer != "y" && answer != "Y" {
		return nil
	}
	removed, err := removeCandidate(ctx, cfg, cleanupCandidate{record: record, family: inv.familyForCommon(record.Common), stale: true}, store, stderr)
	if err != nil {
		return err
	}
	if !removed {
		return fmt.Errorf("worktree is protected or changed")
	}
	return nil
}

func chooseFZFRecord(ctx context.Context, cfg appConfig, inv *inventory, stderr io.Writer) (*inventoryRecord, error) {
	records := sortedLiveRecords(inv, nil)
	byRow := make(map[string]*inventoryRecord)
	var input strings.Builder
	for _, record := range records {
		label := logicalLabel(cfg, record)
		key := label + "\x00" + canonicalPath(record.Path)
		byRow[key] = record
		fmt.Fprintf(&input, "%s\t%s\n", label, record.Path)
	}
	cmd := exec.CommandContext(ctx, "fzf", "--print-query", "--scheme=path")
	cmd.Stdin = strings.NewReader(input.String())
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, stderr
	if err := cmd.Run(); err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			if ee.ExitCode() == 130 || (ee.ExitCode() == 1 && out.Len() == 0) {
				return nil, nil
			}
		}
		return nil, err
	}
	lines := strings.Split(strings.TrimSuffix(out.String(), "\n"), "\n")
	if len(lines) != 2 {
		return nil, fmt.Errorf("fzf returned malformed selection")
	}
	fields := strings.Split(lines[1], "\t")
	if len(fields) != 2 {
		return nil, fmt.Errorf("fzf returned unknown selection")
	}
	record := byRow[fields[0]+"\x00"+canonicalPath(fields[1])]
	if record == nil {
		return nil, fmt.Errorf("fzf returned unknown selection")
	}
	return record, nil
}
