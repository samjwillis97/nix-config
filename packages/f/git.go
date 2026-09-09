package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
	"strings"
)

type gitFailure struct {
	op     string
	stderr string
	err    error
}

func (e *gitFailure) Error() string {
	if e.stderr != "" {
		return fmt.Sprintf("git %s: %s", e.op, strings.TrimSpace(e.stderr))
	}
	return fmt.Sprintf("git %s: %v", e.op, e.err)
}
func (e *gitFailure) Unwrap() error { return e.err }

func gitCommand(ctx context.Context, dir string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, "git", args...)
	if dir != "" {
		cmd.Dir = dir
	}
	return cmd
}

func gitRun(ctx context.Context, dir string, args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	cmd := gitCommand(ctx, dir, args...)
	cmd.Stdin = stdin
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	if err := cmd.Run(); err != nil {
		return &gitFailure{op: strings.Join(args, " "), err: err}
	}
	return nil
}

func gitCapture(ctx context.Context, dir string, args ...string) ([]byte, error) {
	cmd := gitCommand(ctx, dir, args...)
	var out, errOut bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errOut
	if err := cmd.Run(); err != nil {
		return nil, &gitFailure{op: strings.Join(args, " "), stderr: errOut.String(), err: err}
	}
	return out.Bytes(), nil
}

func gitCaptureText(ctx context.Context, dir string, args ...string) (string, error) {
	out, err := gitCapture(ctx, dir, args...)
	return string(out), err
}

func gitCheckRef(ctx context.Context, dir, ref string) (bool, error) {
	cmd := gitCommand(ctx, dir, "show-ref", "--verify", "--quiet", ref)
	var errOut bytes.Buffer
	cmd.Stderr = &errOut
	if err := cmd.Run(); err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) && ee.ExitCode() == 1 {
			return false, nil
		}
		return false, &gitFailure{op: "show-ref --verify --quiet " + ref, stderr: errOut.String(), err: err}
	}
	return true, nil
}

func gitCheckBranch(ctx context.Context, branch string) (string, error) {
	out, err := gitCapture(ctx, "", "check-ref-format", "--branch", branch)
	if err != nil {
		return "", err
	}
	normalized := strings.TrimSpace(string(out))
	if normalized != branch {
		return "", fmt.Errorf("branch %q is not normalized by git (got %q)", branch, normalized)
	}
	return normalized, nil
}

func gitCommonDir(ctx context.Context, anchor string) (string, error) {
	out, err := gitCaptureText(ctx, anchor, "rev-parse", "--git-common-dir")
	if err != nil {
		return "", err
	}
	common := strings.TrimSpace(out)
	if common == "" {
		return "", fmt.Errorf("git returned an empty common directory for %s", anchor)
	}
	if !filepath.IsAbs(common) {
		common = filepath.Join(anchor, common)
	}
	return canonicalPath(common), nil
}

type gitWorktreeRecord struct {
	Path        string
	HEAD        string
	Branch      string
	Detached    bool
	Primary     bool
	Locked      bool
	Prunable    bool
	LockReason  string
	PruneReason string
}

func parseWorktreePorcelain(data []byte) ([]gitWorktreeRecord, error) {
	// Git's -z form uses NUL terminated records. Older Git releases retain
	// newline separators between fields, so accept both forms without ever
	// splitting a path on whitespace.
	parts := strings.Split(string(data), "\x00")
	var lines []string
	for _, part := range parts {
		part = strings.TrimSuffix(part, "\r")
		if part == "" {
			if len(lines) > 0 {
				lines = append(lines, "")
			}
			continue
		}
		lines = append(lines, part)
	}
	var records []gitWorktreeRecord
	var current *gitWorktreeRecord
	flush := func() {
		if current == nil {
			return
		}
		if current.Path != "" {
			if current.Branch == "" {
				current.Detached = true
			}
			records = append(records, *current)
		}
		current = nil
	}
	for _, line := range lines {
		if line == "" {
			flush()
			continue
		}
		if strings.HasPrefix(line, "worktree ") {
			if current != nil {
				flush()
			}
			current = &gitWorktreeRecord{Path: strings.TrimPrefix(line, "worktree ")}
			continue
		}
		if current == nil {
			continue
		}
		switch {
		case strings.HasPrefix(line, "HEAD "):
			current.HEAD = strings.TrimPrefix(line, "HEAD ")
		case strings.HasPrefix(line, "branch "):
			current.Branch = strings.TrimPrefix(line, "branch refs/heads/")
			if strings.HasPrefix(current.Branch, "refs/") {
				current.Branch = strings.TrimPrefix(current.Branch, "refs/heads/")
			}
		case line == "detached":
			current.Detached = true
		case line == "bare":
			current.Path = ""
		case line == "locked" || strings.HasPrefix(line, "locked "):
			current.Locked = true
			current.LockReason = strings.TrimSpace(strings.TrimPrefix(line, "locked"))
		case line == "prunable" || strings.HasPrefix(line, "prunable "):
			current.Prunable = true
			current.PruneReason = strings.TrimSpace(strings.TrimPrefix(line, "prunable"))
		}
	}
	flush()
	for i := range records {
		records[i].Path = canonicalPath(records[i].Path)
		records[i].Primary = i == 0
	}
	return records, nil
}

func gitWorktrees(ctx context.Context, anchor string) ([]gitWorktreeRecord, error) {
	out, err := gitCapture(ctx, anchor, "worktree", "list", "--porcelain", "-z")
	if err != nil {
		return nil, err
	}
	return parseWorktreePorcelain(out)
}

func gitStatusDirty(ctx context.Context, path string) (bool, error) {
	out, err := gitCapture(ctx, path, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=none")
	if err != nil {
		return false, err
	}
	return len(out) != 0, nil
}

func gitRemoteHead(ctx context.Context, dir, remote string) (string, error) {
	out, err := gitCaptureText(ctx, dir, "ls-remote", "--symref", remote, "HEAD")
	if err != nil {
		return "", err
	}
	return parseRemoteHead(out)
}

func parseRemoteHead(output string) (string, error) {
	for _, line := range strings.Split(output, "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 3 && fields[0] == "ref:" && strings.HasPrefix(fields[1], "refs/heads/") && fields[2] == "HEAD" {
			branch := strings.TrimPrefix(fields[1], "refs/heads/")
			if branch != "" {
				return branch, nil
			}
		}
	}
	return "", fmt.Errorf("remote did not advertise a symbolic HEAD")
}

func reportGitError(stderr io.Writer, err error) {
	if err == nil {
		return
	}
	_, _ = fmt.Fprintf(stderr, "Error: %v\n", err)
}
