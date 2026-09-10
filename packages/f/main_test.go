package main

import (
	"bytes"
	"context"
	"strings"
	"testing"
	"time"
)

func fixedEnv() func(string) string {
	return func(key string) string {
		switch key {
		case "HOME":
			return "/tmp/f-test-home"
		case "XDG_STATE_HOME":
			return "/tmp/f-test-state"
		default:
			return ""
		}
	}
}

func TestRunParserForms(t *testing.T) {
	tests := []struct {
		name string
		args []string
		code int
		want string
	}{
		{name: "help avoids dependencies", args: []string{"-h"}, code: 0, want: "usage: f"},
		{name: "ambiguous target", args: []string{"-p", "repo/branch"}, code: 2, want: "ambiguous"},
		{name: "conflicting modes", args: []string{"-p", "-e", "acme/demo/main"}, code: 2, want: "conflicting"},
		{name: "extra target", args: []string{"-L", "acme/demo/main"}, code: 2, want: "listing accepts"},
		{name: "clean needs days", args: []string{"clean"}, code: 2, want: "clean requires"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			code := run(context.Background(), tt.args, strings.NewReader(""), &stdout, &stderr, fixedEnv(), func() time.Time { return time.Unix(10, 0) })
			if code != tt.code {
				t.Fatalf("run code = %d, want %d; stderr=%s", code, tt.code, stderr.String())
			}
			got := stdout.String() + stderr.String()
			if !strings.Contains(got, tt.want) {
				t.Fatalf("output %q does not contain %q", got, tt.want)
			}
		})
	}
}

func TestHelpDoesNotCreateState(t *testing.T) {
	env := fixedEnv()
	var stdout, stderr bytes.Buffer
	code := run(context.Background(), []string{"-h"}, strings.NewReader(""), &stdout, &stderr, env, time.Now)
	if code != 0 || stdout.Len() == 0 || stderr.Len() != 0 {
		t.Fatalf("help code=%d stdout=%q stderr=%q", code, stdout.String(), stderr.String())
	}
}

func TestRunRejectsUnsafeDomainAndDeleteTarget(t *testing.T) {
	for _, args := range [][]string{
		{"-r", "/tmp/f-test-root", "-g", ".", "-L"},
		{"-r", "/tmp/f-test-root", "-g", "..", "-L"},
		{"-d", "acme/demo/main"},
	} {
		var stdout, stderr bytes.Buffer
		if code := run(context.Background(), args, strings.NewReader(""), &stdout, &stderr, fixedEnv(), time.Now); code != 2 {
			t.Fatalf("args=%v code=%d stderr=%s", args, code, stderr.String())
		}
	}
}
