"""Read-only host probe for teeny.

The same executable runs in two modes:

* ``teeny-probe <command>`` is the client used by the agent.
* ``teeny-probe --broker`` is the per-connection broker started by systemd as
  the ``probe`` user. It accepts one JSON request on stdin and writes one JSON
  response to stdout.

The broker only exposes fixed, read-only commands. Unit names, time windows,
priorities, and glob patterns are validated before they reach journalctl or
systemctl.
"""

import argparse
import json
import os
import re
import socket
import subprocess
import sys
import time

SOCKET_PATH = os.environ.get(
    "TEENY_PROBE_SOCKET", "/run/teeny-probe/probe.sock"
)
UNIT_RE = re.compile(r"^[A-Za-z0-9@:_.-]{1,128}$")
SINCE_RE = re.compile(r"^(-[0-9]{1,4}[smhd]|today|yesterday)$")
PRIORITY_RE = re.compile(
    r"^(emerg|alert|crit|err|warning|notice|info|debug|[0-7])$"
)
PATTERN_RE = re.compile(r"^[A-Za-z0-9@:_.*?\-]{1,128}$")
MAX_OUTPUT = 32768


def run(argv, timeout=15):
    try:
        completed = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "command timed out"}
    except FileNotFoundError as exc:
        return {"ok": False, "error": f"missing command: {exc}"}
    except OSError as exc:
        return {"ok": False, "error": str(exc)}

    output = (completed.stdout or "") + (completed.stderr or "")
    if len(output) > MAX_OUTPUT:
        output = output[:MAX_OUTPUT] + "\n... output truncated ..."
    return {
        "ok": completed.returncode == 0,
        "exit_code": completed.returncode,
        "output": output,
    }


def journal(args):
    unit = args.get("unit", "")
    since = args.get("since", "-1h")
    priority = args.get("priority", "")
    grep = args.get("grep", "")
    limit = args.get("limit", 100)

    if unit and not UNIT_RE.match(unit):
        return {"ok": False, "error": "invalid unit name"}
    if not SINCE_RE.match(since):
        return {
            "ok": False,
            "error": "invalid since; use -15m, -1h, -1d, today, or yesterday",
        }
    if priority and not PRIORITY_RE.match(priority):
        return {"ok": False, "error": "invalid priority"}
    if grep and (len(grep) > 200 or "\n" in grep):
        return {"ok": False, "error": "invalid grep"}
    if not isinstance(limit, int) or not 1 <= limit <= 500:
        return {"ok": False, "error": "limit must be between 1 and 500"}

    argv = [
        "journalctl",
        "--no-pager",
        "--output=json",
        f"--since={since}",
        f"--lines={limit}",
    ]
    if unit:
        argv.append(f"--unit={unit}")
    if priority:
        argv.append(f"--priority={priority}")
    if grep:
        argv.append(f"--grep={grep}")

    try:
        completed = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "journalctl timed out"}
    except OSError as exc:
        return {"ok": False, "error": str(exc)}

    entries = []
    for line in completed.stdout.splitlines():
        try:
            raw = json.loads(line)
        except json.JSONDecodeError:
            continue
        message = raw.get("MESSAGE", "")
        if isinstance(message, list):
            try:
                message = bytes(message).decode("utf-8", "replace")
            except (TypeError, ValueError):
                message = str(message)
        timestamp = raw.get("__REALTIME_TIMESTAMP")
        if isinstance(timestamp, str) and timestamp.isdigit():
            timestamp = time.strftime(
                "%Y-%m-%dT%H:%M:%SZ", time.gmtime(int(timestamp) / 1_000_000)
            )
        entries.append(
            {
                "time": timestamp,
                "unit": raw.get("_SYSTEMD_UNIT")
                or raw.get("SYSLOG_IDENTIFIER"),
                "priority": raw.get("PRIORITY"),
                "host": raw.get("_HOSTNAME"),
                "message": message,
            }
        )

    return {
        "ok": completed.returncode == 0,
        "exit_code": completed.returncode,
        "count": len(entries),
        "entries": entries,
        "stderr": completed.stderr[:2000],
    }


