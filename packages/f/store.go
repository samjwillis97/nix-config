package main

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	_ "modernc.org/sqlite"
)

const storeSchemaVersion = 1

type usageKey struct {
	common string
	path   string
}

type advisoryStore struct {
	db   *sql.DB
	path string
}

func storePath(getenv func(string) string) (string, error) {
	state := getenv("XDG_STATE_HOME")
	if state == "" {
		home := getenv("HOME")
		if home == "" {
			return "", fmt.Errorf("HOME is not set")
		}
		state = filepath.Join(home, ".local", "state")
	}
	state, err := filepath.Abs(state)
	if err != nil {
		return "", err
	}
	dir := filepath.Join(state, "f")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", fmt.Errorf("create state directory: %w", err)
	}
	if err := os.Chmod(dir, 0o700); err != nil {
		return "", fmt.Errorf("secure state directory: %w", err)
	}
	return filepath.Join(dir, "worktrees.sqlite3"), nil
}

func openStore(ctx context.Context, getenv func(string) string) (*advisoryStore, error) {
	path, err := storePath(getenv)
	if err != nil {
		return nil, err
	}
	if info, statErr := os.Lstat(path); statErr == nil && info.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("SQLite state path is a symlink")
	}
	u := &url.URL{Scheme: "file", Path: path, RawQuery: "_busy_timeout=5000"}
	db, err := sql.Open("sqlite", u.String())
	if err != nil {
		return nil, fmt.Errorf("open SQLite state: %w", err)
	}
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	s := &advisoryStore{db: db, path: path}
	if err := s.initialize(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	if err := os.Chmod(path, 0o600); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("secure SQLite state: %w", err)
	}
	return s, nil
}

func (s *advisoryStore) close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

