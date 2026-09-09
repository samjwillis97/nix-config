package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type cliMode uint8

const (
	modeTarget cliMode = iota
	modeListFZF
	modeList
	modeDelete
	modeSync
	modeGC
	modeClean
)

type cliOptions struct {
	root       string
	domain     string
	mode       cliMode
	printOnly  bool
	ensureOnly bool
	target     string
	days       string
	help       bool
}

const usageText = `usage: f [-r <root>] [-g <domain>] [-p|-e] <owner>/<repo>/<branch...>
       f [-r <root>] [-g <domain>] -l|-L|-d
       f [-r <root>] [-g <domain>] sync
       f [-r <root>] [-g <domain>] gc [days]
       f [-r <root>] [-g <domain>] clean <days>

flags:
  -h                  display this usage
  -r <root>           workspace root (default: $HOME/code)
  -g <domain>         Git hosting domain (default: github.com)
  -l                  list workspaces with fzf and open the selection
  -L                  list workspace paths without fzf
  -d                  delete one selected workspace
  -p                  print an existing workspace path; never create or tmux
  -e                  create a workspace when needed and print its path

subcommands:
  sync                import filesystem timestamps into the advisory index
  gc [days]           list stale worktrees (default: 30 days)
  clean <days>        remove guarded stale worktrees
`

func printUsage(w io.Writer) { _, _ = io.WriteString(w, usageText) }

func parseArgs(args []string) (cliOptions, error) {
	o := cliOptions{domain: "github.com", mode: modeTarget}
	var positional []string
	optionsDone := false
	for i := 0; i < len(args); i++ {
		a := args[i]
		if !optionsDone && a == "--" {
			optionsDone = true
			continue
		}
		if !optionsDone && strings.HasPrefix(a, "-") && a != "-" {
			if a == "-h" || a == "--help" {
				o.help = true
				continue
			}
			if a == "-r" || a == "-g" {
				if i+1 >= len(args) || args[i+1] == "" || strings.HasPrefix(args[i+1], "-") {
					return o, fmt.Errorf("%s requires an argument", a)
				}
				if a == "-r" {
					o.root = args[i+1]
				} else {
					o.domain = args[i+1]
				}
				i++
				continue
			}
			if strings.HasPrefix(a, "--") {
				return o, fmt.Errorf("unknown option %s", a)
			}
			for _, flag := range a[1:] {
				switch flag {
				case 'p':
					if o.printOnly || o.ensureOnly {
						return o, fmt.Errorf("conflicting mode flags")
					}
					o.printOnly = true
				case 'e':
					if o.printOnly || o.ensureOnly {
						return o, fmt.Errorf("conflicting mode flags")
					}
					o.ensureOnly = true
				case 'l':
					if o.mode != modeTarget || o.printOnly || o.ensureOnly {
						return o, fmt.Errorf("conflicting mode flags")
					}
					o.mode = modeListFZF
				case 'L':
					if o.mode != modeTarget || o.printOnly || o.ensureOnly {
						return o, fmt.Errorf("conflicting mode flags")
					}
					o.mode = modeList
				case 'd':
					if o.mode != modeTarget || o.printOnly || o.ensureOnly {
						return o, fmt.Errorf("conflicting mode flags")
					}
					o.mode = modeDelete
				default:
					return o, fmt.Errorf("unknown option -%c", flag)
				}
			}
			continue
		}
		if !optionsDone && strings.HasPrefix(a, "-") {
			return o, fmt.Errorf("invalid option %s", a)
		}
		optionsDone = true
		positional = append(positional, a)
	}
	if o.help {
		return o, nil
	}
	if o.printOnly || o.ensureOnly {
		if o.mode != modeTarget {
			return o, fmt.Errorf("target mode cannot be combined with listing or deletion")
		}
	}
	if o.mode == modeTarget {
		if len(positional) == 0 {
			return o, fmt.Errorf("a target or subcommand is required")
		}
		if len(positional) > 2 {
			return o, fmt.Errorf("too many positional arguments")
		}
		if positional[0] == "sync" {
			if len(positional) != 1 || o.printOnly || o.ensureOnly {
				return o, fmt.Errorf("invalid sync invocation")
			}
			o.mode = modeSync
		} else if positional[0] == "gc" {
			if o.printOnly || o.ensureOnly || len(positional) > 2 {
				return o, fmt.Errorf("invalid gc invocation")
			}
			o.mode = modeGC
			if len(positional) == 2 {
				o.days = positional[1]
			}
		} else if positional[0] == "clean" {
			if o.printOnly || o.ensureOnly || len(positional) != 2 {
				return o, fmt.Errorf("clean requires exactly one day count")
			}
			o.mode = modeClean
			o.days = positional[1]
		} else {
			if len(positional) != 1 {
				return o, fmt.Errorf("a target must be one argument")
			}
			o.target = positional[0]
		}
	} else if o.mode == modeDelete {
		if len(positional) != 0 {
			return o, fmt.Errorf("deletion accepts no positional arguments")
		}
	} else if len(positional) != 0 {
		return o, fmt.Errorf("listing accepts no positional arguments")
	}
	if o.mode == modeListFZF || o.mode == modeList || o.mode == modeDelete {
		if o.printOnly || o.ensureOnly {
			return o, fmt.Errorf("conflicting mode flags")
		}
	}
	return o, nil
}

