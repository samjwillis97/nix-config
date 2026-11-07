"""Stable incident fingerprints and spawn budgets for triage threads.

The dispatcher calls ``check`` before starting an Amp thread and ``record``
after the thread URL is known. Similar alerts share a fingerprint and are
suppressed during the cooldown, so a flapping service does not create a new
thread for every evaluation.
"""

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time

DEFAULT_STATE = "/var/lib/triage/state.db"
DEFAULT_COOLDOWN = 6 * 60 * 60
DEFAULT_MAX_PER_HOUR = 3
DEFAULT_MAX_PER_DAY = 10

SCHEMA = """
CREATE TABLE IF NOT EXISTS incidents (
    fingerprint TEXT PRIMARY KEY,
    alertname TEXT NOT NULL,
    host TEXT NOT NULL,
    unit TEXT NOT NULL,
    first_seen INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    last_spawned INTEGER,
    thread_url TEXT,
    status TEXT NOT NULL DEFAULT 'open'
);

CREATE TABLE IF NOT EXISTS spawns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    fingerprint TEXT NOT NULL,
    spawned_at INTEGER NOT NULL,
    thread_url TEXT
);
"""


def open_state(path):
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    connection = sqlite3.connect(path)
    connection.row_factory = sqlite3.Row
    connection.executescript(SCHEMA)
    return connection


def alert_fields(alert):
    labels = alert.get("labels") or {}
    alertname = labels.get("alertname") or "unknown"
    host = labels.get("host") or labels.get("instance") or "unknown"
    unit = labels.get("_SYSTEMD_UNIT") or labels.get("unit") or "-"
    return alertname, host, unit


def fingerprint(alert):
    """Hash only stable labels, never the changing value or summary."""
    alertname, host, unit = alert_fields(alert)
    key = f"{alertname}|{host}|{unit}"
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


def _incident(connection, fingerprint_value):
    row = connection.execute(
        "SELECT * FROM incidents WHERE fingerprint = ?",
        (fingerprint_value,),
    ).fetchone()
    return dict(row) if row else None


def _count_spawns(connection, since):
    row = connection.execute(
        "SELECT COUNT(*) AS count FROM spawns WHERE spawned_at > ?",
        (since,),
    ).fetchone()
    return int(row["count"])


def check(
    connection,
    alert,
    now,
    cooldown=DEFAULT_COOLDOWN,
    max_per_hour=DEFAULT_MAX_PER_HOUR,
    max_per_day=DEFAULT_MAX_PER_DAY,
):
    fingerprint_value = fingerprint(alert)
    alertname, host, unit = alert_fields(alert)
    status = alert.get("status", "firing")

    with connection:
        row = _incident(connection, fingerprint_value)
        previous_status = row["status"] if row else None
        if row is None:
            connection.execute(
                """
                INSERT INTO incidents
                    (fingerprint, alertname, host, unit, first_seen,
                     last_seen, status)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (fingerprint_value, alertname, host, unit, now, now, "open"),
            )
        else:
            new_status = "resolved" if status == "resolved" else "open"
            connection.execute(
                """
                UPDATE incidents
                   SET last_seen = ?, status = ?
                 WHERE fingerprint = ?
                """,
                (now, new_status, fingerprint_value),
            )

    incident = _incident(connection, fingerprint_value)

    if status == "resolved":
        return {
            "decision": "suppress",
            "reason": "resolved",
            "fingerprint": fingerprint_value,
            "incident": incident,
        }

    if incident.get("last_spawned") is not None:
        age = now - int(incident["last_spawned"])
        if age < cooldown:
            return {
                "decision": "suppress",
                "reason": "cooldown",
                "fingerprint": fingerprint_value,
                "incident": incident,
            }

    # The incident already has a thread and has not resolved: continue that
    # thread instead of creating another one.
    if incident.get("thread_url") and previous_status != "resolved":
        return {
            "decision": "continue",
            "reason": "existing_incident",
            "fingerprint": fingerprint_value,
            "thread_url": incident["thread_url"],
            "incident": incident,
        }

    if _count_spawns(connection, now - 3600) >= max_per_hour:
        return {
            "decision": "suppress",
            "reason": "hourly_limit",
            "fingerprint": fingerprint_value,
            "incident": incident,
        }

    if _count_spawns(connection, now - 86400) >= max_per_day:
        return {
            "decision": "suppress",
            "reason": "daily_limit",
            "fingerprint": fingerprint_value,
            "incident": incident,
        }

    return {
        "decision": "spawn",
        "reason": "new_incident",
        "fingerprint": fingerprint_value,
        "incident": incident,
    }


def record(connection, alert, thread_url, now):
    fingerprint_value = fingerprint(alert)
    with connection:
        connection.execute(
            """
            UPDATE incidents
               SET last_spawned = ?, thread_url = ?
             WHERE fingerprint = ?
            """,
            (now, thread_url, fingerprint_value),
        )
        connection.execute(
            """
            INSERT INTO spawns (fingerprint, spawned_at, thread_url)
            VALUES (?, ?, ?)
            """,
            (fingerprint_value, now, thread_url),
        )
    return _incident(connection, fingerprint_value)


def prune(connection, older_than):
    with connection:
        connection.execute(
            "DELETE FROM incidents WHERE last_seen < ?",
            (older_than,),
        )
        connection.execute(
            "DELETE FROM spawns WHERE spawned_at < ?",
            (older_than,),
        )


def read_alert(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="triage-state",
        description="Deduplicate triage threads by stable alert labels",
    )
    parser.add_argument("--state", default=DEFAULT_STATE)
    parser.add_argument("--cooldown", type=int, default=DEFAULT_COOLDOWN)
    parser.add_argument(
        "--max-per-hour", type=int, default=DEFAULT_MAX_PER_HOUR
    )
    parser.add_argument("--max-per-day", type=int, default=DEFAULT_MAX_PER_DAY)
    subparsers = parser.add_subparsers(dest="command", required=True)

    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--alert", required=True)

    record_parser = subparsers.add_parser("record")
    record_parser.add_argument("--alert", required=True)
    record_parser.add_argument("--thread-url", required=True)

    subparsers.add_parser("list")

    prune_parser = subparsers.add_parser("prune")
    prune_parser.add_argument("--days", type=int, default=30)

    args = parser.parse_args(argv)
    connection = open_state(args.state)
    now = int(time.time())

    if args.command == "check":
        result = check(
            connection,
            read_alert(args.alert),
            now,
            cooldown=args.cooldown,
            max_per_hour=args.max_per_hour,
            max_per_day=args.max_per_day,
        )
    elif args.command == "record":
        result = record(
            connection,
            read_alert(args.alert),
            args.thread_url,
            now,
        )
    elif args.command == "list":
        rows = connection.execute(
            "SELECT * FROM incidents ORDER BY last_seen DESC"
        ).fetchall()
        result = [dict(row) for row in rows]
    elif args.command == "prune":
        prune(connection, now - args.days * 86400)
        result = {"pruned_before": now - args.days * 86400}
    else:
        connection.close()
        return 2

    connection.close()
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