func (s *advisoryStore) initialize(ctx context.Context) error {
	if err := s.db.PingContext(ctx); err != nil {
		return fmt.Errorf("open SQLite state %s: %w", s.path, err)
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin SQLite schema transaction: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	var version int
	if err := tx.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return fmt.Errorf("read SQLite schema version: %w", err)
	}
	if version > storeSchemaVersion {
		return fmt.Errorf("unsupported SQLite schema version %d", version)
	}
	objects, err := sqliteSchemaObjects(ctx, tx)
	if err != nil {
		return err
	}
	fresh := version == 0 && len(objects) == 0
	if !fresh {
		if err := validateSQLiteSchema(ctx, tx, objects); err != nil {
			return fmt.Errorf("invalid SQLite schema: %w", err)
		}
	}
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS worktree_usage (
			common_git_dir TEXT NOT NULL,
			worktree_path TEXT NOT NULL,
			last_used_unix_ms INTEGER NULL CHECK(last_used_unix_ms >= 0),
			PRIMARY KEY(common_git_dir, worktree_path)
		)`,
		`CREATE INDEX IF NOT EXISTS worktree_usage_last_used_idx ON worktree_usage(last_used_unix_ms)`,
		`CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value INTEGER NOT NULL)`,
	}
	for _, stmt := range stmts {
		if _, err := tx.ExecContext(ctx, stmt); err != nil {
			return fmt.Errorf("initialize SQLite schema: %w", err)
		}
	}
	if version < storeSchemaVersion {
		if _, err := tx.ExecContext(ctx, "PRAGMA user_version = "+strconv.Itoa(storeSchemaVersion)); err != nil {
			return fmt.Errorf("set SQLite schema: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit SQLite schema: %w", err)
	}
	return nil
}

func sqliteSchemaObjects(ctx context.Context, tx *sql.Tx) (map[string]string, error) {
	rows, err := tx.QueryContext(ctx, "SELECT name, type FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	objects := make(map[string]string)
	for rows.Next() {
		var name, typ string
		if err := rows.Scan(&name, &typ); err != nil {
			return nil, err
		}
		objects[name] = typ
	}
	return objects, rows.Err()
}

type sqliteColumn struct {
	typ     string
	notNull int
	pk      int
}

func validateSQLiteSchema(ctx context.Context, tx *sql.Tx, objects map[string]string) error {
	if objects["worktree_usage"] != "table" || objects["metadata"] != "table" || objects["worktree_usage_last_used_idx"] != "index" {
		return fmt.Errorf("required tables or index are missing")
	}
	if err := validateSQLiteTable(ctx, tx, "worktree_usage", map[string]sqliteColumn{
		"common_git_dir":    {typ: "TEXT", notNull: 1, pk: 1},
		"worktree_path":     {typ: "TEXT", notNull: 1, pk: 2},
		"last_used_unix_ms": {typ: "INTEGER", notNull: 0, pk: 0},
	}); err != nil {
		return err
	}
	return validateSQLiteTable(ctx, tx, "metadata", map[string]sqliteColumn{
		"key":   {typ: "TEXT", notNull: 0, pk: 1},
		"value": {typ: "INTEGER", notNull: 1, pk: 0},
	})
}

func validateSQLiteTable(ctx context.Context, tx *sql.Tx, table string, want map[string]sqliteColumn) error {
	rows, err := tx.QueryContext(ctx, "PRAGMA table_info("+table+")")
	if err != nil {
		return err
	}
	defer rows.Close()
	got := make(map[string]sqliteColumn)
	for rows.Next() {
		var cid int
		var name, typ string
		var notNull, pk int
		var dflt sql.NullString
		if err := rows.Scan(&cid, &name, &typ, &notNull, &dflt, &pk); err != nil {
			return err
		}
		got[name] = sqliteColumn{typ: strings.ToUpper(strings.TrimSpace(typ)), notNull: notNull, pk: pk}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if len(got) != len(want) {
		return fmt.Errorf("table %s has unexpected columns", table)
	}
	for name, expected := range want {
		actual, ok := got[name]
		if !ok || actual != expected {
			return fmt.Errorf("table %s column %s has unexpected definition", table, name)
		}
	}
	return nil
}

func (s *advisoryStore) usage(ctx context.Context) (map[usageKey]sql.NullInt64, error) {
	rows, err := s.db.QueryContext(ctx, "SELECT common_git_dir, worktree_path, last_used_unix_ms FROM worktree_usage")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make(map[usageKey]sql.NullInt64)
	for rows.Next() {
		var common, path string
		var value sql.NullInt64
		if err := rows.Scan(&common, &path, &value); err != nil {
			return nil, err
		}
		out[usageKey{common: canonicalPath(common), path: canonicalPath(path)}] = value
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}

func (s *advisoryStore) marker(ctx context.Context) (bool, error) {
	var value int64
	err := s.db.QueryRowContext(ctx, "SELECT value FROM metadata WHERE key = 'filesystem_import_version'").Scan(&value)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return value == 1, nil
}

func (s *advisoryStore) reconcileFamily(ctx context.Context, family *repoFamily) error {
	if family == nil {
		return fmt.Errorf("cannot reconcile an empty worktree family")
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	seen := make(map[string]struct{})
	for _, record := range family.records {
		if record.Path == "" {
			continue
		}
		path := canonicalPath(record.Path)
		seen[path] = struct{}{}
		if _, err := tx.ExecContext(ctx, `INSERT INTO worktree_usage(common_git_dir, worktree_path, last_used_unix_ms)
			VALUES(?, ?, NULL) ON CONFLICT(common_git_dir, worktree_path) DO NOTHING`, family.common, path); err != nil {
			return err
		}
	}
	rows, err := tx.QueryContext(ctx, "SELECT worktree_path FROM worktree_usage WHERE common_git_dir = ?", family.common)
	if err != nil {
		return err
	}
	var stale []string
	for rows.Next() {
		var path string
		if err := rows.Scan(&path); err != nil {
			_ = rows.Close()
			return err
		}
		path = canonicalPath(path)
		if _, ok := seen[path]; !ok {
			stale = append(stale, path)
		}
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return err
	}
	_ = rows.Close()
	for _, path := range stale {
		if _, err := tx.ExecContext(ctx, "DELETE FROM worktree_usage WHERE common_git_dir = ? AND worktree_path = ?", family.common, path); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *advisoryStore) upsertUsage(ctx context.Context, key usageKey, value int64) error {
	if value < 0 {
		value = 0
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO worktree_usage(common_git_dir, worktree_path, last_used_unix_ms)
		VALUES(?, ?, ?)
		ON CONFLICT(common_git_dir, worktree_path) DO UPDATE SET last_used_unix_ms =
		CASE WHEN worktree_usage.last_used_unix_ms IS NULL OR worktree_usage.last_used_unix_ms < excluded.last_used_unix_ms
		THEN excluded.last_used_unix_ms ELSE worktree_usage.last_used_unix_ms END`, key.common, key.path, value)
	return err
}