func run(ctx context.Context, args []string, stdin io.Reader, stdout, stderr io.Writer, getenv func(string) string, now func() time.Time) int {
	if ctx == nil {
		ctx = context.Background()
	}
	if getenv == nil {
		getenv = os.Getenv
	}
	if now == nil {
		now = time.Now
	}
	opts, err := parseArgs(args)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "Error: %v\n", err)
		printUsage(stderr)
		return 2
	}
	if opts.help {
		printUsage(stdout)
		return 0
	}
	if opts.root == "" {
		home := getenv("HOME")
		if home == "" {
			_, _ = fmt.Fprintln(stderr, "Error: HOME is not set and no root was supplied")
			return 1
		}
		opts.root = filepath.Join(home, "code")
	}
	root, err := filepath.Abs(opts.root)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "Error: invalid root: %v\n", err)
		return 1
	}
	opts.root = filepath.Clean(root)
	if opts.domain == "" || opts.domain == "." || opts.domain == ".." || filepath.IsAbs(opts.domain) || strings.ContainsAny(opts.domain, `/\\`) {
		_, _ = fmt.Fprintln(stderr, "Error: invalid Git domain")
		return 2
	}
	cfg := appConfig{root: opts.root, domain: opts.domain, getenv: getenv, now: now}
	switch opts.mode {
	case modeSync:
		if err := runSync(ctx, cfg, stdout, stderr, stdin); err != nil {
			return 1
		}
		return 0
	case modeGC, modeClean:
		days := opts.days
		if days == "" {
			days = "30"
		}
		if opts.mode == modeClean && opts.days == "" {
			_, _ = fmt.Fprintln(stderr, "Error: clean requires a number of days")
			printUsage(stderr)
			return 2
		}
		if _, daysErr := parseDays(days); daysErr != nil {
			_, _ = fmt.Fprintf(stderr, "Error: %v\n", daysErr)
			printUsage(stderr)
			return 2
		}
		if err := runCleanup(ctx, cfg, opts.mode == modeClean, days, stdin, stdout, stderr); err != nil {
			return 1
		}
		return 0
	case modeListFZF:
		if err := runListFZF(ctx, cfg, stdin, stdout, stderr); err != nil {
			if exitErr, ok := err.(exitCodeError); ok {
				return exitErr.code
			}
			return 1
		}
		return 0
	case modeList:
		if err := runList(ctx, cfg, stdout, stderr); err != nil {
			return 1
		}
		return 0
	case modeDelete:
		if err := runDelete(ctx, cfg, opts.target, stdin, stdout, stderr); err != nil {
			if exitErr, ok := err.(exitCodeError); ok {
				return exitErr.code
			}
			return 1
		}
		return 0
	default:
		if opts.target == "" {
			_, _ = fmt.Fprintln(stderr, "Error: target is required")
			printUsage(stderr)
			return 2
		}
		rc, err := runTarget(ctx, cfg, opts.target, opts.printOnly, opts.ensureOnly, stdin, stdout, stderr)
		if err != nil {
			if rc != 0 {
				return rc
			}
			return 1
		}
		return 0
	}
}

func main() {
	os.Exit(run(context.Background(), os.Args[1:], os.Stdin, os.Stdout, os.Stderr, os.Getenv, time.Now))
}

func stdinIsTerminal(r io.Reader) bool {
	f, ok := r.(*os.File)
	if !ok {
		return false
	}
	info, err := f.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}

type exitCodeError struct {
	code int
	err  error
}

func (e exitCodeError) Error() string { return e.err.Error() }
