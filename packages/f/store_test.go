package main

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestScanWorktreeExclusionsAndClockClamping(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, ".git"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(root, "node_modules"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "node_modules", "cache"), []byte("ignored"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, ".git", "index"), []byte("ignored"), 0o644); err != nil {
		t.Fatal(err)
	}
	visible := filepath.Join(root, "visible")
	if err := os.WriteFile(visible, []byte("visible"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(visible, time.Unix(20, 0), time.Unix(20, 0)); err != nil {
		t.Fatal(err)
	}
	outside := filepath.Join(t.TempDir(), "outside")
	if err := os.WriteFile(outside, []byte("outside"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(outside, time.Unix(30, 0), time.Unix(30, 0)); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(root, "link")); err != nil {
		t.Fatal(err)
	}
	value, err := scanWorktree(root, 10_000)
	if err != nil {
		t.Fatal(err)
	}
	if value == nil || *value != 10_000 {
		t.Fatalf("scan value=%v, want clamped future timestamp 10000", value)
	}
	if err := os.Remove(visible); err != nil {
		t.Fatal(err)
	}
	value, err = scanWorktree(root, 10_000)
	if err != nil {
		t.Fatal(err)
	}
	if value != nil {
		t.Fatalf("excluded-only scan value=%v, want unknown", *value)
	}
}

func TestStoreUsageIsMonotonicAndImportMarksCompletion(t *testing.T) {
	state := t.TempDir()
	env := func(key string) string {
		if key == "XDG_STATE_HOME" {
			return state
		}
		if key == "HOME" {
			return state
		}
		return ""
	}
	store, err := openStore(context.Background(), env)
	if err != nil {
		t.Fatal(err)
	}
	defer store.close()
	key := pathKey(filepath.Join(state, "common"), filepath.Join(state, "worktree"))
	if err := store.upsertUsage(context.Background(), key, 500); err != nil {
		t.Fatal(err)
	}
	if err := store.upsertUsage(context.Background(), key, 100); err != nil {
		t.Fatal(err)
	}
	rows, err := store.usage(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	value := rows[key]
	if !value.Valid || value.Int64 != 500 {
		t.Fatalf("monotonic usage=%v", value)
	}
	newKey := pathKey(filepath.Join(state, "common"), filepath.Join(state, "new-worktree"))
	v := int64(600)
	summary, err := store.applyImport(context.Background(), []importScan{{key: key, value: &v}, {key: newKey, value: nil}}, true)
	if err != nil {
		t.Fatal(err)
	}
	if summary.updated != 1 || summary.unchanged != 0 || summary.unknown != 1 || summary.failed != 0 {
		t.Fatalf("summary=%+v", summary)
	}
	marked, err := store.marker(context.Background())
	if err != nil || !marked {
		t.Fatalf("marker=%v err=%v", marked, err)
	}
	rows, err = store.usage(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if got := rows[key]; !got.Valid || got.Int64 != 600 {
		t.Fatalf("imported usage=%v", got)
	}
	if got := rows[newKey]; got.Valid {
		t.Fatalf("unknown row unexpectedly timestamped: %v", got)
	}
}

func TestStoreRejectsMalformedSchemaAndKeepsPartialMarkerSafe(t *testing.T) {
	state := t.TempDir()
	dbPath := filepath.Join(state, "f", "worktrees.sqlite3")
	if err := os.MkdirAll(filepath.Dir(dbPath), 0o700); err != nil {
		t.Fatal(err)
	}
	db, err := sql.Open("sqlite", "file:"+dbPath)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`CREATE TABLE worktree_usage (common_git_dir TEXT, worktree_path TEXT, last_used_unix_ms INTEGER)`); err != nil {
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}
	env := func(key string) string {
		if key == "XDG_STATE_HOME" || key == "HOME" {
			return state
		}
		return ""
	}
	if store, err := openStore(context.Background(), env); err == nil {
		store.close()
		t.Fatal("malformed SQLite schema opened successfully")
	}

	goodState := t.TempDir()
	goodEnv := func(key string) string {
		if key == "XDG_STATE_HOME" || key == "HOME" {
			return goodState
		}
		return ""
	}
	store, err := openStore(context.Background(), goodEnv)
	if err != nil {
		t.Fatal(err)
	}
	defer store.close()
	goodKey := pathKey(filepath.Join(goodState, "common"), filepath.Join(goodState, "good"))
	badKey := pathKey(filepath.Join(goodState, "common"), filepath.Join(goodState, "bad"))
	v := int64(100)
	if _, err := store.applyImport(context.Background(), []importScan{{key: goodKey, value: &v}, {key: badKey, failed: true}}, false); err != nil {
		t.Fatal(err)
	}
	marked, err := store.marker(context.Background())
	if err != nil || marked {
		t.Fatalf("partial import marker=%v err=%v", marked, err)
	}
	rows, err := store.usage(context.Background())
	if err != nil || !rows[goodKey].Valid || rows[badKey].Valid {
		t.Fatalf("partial rows=%v err=%v", rows, err)
	}
	done := make(chan struct{}, 8)
	for i := 0; i < 8; i++ {
		go func(value int64) {
			_ = store.upsertUsage(context.Background(), goodKey, value)
			done <- struct{}{}
		}(int64(200 + i))
	}
	for i := 0; i < 8; i++ {
		<-done
	}
	rows, err = store.usage(context.Background())
	if err != nil || rows[goodKey].Int64 < 207 {
		t.Fatalf("concurrent usage=%v err=%v", rows[goodKey], err)
	}
}