func (s *advisoryStore) deleteUsage(ctx context.Context, key usageKey) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM worktree_usage WHERE common_git_dir = ? AND worktree_path = ?", key.common, key.path)
	return err
}

type importScan struct {
	key    usageKey
	value  *int64
	failed bool
}

type importSummary struct {
	updated   int
	unchanged int
	unknown   int
	failed    int
}

func (s *advisoryStore) applyImport(ctx context.Context, scans []importScan, complete bool) (importSummary, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return importSummary{}, err
	}
	defer func() { _ = tx.Rollback() }()
	var summary importSummary
	for _, scan := range scans {
		if scan.failed {
			summary.failed++
			continue
		}
		var old sql.NullInt64
		err := tx.QueryRowContext(ctx, "SELECT last_used_unix_ms FROM worktree_usage WHERE common_git_dir = ? AND worktree_path = ?", scan.key.common, scan.key.path).Scan(&old)
		if err == sql.ErrNoRows {
			if _, err := tx.ExecContext(ctx, "INSERT INTO worktree_usage(common_git_dir, worktree_path, last_used_unix_ms) VALUES(?, ?, NULL)", scan.key.common, scan.key.path); err != nil {
				return summary, err
			}
		} else if err != nil {
			return summary, err
		}
		if scan.value == nil {
			summary.unknown++
			continue
		}
		value := *scan.value
		if value < 0 {
			value = 0
		}
		if !old.Valid || old.Int64 < value {
			if _, err := tx.ExecContext(ctx, "UPDATE worktree_usage SET last_used_unix_ms = ? WHERE common_git_dir = ? AND worktree_path = ?", value, scan.key.common, scan.key.path); err != nil {
				return summary, err
			}
			summary.updated++
		} else {
			summary.unchanged++
		}
	}
	if complete {
		if _, err := tx.ExecContext(ctx, `INSERT INTO metadata(key, value) VALUES('filesystem_import_version', 1)
			ON CONFLICT(key) DO UPDATE SET value = excluded.value`); err != nil {
			return summary, err
		}
	}
	if err := tx.Commit(); err != nil {
		return summary, err
	}
	return summary, nil
}

func usageValue(rows map[usageKey]sql.NullInt64, common, path string) sql.NullInt64 {
	if rows == nil {
		return sql.NullInt64{}
	}
	return rows[usageKey{common: canonicalPath(common), path: canonicalPath(path)}]
}

func canonicalPath(path string) string {
	if path == "" {
		return ""
	}
	abs, err := filepath.Abs(path)
	if err == nil {
		path = abs
	}
	path = filepath.Clean(path)
	if resolved, err := filepath.EvalSymlinks(path); err == nil {
		if abs, err := filepath.Abs(resolved); err == nil {
			return filepath.Clean(abs)
		}
		return filepath.Clean(resolved)
	}
	return path
}

func pathInside(path, root string) bool {
	path = canonicalPath(path)
	root = canonicalPath(root)
	rel, err := filepath.Rel(root, path)
	if err != nil || rel == "." {
		return err == nil && rel == "."
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) && !filepath.IsAbs(rel)
}

func pathKey(common, path string) usageKey {
	return usageKey{common: canonicalPath(common), path: canonicalPath(path)}
}
