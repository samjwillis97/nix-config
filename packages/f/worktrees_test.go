package main

import (
	"bytes"
	"context"
	"fmt"
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
	records, err := parseWorktreePorcelain(data)
	if err != nil || len(records) != 2 {
		t.Fatalf("records=%+v err=%v", records, err)
	}
	if !records[0].Primary || records[0].Branch != "main" || records[1].Branch != "" || !records[1].Detached {
		t.Fatalf("records=%+v", records)
	}
}

func TestDiscoverInventoryExcludesGeneratedSubtrees(t *testing.T) {
	root := t.TempDir()
	scope := filepath.Join(root, "github.com", "acme")
	generated := filepath.Join(scope, "unmanaged", ".direnv", "nested", "tree")
	if err := os.MkdirAll(generated, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(generated, ".git"), []byte("not a repository"), 0o644); err != nil {
		t.Fatal(err)
	}

	anchor := filepath.Join(scope, "named", "node_modules")
	gitTestCommand(t, "", "init", "--initial-branch=main", anchor)
	gitTestCommand(t, anchor, "config", "user.name", "f test")
	gitTestCommand(t, anchor, "config", "user.email", "f@example.invalid")
	gitTestCommand(t, anchor, "config", "commit.gpgsign", "false")
	gitTestCommand(t, anchor, "commit", "--allow-empty", "-m", "initial")

	inv, err := discoverInventory(context.Background(), appConfig{root: root, domain: "github.com"})
	if err != nil {
		t.Fatal(err)
	}
	if len(inv.errors) != 0 || len(inv.families) != 1 || len(inv.families[0].records) != 1 {
		t.Fatalf("inventory errors=%v families=%v", inv.errors, inv.families)
	}
	if got := canonicalPath(inv.families[0].records[0].Path); got != canonicalPath(anchor) {
		t.Fatalf("anchor path=%q want %q", got, anchor)
	}
}

func TestDiscoverInventoryFindsDeepOnlyAnchor(t *testing.T) {
	root := t.TempDir()
	anchor := filepath.Join(root, "github.com", "acme", "demo", "feature", "login")
	gitTestCommand(t, "", "init", "--initial-branch=main", anchor)
	gitTestCommand(t, anchor, "config", "user.name", "f test")
	gitTestCommand(t, anchor, "config", "user.email", "f@example.invalid")
	gitTestCommand(t, anchor, "config", "commit.gpgsign", "false")
	gitTestCommand(t, anchor, "commit", "--allow-empty", "-m", "initial")

	inv, err := discoverInventory(context.Background(), appConfig{root: root, domain: "github.com"})
	if err != nil {
		t.Fatal(err)
	}
	if len(inv.errors) != 0 || len(inv.families) != 1 || len(inv.families[0].records) != 1 {
		t.Fatalf("inventory errors=%v families=%v", inv.errors, inv.families)
	}
	if got := canonicalPath(inv.families[0].records[0].Path); got != canonicalPath(anchor) {
		t.Fatalf("anchor path=%q want %q", got, anchor)
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

func TestRunFZFQueryCancellationAndTmuxFailures(t *testing.T) {
	root, _ := setupLocalRemote(t)
	state := filepath.Join(filepath.Dir(root), "state")
	if code, _, stderr := invokeRun(t, root, state, "-e", "acme/demo/main"); code != 0 {
		t.Fatalf("create default code=%d stderr=%s", code, stderr)
	}
	mainPath := filepath.Join(root, "test.invalid", "acme", "demo", "main")
	tools := t.TempDir()
	tmuxLog := filepath.Join(tools, "tmux.log")
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
	writeTool("fzf", fmt.Sprintf("#!/bin/sh\nprintf 'test.invalid/acme/demo/main\\ntest.invalid/acme/demo/main\\t%s\\n'\nexit 0\n", mainPath))
	code, _, stderr := runWithInput("", "-l")
	if code != 0 || !strings.Contains(stderr, "") {
		t.Fatalf("fzf select code=%d stderr=%s", code, stderr)
	}
	if data, err := os.ReadFile(tmuxLog); err != nil || !strings.Contains(string(data), "attach-session") {
		t.Fatalf("tmux attach log=%q err=%v", data, err)
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
	writeTool("fzf", "#!/bin/sh\nprintf 'acme/demo/newbranch\\n'\nexit 1\n")
	if code, _, stderr := runWithInput("", "-l"); code != 0 {
		t.Fatalf("fzf query code=%d stderr=%s", code, stderr)
	}
	writeTool("fzf", "#!/bin/sh\nprintf 'acme/demo/bad..branch\\n'\nexit 1\n")
	if code, _, _ := runWithInput("", "-l"); code != 2 {
		t.Fatalf("malformed fzf query code=%d", code)
	}
	writeTool("fzf", "#!/bin/sh\nexit 2\n")
	if code, _, _ := runWithInput("", "-l"); code != 1 {
		t.Fatalf("fzf error code=%d", code)
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