def handle(request):
    command = request.get("command")
    args = request.get("args") or {}

    if command == "ping":
        return {"ok": True, "user": os.environ.get("USER", "unknown")}

    if command == "journal":
        return journal(args)

    if command == "unit-status":
        unit = args.get("unit", "")
        if not UNIT_RE.match(unit):
            return {"ok": False, "error": "invalid unit name"}
        return run(
            ["systemctl", "status", "--no-pager", "--full", "--lines=0", unit]
        )

    if command == "failed-units":
        return run(
            ["systemctl", "--failed", "--no-pager", "--plain", "--no-legend"]
        )

    if command == "disk":
        return run(["df", "-h"])

    if command == "memory":
        return run(["free", "-h"])

    if command == "uptime":
        return run(["uptime"])

    if command == "list-units":
        pattern = args.get("pattern", "")
        if pattern and not PATTERN_RE.match(pattern):
            return {"ok": False, "error": "invalid unit pattern"}
        argv = [
            "systemctl",
            "list-units",
            "--type=service",
            "--all",
            "--no-pager",
            "--plain",
            "--no-legend",
        ]
        if pattern:
            argv.append(pattern)
        return run(argv)

    return {"ok": False, "error": "unknown command"}


def broker():
    line = sys.stdin.readline()
    if not line:
        return 1
    try:
        request = json.loads(line)
    except json.JSONDecodeError:
        print(json.dumps({"ok": False, "error": "invalid JSON"}))
        return 1

    print(
        json.dumps(
            {
                "command": request.get("command"),
                "args": request.get("args") or {},
            }
        ),
        file=sys.stderr,
    )
    print(json.dumps(handle(request)))
    return 0


def client():
    parser = argparse.ArgumentParser(
        prog="teeny-probe",
        description="Read-only journald and systemd probe for teeny",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("ping", help="check that the broker is reachable")

    journal_parser = subparsers.add_parser("journal", help="query the journal")
    journal_parser.add_argument("--unit", default="", help="systemd unit name")
    journal_parser.add_argument(
        "--since",
        default="-1h",
        help="-15m, -1h, -1d, today, yesterday",
    )
    journal_parser.add_argument(
        "--priority",
        default="",
        help="err, warning, info, or 0-7",
    )
    journal_parser.add_argument(
        "--grep",
        default="",
        help="journalctl regular expression",
    )
    journal_parser.add_argument("--limit", type=int, default=100)

    status_parser = subparsers.add_parser(
        "unit-status", help="show one unit's status"
    )
    status_parser.add_argument("unit")

    subparsers.add_parser("failed-units", help="list failed units")
    subparsers.add_parser("disk", help="show filesystem usage")
    subparsers.add_parser("memory", help="show memory usage")
    subparsers.add_parser("uptime", help="show uptime and load")

    list_parser = subparsers.add_parser(
        "list-units", help="list service units"
    )
    list_parser.add_argument("pattern", nargs="?", default="")

    args = parser.parse_args()
    request = {"command": args.command, "args": {}}

    if args.command == "journal":
        request["args"] = {
            "unit": args.unit,
            "since": args.since,
            "priority": args.priority,
            "grep": args.grep,
            "limit": args.limit,
        }
    elif args.command == "unit-status":
        request["args"] = {"unit": args.unit}
    elif args.command == "list-units":
        request["args"] = {"pattern": args.pattern}

    try:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.settimeout(30)
        connection.connect(SOCKET_PATH)
        connection.sendall((json.dumps(request) + "\n").encode())
        connection.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            chunk = connection.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
        connection.close()
        response = json.loads(b"".join(chunks).decode())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"teeny-probe: {exc}", file=sys.stderr)
        return 1

    if response.get("error"):
        print(json.dumps(response, indent=2), file=sys.stderr)
        return 1

    if "entries" in response:
        for entry in response["entries"]:
            print(
                f"{entry.get('time', '?')} "
                f"{entry.get('unit') or '-'} "
                f"[{entry.get('priority', '?')}] "
                f"{entry.get('message', '')}"
            )
    elif "user" in response:
        print(f"probe user: {response['user']}")
    else:
        print((response.get("output") or "").rstrip())
    return 0


if __name__ == "__main__":
    if "--broker" in sys.argv[1:]:
        sys.exit(broker())
    sys.exit(client())
