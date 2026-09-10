package main

import (
	"bytes"
	"context"
	"database/sql"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func gitTestCommand(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	if err := cmd.Run(); err != nil {
		t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out.String())
	}
	return out.String()
}

func setupLocalRemote(t *testing.T) (root, bare string) {
	t.Helper()
	tmp := t.TempDir()
	root = filepath.Join(tmp, "code")
	bare = filepath.Join(tmp, "remotes", "acme", "demo.git")
	if err := os.MkdirAll(filepath.Dir(bare), 0o755); err != nil {
		t.Fatal(err)
	}
	gitTestCommand(t, "", "init", "--bare", "--initial-branch=main", bare)
	seed := filepath.Join(tmp, "seed")
	gitTestCommand(t, "", "clone", bare, seed)
	gitTestCommand(t, seed, "config", "user.name", "f test")
	gitTestCommand(t, seed, "config", "user.email", "f@example.invalid")
	gitTestCommand(t, seed, "config", "commit.gpgsign", "false")
	if err := os.WriteFile(filepath.Join(seed, "tracked.txt"), []byte("tracked\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitTestCommand(t, seed, "add", "tracked.txt")
	gitTestCommand(t, seed, "commit", "-m", "initial")
	gitTestCommand(t, seed, "push", "origin", "main")
	global := filepath.Join(tmp, "gitconfig")
	config := fmt.Sprintf("[url %q]\n\tinsteadOf = git@test.invalid:acme/\n", filepath.Join(tmp, "remotes", "acme")+string(filepath.Separator))
	if err := os.WriteFile(global, []byte(config), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GIT_CONFIG_GLOBAL", global)
	return root, bare
}

func testEnv(root, state string) func(string) string {
	return func(key string) string {
		switch key {
		case "HOME":
			return filepath.Dir(root)
		case "XDG_STATE_HOME":
			return state
		default:
			return os.Getenv(key)
		}
	}
}

func invokeRun(t *testing.T, root, state string, args ...string) (int, string, string) {
	t.Helper()
	var stdout, stderr bytes.Buffer
	env := testEnv(root, state)
	code := run(context.Background(), append([]string{"-r", root, "-g", "test.invalid"}, args...), strings.NewReader(""), &stdout, &stderr, env, func() time.Time { return time.Unix(2_000_000_000, 0) })
	return code, stdout.String(), stderr.String()
}

func TestWorktreeAddArgs(t *testing.T) {
	tests := []struct {
		name   string
		local  bool
		remote bool
		def    string
		want   []string
	}{
		{name: "local", local: true, want: []string{"worktree", "add", "/tmp/wt", "feature"}},
		{name: "remote", remote: true, want: []string{"worktree", "add", "--track", "-b", "feature", "/tmp/wt", "origin/feature"}},
		{name: "new from default", def: "main", want: []string{"worktree", "add", "-b", "feature", "/tmp/wt", "refs/remotes/origin/main"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := worktreeAddArgs("/tmp/wt", "feature", tt.local, tt.remote, tt.def)
			if strings.Join(got, "\x00") != strings.Join(tt.want, "\x00") {
				t.Fatalf("args=%v want %v", got, tt.want)
			}
			count := 0
			for _, arg := range got {
				if arg == "/tmp/wt" {
					count++
				}
			}
			if count != 1 {
				t.Fatalf("destination appears %d times in %v", count, got)
			}
		})
	}
}

func TestParseRemoteHeadAndPorcelainZ(t *testing.T) {
	branch, err := parseRemoteHead("ref: refs/heads/feature/login\tHEAD\n0123\tHEAD\n")
	if err != nil || branch != "feature/login" {
		t.Fatalf("remote head=%q err=%v", branch, err)
	}
	data := []byte("worktree /tmp/main\x00HEAD abc\x00branch refs/heads/main\x00\x00worktree /tmp/link\x00HEAD def\x00detached\x00\x00")
	records := parseWorktreePorcelain(data)
	if len(records) != 2 {
		t.Fatalf("records=%+v", records)
	}
	if !records[0].Primary || records[0].Branch != "main" || records[1].Branch != "" || !records[1].Detached {
		t.Fatalf("records=%+v", records)
	}
}

func TestCanonicalDiscoveryUsesFixedDepth(t *testing.T) {
	root := t.TempDir()
	scope := filepath.Join(root, "test.invalid")
	primary := filepath.Join(scope, "acme", "demo", "main")
	gitTestCommand(t, "", "init", "--initial-branch=main", primary)
	gitTestCommand(t, primary, "config", "user.name", "f test")
	gitTestCommand(t, primary, "config", "user.email", "f@example.invalid")
	gitTestCommand(t, primary, "config", "commit.gpgsign", "false")
	gitTestCommand(t, primary, "commit", "--allow-empty", "-m", "initial")
	linked := filepath.Join(scope, "acme", "demo", "feature%2Flogin")
	gitTestCommand(t, primary, "worktree", "add", "-b", "feature/login", linked)
	noncanonical := filepath.Join(scope, "acme", "demo", "legacy", "deep")
	if err := os.MkdirAll(filepath.Dir(noncanonical), 0o755); err != nil {
		t.Fatal(err)
	}
	gitTestCommand(t, primary, "worktree", "add", "-b", "legacy/deep", noncanonical)

	deep := filepath.Join(scope, "acme", "deep", "repo", "feature", "login")
	gitTestCommand(t, "", "init", "--initial-branch=main", deep)
	outside := t.TempDir()
	if err := os.MkdirAll(filepath.Join(outside, "repo", "branch"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(outside, "repo"), filepath.Join(scope, "symlink-owner")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(outside, "repo"), filepath.Join(scope, "acme", "symlink-repo")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(outside, "repo", "branch"), filepath.Join(scope, "acme", "demo", "symlink-branch")); err != nil {
		t.Fatal(err)
	}

	inv, err := discoverInventory(context.Background(), appConfig{root: root, domain: "test.invalid"})
	if err != nil {
		t.Fatal(err)
	}
	if len(inv.errors) != 0 {
		t.Fatalf("inventory errors=%v", inv.errors)
	}
	seen := make(map[string]*inventoryRecord)
	for _, record := range inv.managedRecords() {
		seen[canonicalPath(record.Path)] = record
	}
	if len(seen) != 2 || seen[canonicalPath(primary)] == nil || seen[canonicalPath(linked)] == nil {
		t.Fatalf("managed records=%v", seen)
	}
	if seen[canonicalPath(linked)].Branch != "feature/login" {
		t.Fatalf("linked branch=%q", seen[canonicalPath(linked)].Branch)
	}
	if _, ok := seen[canonicalPath(deep)]; ok {
		t.Fatalf("deep-only worktree was discovered: %s", deep)
	}
	if len(inv.families) != 1 || len(inv.families[0].records) != 3 {
		t.Fatalf("family records=%v", inv.families)
	}
	var noncanonicalRecord *inventoryRecord
	for i := range inv.families[0].records {
		record := &inv.families[0].records[i]
		if canonicalPath(record.Path) == canonicalPath(noncanonical) {
			noncanonicalRecord = record
			if record.Managed {
				t.Fatal("noncanonical record is managed")
			}
		}
	}
	if noncanonicalRecord == nil {
		t.Fatalf("family records=%v", inv.families[0].records)
	}
	found, err := findBranchRecord(inv.families[0], "legacy/deep")
	if err != nil || found == nil || canonicalPath(found.Path) != canonicalPath(noncanonical) {
		t.Fatalf("branch lookup=%v err=%v", found, err)
	}
	state := filepath.Join(root, "state")
	cfg := appConfig{root: root, domain: "test.invalid", now: func() time.Time { return time.Unix(100, 0) }, getenv: func(key string) string {
		if key == "XDG_STATE_HOME" {
			return state
		}
		return ""
	}}
	store, err := openStore(context.Background(), cfg.getenv)
	if err != nil {
		t.Fatal(err)
	}
	defer store.close()
	if err := store.reconcileFamily(context.Background(), inv.families[0]); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(noncanonical, "import-only"), []byte("unmanaged"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(filepath.Join(noncanonical, "import-only"), time.Unix(2, 0), time.Unix(2, 0)); err != nil {
		t.Fatal(err)
	}
	if _, err := importFilesystem(context.Background(), cfg, inv, store, false, io.Discard); err != nil {
		t.Fatal(err)
	}
	usageRows, err := store.usage(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	noncanonicalUsage, ok := usageRows[pathKey(inv.families[0].common, noncanonical)]
	if !ok || noncanonicalUsage.Valid {
		t.Fatalf("noncanonical usage=%+v present=%v", noncanonicalUsage, ok)
	}
	var listOut, listErr bytes.Buffer
	if err := runList(context.Background(), cfg, &listOut, &listErr); err != nil {
		t.Fatalf("list err=%v stderr=%s", err, listErr.String())
	}
	listSeen := make(map[string]bool)
	for _, line := range strings.Split(strings.TrimSpace(listOut.String()), "\n") {
		if line != "" {
			listSeen[canonicalPath(line)] = true
		}
	}
	if len(listSeen) != 2 || !listSeen[canonicalPath(primary)] || !listSeen[canonicalPath(linked)] || listSeen[canonicalPath(noncanonical)] {
		t.Fatalf("list=%v", listSeen)
	}
	usage := map[usageKey]sql.NullInt64{
		pathKey(inv.families[0].common, noncanonical): {Valid: true, Int64: 0},
		pathKey(inv.families[0].common, linked):       {Valid: true, Int64: 0},
	}
	for _, candidate := range collectCleanupCandidates(cfg, inv, usage, 1, context.Background(), io.Discard) {
		if canonicalPath(candidate.record.Path) == canonicalPath(noncanonical) {
			t.Fatal("noncanonical record became a cleanup candidate")
		}
	}
	spec, err := parseTarget(cfg, "acme/demo/legacy/deep")
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := resolveTarget(context.Background(), cfg, inv, spec, false, io.Discard); err == nil || !strings.Contains(err.Error(), "canonical workspace layout") {
		t.Fatalf("direct noncanonical target error=%v", err)
	}
}

func TestCanonicalFastListUsesValidatedMarkers(t *testing.T) {
	root := t.TempDir()
	scope := filepath.Join(root, "test.invalid")
	primary := filepath.Join(scope, "acme", "demo", "main")
	gitTestCommand(t, "", "init", "--initial-branch=main", primary)
	gitTestCommand(t, primary, "config", "user.name", "f test")
	gitTestCommand(t, primary, "config", "user.email", "f@example.invalid")
	gitTestCommand(t, primary, "config", "commit.gpgsign", "false")
	gitTestCommand(t, primary, "commit", "--allow-empty", "-m", "initial")
	linked := filepath.Join(scope, "acme", "demo", "feature%2Flogin")
	gitTestCommand(t, primary, "worktree", "add", "-b", "feature/login", linked)
	bogus := filepath.Join(scope, "acme", "demo", "bogus")
	if err := os.MkdirAll(bogus, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bogus, ".git"), []byte("not a git marker"), 0o644); err != nil {
		t.Fatal(err)
	}
	outside := t.TempDir()
	if err := os.MkdirAll(outside, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(scope, "acme", "demo", "symlink-branch")); err != nil {
		t.Fatal(err)
	}

	paths, err := discoverFilesystemWorktrees(scope)
	if err != nil {
		t.Fatal(err)
	}
	seen := make(map[string]bool, len(paths))
	for _, path := range paths {
		seen[canonicalPath(path)] = true
	}
	if len(seen) != 2 || !seen[canonicalPath(primary)] || !seen[canonicalPath(linked)] {
		t.Fatalf("paths=%v", paths)
	}
	if got := filesystemBranch(scope, linked); got != "feature/login" {
		t.Fatalf("filesystem branch=%q", got)
	}
	state := filepath.Join(root, "state")
	getenv := func(key string) string {
		if key == "XDG_STATE_HOME" {
			return state
		}
		return ""
	}
	inv, store, _ := fastListInventory(context.Background(), appConfig{root: root, domain: "test.invalid", getenv: getenv}, io.Discard)
	if store != nil {
		defer store.close()
	}
	if len(inv.records) != 2 {
		t.Fatalf("fast inventory=%v", inv.records)
	}
	for _, record := range inv.records {
		if !record.InScope || !record.Managed {
			t.Fatalf("record flags=%+v", record)
		}
	}
}

func TestRunListDoesNotReconcileGitBeforePrinting(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "test.invalid", "acme", "demo", "main")
	gitTestCommand(t, "", "init", "--initial-branch=main", path)
	gitTestCommand(t, path, "config", "user.name", "f test")
	gitTestCommand(t, path, "config", "user.email", "f@example.invalid")
	gitTestCommand(t, path, "config", "commit.gpgsign", "false")
	gitTestCommand(t, path, "commit", "--allow-empty", "-m", "initial")
	bogus := filepath.Join(root, "test.invalid", "acme", "demo", "bogus")
	if err := os.MkdirAll(bogus, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bogus, ".git"), []byte("unvalidated marker"), 0o644); err != nil {
		t.Fatal(err)
	}
	tools := t.TempDir()
	if err := os.WriteFile(filepath.Join(tools, "git"), []byte("#!/bin/sh\nexit 99\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", tools+string(filepath.ListSeparator)+os.Getenv("PATH"))
	state := filepath.Join(filepath.Dir(root), "state")
	var stdout, stderr bytes.Buffer
	code := run(context.Background(), []string{"-r", root, "-g", "test.invalid", "-L"}, strings.NewReader(""), &stdout, &stderr, testEnv(root, state), time.Now)
	if code != 0 {
		t.Fatalf("list code=%d stderr=%s", code, stderr.String())
	}
	if got := strings.TrimSpace(stdout.String()); got != canonicalPath(path) {
		t.Fatalf("list=%q want %q", got, canonicalPath(path))
	}
}

func TestRunCreatesEscapedWorktreesAndListsAuthoritativeGit(t *testing.T) {
	root, _ := setupLocalRemote(t)
	state := filepath.Join(filepath.Dir(root), "state")
	code, out, stderr := invokeRun(t, root, state, "-e", "acme/demo/main")
	if code != 0 {
		t.Fatalf("default creation code=%d stderr=%s", code, stderr)
	}
	mainPath := filepath.Join(root, "test.invalid", "acme", "demo", "main")
	if canonicalPath(strings.TrimSpace(out)) != canonicalPath(mainPath) {
		t.Fatalf("default path=%q want %q", strings.TrimSpace(out), mainPath)
	}
	if err := os.WriteFile(filepath.Join(mainPath, "local-only"), []byte("not copied\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, out, stderr = invokeRun(t, root, state, "-e", "acme/demo/feature/login")
	if code != 0 {
		t.Fatalf("linked creation code=%d stderr=%s", code, stderr)
	}
	featurePath := filepath.Join(root, "test.invalid", "acme", "demo", "feature%2Flogin")
	if canonicalPath(strings.TrimSpace(out)) != canonicalPath(featurePath) {
		t.Fatalf("feature path=%q want %q", strings.TrimSpace(out), featurePath)
	}
	branch := strings.TrimSpace(gitTestCommand(t, featurePath, "branch", "--show-current"))
	if branch != "feature/login" {
		t.Fatalf("branch=%q", branch)
	}
	if _, err := os.Stat(filepath.Join(featurePath, "local-only")); !os.IsNotExist(err) {
		t.Fatalf("untracked file copied into linked worktree: err=%v", err)
	}
	code, out, stderr = invokeRun(t, root, state, "-L")
	if code != 0 {
		t.Fatalf("list code=%d stderr=%s", code, stderr)
	}
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) != 2 {
		t.Fatalf("list=%q", lines)
	}
	seen := map[string]bool{}
	for _, line := range lines {
		seen[canonicalPath(line)] = true
	}
	if !seen[canonicalPath(mainPath)] || !seen[canonicalPath(featurePath)] {
		t.Fatalf("list=%q", lines)
	}
	missing := filepath.Join(root, "test.invalid", "acme", "demo", "missing")
	code, _, _ = invokeRun(t, root, state, "-p", "acme/demo/missing")
	if code == 0 {
		t.Fatal("-p unexpectedly created missing worktree")
	}
	if _, err := os.Stat(missing); !os.IsNotExist(err) {
		t.Fatalf("-p changed missing destination: %v", err)
	}
}

func TestRunFZFSelectionQueryAndStatuses(t *testing.T) {
	root, _ := setupLocalRemote(t)
	state := filepath.Join(filepath.Dir(root), "state")
	if code, _, stderr := invokeRun(t, root, state, "-e", "acme/demo/main"); code != 0 {
		t.Fatalf("create default code=%d stderr=%s", code, stderr)
	}
	mainPath := filepath.Join(root, "test.invalid", "acme", "demo", "main")
	tools := t.TempDir()
	tmuxLog := filepath.Join(tools, "tmux.log")
	argsLog := filepath.Join(tools, "fzf-args.log")
	writeTool := func(name, content string) {
		t.Helper()
		path := filepath.Join(tools, name)
		if err := os.WriteFile(path, []byte(content), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	writeTool("tmux", fmt.Sprintf("#!/bin/sh\nprintf '%%s\\n' \"$*\" >> %q\ncase \"$1\" in has-session) exit 1;; list-panes) echo 'no server' >&2; exit 1;; esac\nexit 0\n", tmuxLog))
	t.Setenv("PATH", tools+string(filepath.ListSeparator)+os.Getenv("PATH"))
	runWithInput := func(input string, args ...string) (int, string, string) {
		var stdout, stderr bytes.Buffer
		code := run(context.Background(), append([]string{"-r", root, "-g", "test.invalid"}, args...), strings.NewReader(input), &stdout, &stderr, testEnv(root, state), func() time.Time { return time.Unix(2_000_000_000, 0) })
		return code, stdout.String(), stderr.String()
	}
	writeTool("fzf", fmt.Sprintf("#!/bin/sh\nprintf '%%s\\n' \"$*\" >> %q\nIFS= read -r row\nprintf '\\n%%s\\n' \"$row\"\nexit 0\n", argsLog))
	code, _, stderr := runWithInput("", "-l")
	if code != 0 {
		t.Fatalf("fzf select code=%d stderr=%s", code, stderr)
	}
	argsData, err := os.ReadFile(argsLog)
	if err != nil || !strings.Contains(string(argsData), "--delimiter=\\t") || !strings.Contains(string(argsData), "--with-nth=1") {
		t.Fatalf("fzf args=%q err=%v", argsData, err)
	}
	tmuxData, err := os.ReadFile(tmuxLog)
	if err != nil || !strings.Contains(string(tmuxData), "new-session") || !strings.Contains(string(tmuxData), mainPath) {
		t.Fatalf("tmux selection log=%q err=%v", tmuxData, err)
	}
	before, _ := os.ReadFile(tmuxLog)
	writeTool("fzf", "#!/bin/sh\nexit 130\n")
	if code, _, _ := runWithInput("", "-l"); code != 0 {
		t.Fatalf("fzf cancellation code=%d", code)
	}
	after, _ := os.ReadFile(tmuxLog)
	if string(before) != string(after) {
		t.Fatal("fzf cancellation opened tmux")
	}
	writeTool("fzf", "#!/bin/sh\ncat >/dev/null\nprintf 'acme/demo/newbranch\\n'\nexit 1\n")
	if code, _, stderr := runWithInput("", "-l"); code != 0 {
		t.Fatalf("fzf query code=%d stderr=%s", code, stderr)
	}
	newPath := filepath.Join(root, "test.invalid", "acme", "demo", "newbranch")
	if _, err := os.Stat(newPath); err != nil {
		t.Fatalf("query-created worktree missing: %v", err)
	}
	writeTool("fzf", "#!/bin/sh\ncat >/dev/null\nprintf 'acme/demo/bad..branch\\n'\nexit 1\n")
	if code, _, _ := runWithInput("", "-l"); code != 2 {
		t.Fatalf("malformed fzf query code=%d", code)
	}
	writeTool("fzf", "#!/bin/sh\nexit 2\n")
	if code, _, _ := runWithInput("", "-l"); code != 1 {
		t.Fatalf("fzf error code=%d", code)
	}
}

func TestTmuxSessionNameFallback(t *testing.T) {
	tools := t.TempDir()
	logPath := filepath.Join(tools, "tmux.log")
	if err := os.WriteFile(filepath.Join(tools, "tmux"), []byte(fmt.Sprintf("#!/bin/sh\nprintf '%%s\\n' \"$*\" >> %q\ncase \"$1\" in has-session) exit 1;; list-panes) echo 'no server' >&2; exit 1;; esac\nexit 0\n", logPath)), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", tools+string(filepath.ListSeparator)+os.Getenv("PATH"))
	path := filepath.Join(t.TempDir(), "outside")
	if err := os.Mkdir(path, 0o755); err != nil {
		t.Fatal(err)
	}
	cfg := appConfig{root: filepath.Join(t.TempDir(), "code"), domain: "test.invalid", getenv: func(key string) string {
		if key == "TMUX" {
			return "1"
		}
		return ""
	}}
	record := &inventoryRecord{gitWorktreeRecord: gitWorktreeRecord{Path: path, Branch: "branch"}}
	want := tmuxSessionName(cfg, record)
	if err := openTmux(context.Background(), cfg, record, strings.NewReader(""), io.Discard, io.Discard); err != nil {
		t.Fatal(err)
	}
	_ = tmuxWorktreeActive(context.Background(), cfg, record)
	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	var hasSessions []string
	for _, line := range lines {
		if strings.HasPrefix(line, "has-session ") {
			hasSessions = append(hasSessions, line)
		}
	}
	if len(hasSessions) != 2 || hasSessions[0] != "has-session -t "+want || hasSessions[1] != hasSessions[0] {
		t.Fatalf("has-session calls=%v want %q", hasSessions, want)
	}
}

func TestBranchDestinationCollisionsAndTrackedDirenv(t *testing.T) {
	root, _ := setupLocalRemote(t)
	state := filepath.Join(filepath.Dir(root), "state")
	if code, _, stderr := invokeRun(t, root, state, "-e", "acme/demo/main"); code != 0 {
		t.Fatalf("default creation code=%d stderr=%s", code, stderr)
	}
	if code, _, stderr := invokeRun(t, root, state, "-e", "acme/demo/feature/login"); code != 0 {
		t.Fatalf("feature creation code=%d stderr=%s", code, stderr)
	}
	if code, _, stderr := invokeRun(t, root, state, "-e", "acme/demo/feature/login-extra"); code != 0 {
		t.Fatalf("prefix feature creation code=%d stderr=%s", code, stderr)
	}
	escaped := filepath.Join(root, "test.invalid", "acme", "demo", "feature%2Flogin")
	escapedPrefix := filepath.Join(root, "test.invalid", "acme", "demo", "feature%2Flogin-extra")
	for _, path := range []string{escaped, escapedPrefix} {
		if _, err := os.Stat(path); err != nil {
			t.Fatal(err)
		}
	}
	occupied := filepath.Join(root, "test.invalid", "acme", "demo", "occupied")
	if err := os.WriteFile(occupied, []byte("occupied"), 0o644); err != nil {
		t.Fatal(err)
	}
	if code, _, _ := invokeRun(t, root, state, "-e", "acme/demo/occupied"); code == 0 {
		t.Fatal("occupied destination unexpectedly succeeded")
	}
	upper := filepath.Join(root, "test.invalid", "acme", "demo", "UPPER")
	if err := os.Mkdir(upper, 0o755); err != nil {
		t.Fatal(err)
	}
	if code, _, _ := invokeRun(t, root, state, "-e", "acme/demo/upper"); code == 0 {
		t.Fatal("case-folding destination unexpectedly succeeded")
	}
	mainPath := filepath.Join(root, "test.invalid", "acme", "demo", "main")
	if err := os.WriteFile(filepath.Join(mainPath, ".envrc"), []byte("export F_TEST=1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitTestCommand(t, mainPath, "config", "user.name", "f test")
	gitTestCommand(t, mainPath, "config", "user.email", "f@example.invalid")
	gitTestCommand(t, mainPath, "config", "commit.gpgsign", "false")
	gitTestCommand(t, mainPath, "add", ".envrc")
	gitTestCommand(t, mainPath, "commit", "-m", "envrc")
	gitTestCommand(t, mainPath, "branch", "envbranch")
	direnvLog := filepath.Join(t.TempDir(), "direnv.log")
	direnv := filepath.Join(filepath.Dir(direnvLog), "direnv")
	if err := os.WriteFile(direnv, []byte(fmt.Sprintf("#!/bin/sh\nprintf '%%s\\n' \"$*\" >> %q\nexit 0\n", direnvLog)), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", filepath.Dir(direnv)+string(filepath.ListSeparator)+os.Getenv("PATH"))
	if code, _, stderr := invokeRun(t, root, state, "-e", "acme/demo/envbranch"); code != 0 {
		t.Fatalf("tracked envrc creation code=%d stderr=%s", code, stderr)
	}
	data, err := os.ReadFile(direnvLog)
	if err != nil || !strings.Contains(string(data), "allow") || !strings.Contains(string(data), ".envrc") {
		t.Fatalf("direnv log=%q err=%v", data, err)
	}
}

func TestCleanupGuardsAndDeadPrune(t *testing.T) {
	root, _ := setupLocalRemote(t)
	state := filepath.Join(filepath.Dir(root), "state")
	for _, target := range []string{"main", "clean", "dirty", "locked"} {
		if code, _, stderr := invokeRun(t, root, state, "-e", "acme/demo/"+target); code != 0 {
			t.Fatalf("create %s code=%d stderr=%s", target, code, stderr)
		}
	}
	base := filepath.Join(root, "test.invalid", "acme", "demo")
	old := time.Now().Add(-60 * 24 * time.Hour)
	for _, target := range []string{"main", "clean", "dirty", "locked"} {
		path := filepath.Join(base, target, "tracked.txt")
		if err := os.Chtimes(path, old, old); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(base, "dirty", "untracked"), []byte("dirty"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitTestCommand(t, filepath.Join(base, "main"), "worktree", "lock", filepath.Join(base, "locked"))
	if err := os.RemoveAll(state); err != nil {
		t.Fatal(err)
	}
	if code, _, stderr := invokeRun(t, root, state, "sync"); code != 0 {
		t.Fatalf("sync code=%d stderr=%s", code, stderr)
	}
	tools := t.TempDir()
	tmux := filepath.Join(tools, "tmux")
	if err := os.WriteFile(tmux, []byte("#!/bin/sh\ncase \"$1\" in has-session) exit 1;; list-panes) echo 'no server' >&2; exit 1;; esac\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", tools+string(filepath.ListSeparator)+os.Getenv("PATH"))
	var stdout, stderr bytes.Buffer
	code := run(context.Background(), []string{"-r", root, "-g", "test.invalid", "clean", "30"}, strings.NewReader("y\n"), &stdout, &stderr, testEnv(root, state), time.Now)
	if code != 0 || stderr.Len() == 0 {
		t.Fatalf("clean code=%d stderr=%s", code, stderr.String())
	}
	if _, err := os.Stat(filepath.Join(base, "clean")); !os.IsNotExist(err) {
		t.Fatalf("clean worktree remains: %v", err)
	}
	if _, err := os.Stat(filepath.Join(base, "dirty")); err != nil {
		t.Fatal("dirty worktree was removed")
	}
	if _, err := os.Stat(filepath.Join(base, "locked")); err != nil {
		t.Fatal("locked worktree was removed")
	}
	if code, _, stderr := invokeRun(t, root, state, "-e", "acme/demo/dead"); code != 0 {
		t.Fatalf("dead setup code=%d stderr=%s", code, stderr)
	}
	dead := filepath.Join(base, "dead")
	if err := os.RemoveAll(dead); err != nil {
		t.Fatal(err)
	}
	stdout.Reset()
	stderr.Reset()
	code = run(context.Background(), []string{"-r", root, "-g", "test.invalid", "clean", "0"}, strings.NewReader("y\n"), &stdout, &stderr, testEnv(root, state), time.Now)
	if code != 0 {
		t.Fatalf("dead clean code=%d stderr=%s", code, stderr.String())
	}
	if strings.Contains(gitTestCommand(t, filepath.Join(base, "main"), "worktree", "list", "--porcelain"), "dead") {
		t.Fatal("dead metadata remains after prune")
	}
}
