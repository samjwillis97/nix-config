import argparse
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))

import dispatcher  # noqa: E402


def make_args(directory):
    return argparse.Namespace(
        victorialogs_url="http://127.0.0.1:9428",
        query="",
        window="5m",
        host="teeny",
        threshold=2,
        limit=25,
        alert_name="journal-errors",
        label=["triage"],
        exclude_unit=["triage-dispatcher.service"],
        query_timeout=5,
        state=os.path.join(directory, "state.db"),
        state_bin="triage-state",
        cooldown=3600,
        continue_cooldown=3600,
        max_per_hour=3,
        max_per_day=10,
        max_actions_per_run=1,
        amp="amp",
        api_key_file=os.path.join(directory, "amp-key"),
        runner_id="teeny",
        runner_dir="/repo",
        mode="low",
        amp_timeout=30,
        amp_home=directory,
        amp_cwd=directory,
        prompt_file=os.path.join(directory, "prompt.md"),
        verbose=False,
    )


def write_fake_amp(path):
    path.write_text(
        f"""#!{sys.executable}
import json
import os
import sys

record = {{
    "argv": sys.argv[1:],
    "stdin": sys.stdin.read(),
    "api_key": os.environ.get("AMP_API_KEY"),
}}
with open(os.environ["FAKE_AMP_LOG"], "a") as handle:
    handle.write(json.dumps(record) + "\\n")
print("https://ampcode.com/threads/T-01234567-89ab-cdef-0123-456789abcdef",
      file=sys.stderr)
"""
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class DispatcherTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.args = make_args(self.directory.name)
        self.log = Path(self.directory.name) / "amp.jsonl"
        os.environ["FAKE_AMP_LOG"] = str(self.log)

    def tearDown(self):
        os.environ.pop("FAKE_AMP_LOG", None)
        self.directory.cleanup()

    def test_default_query_uses_host_and_threshold(self):
        query = dispatcher.build_query(self.args)
        self.assertIn('_HOSTNAME:"teeny"', query)
        self.assertIn("PRIORITY:<=3", query)
        self.assertIn("errors:>=2", query)

    def test_build_alerts_skips_noise_and_empty_units(self):
        rows = [
            {
                "_HOSTNAME": "teeny",
                "_SYSTEMD_UNIT": "jellyfin.service",
                "errors": "3",
            },
            {
                "_HOSTNAME": "teeny",
                "_SYSTEMD_UNIT": "triage-dispatcher.service",
                "errors": "99",
            },
            {
                "_HOSTNAME": "teeny",
                "_SYSTEMD_UNIT": "",
                "errors": "10",
            },
            {
                "_HOSTNAME": "teeny",
                "_SYSTEMD_UNIT": "quiet.service",
                "errors": "1",
            },
        ]
        alerts = dispatcher.build_alerts(rows, self.args, "query")
        self.assertEqual(len(alerts), 1)
        alert = alerts[0]
        self.assertEqual(alert["labels"]["_SYSTEMD_UNIT"], "jellyfin.service")
        self.assertEqual(alert["labels"]["host"], "teeny")
        self.assertEqual(alert["annotations"]["count"], 3)

    def test_render_prompt_replaces_every_placeholder(self):
        prompt = dispatcher.render_prompt(
            "host={{host}} unit={{unit}} action={{action}}\n{{alert_json}}",
            {
                "labels": {
                    "host": "teeny",
                    "_SYSTEMD_UNIT": "jellyfin.service",
                }
            },
            "investigate",
        )
        self.assertNotIn("{{", prompt)
        self.assertIn("host=teeny", prompt)
        self.assertIn("unit=jellyfin.service", prompt)
        self.assertIn("jellyfin.service", prompt)
        self.assertIn("investigate", prompt)

    def test_render_prompt_rejects_unknown_placeholder(self):
        with self.assertRaises(ValueError):
            dispatcher.render_prompt("{{unknown}}", {"labels": {}}, "action")

    def test_last_thread_url_handles_ansi_output(self):
        output = (
            "\x1b[32mthread\x1b[0m "
            "https://ampcode.com/threads/T-01234567-89ab-cdef-0123-456789abcdef\n"
        )
        self.assertEqual(
            dispatcher.last_thread_url(output),
            "https://ampcode.com/threads/T-01234567-89ab-cdef-0123-456789abcdef",
        )

    def test_thread_labels_are_normalized_and_scoped(self):
        labels = dispatcher.thread_labels(
            self.args,
            {
                "labels": {
                    "host": "Teeny Host",
                    "_SYSTEMD_UNIT": "jellyfin.service",
                }
            },
        )
        self.assertEqual(
            labels,
            [
                "triage",
                "triage-teeny-host",
                "unit-jellyfin-service",
            ],
        )
        self.assertEqual(
            dispatcher.sanitize_label("My Unit @ 1"), "my-unit-1"
        )
        self.assertEqual(len(dispatcher.sanitize_label("x" * 40)), 32)

    def test_spawn_sends_prompt_on_stdin_and_targets_runner(self):
        fake = Path(self.directory.name) / "amp"
        write_fake_amp(fake)
        self.args.amp = str(fake)
        Path(self.args.api_key_file).write_text("test-key\n")

        labels = ["triage", "triage-teeny"]
        url = dispatcher.spawn_thread(
            self.args, "rendered prompt", "test-key", labels
        )

        self.assertEqual(
            url,
            "https://ampcode.com/threads/T-01234567-89ab-cdef-0123-456789abcdef",
        )
        record = json.loads(self.log.read_text().strip())
        self.assertEqual(record["stdin"], "rendered prompt")
        self.assertEqual(record["api_key"], "test-key")
        self.assertIn("--executor", record["argv"])
        self.assertIn("runner:teeny", record["argv"])
        self.assertIn("--runner-dir", record["argv"])
        self.assertIn("/repo", record["argv"])
        self.assertEqual(record["argv"].count("--label"), 2)
        self.assertIn("triage", record["argv"])
        self.assertIn("triage-teeny", record["argv"])

    def test_resolve_stale_marks_missing_incidents_resolved(self):
        fake = Path(self.directory.name) / "triage-state"
        state_log = Path(self.directory.name) / "state.jsonl"
        fake.write_text(
            f"""#!{sys.executable}
import json
import sys

args = sys.argv[1:]
record = {{"argv": args}}
if "list" in args:
    print(json.dumps([{{
        "fingerprint": "fp",
        "alertname": "journal-errors",
        "host": "teeny",
        "unit": "jellyfin.service",
        "status": "open",
    }}]))
else:
    alert_path = args[args.index("--alert") + 1]
    record["alert"] = json.load(open(alert_path))
    print(json.dumps({{"decision": "suppress", "fingerprint": "fp"}}))
with open({str(state_log)!r}, "a") as handle:
    handle.write(json.dumps(record) + "\\n")
"""
        )
        fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
        self.args.state_bin = str(fake)

        self.assertEqual(
            dispatcher.resolve_stale(self.args, "journal-errors", set()), 1
        )

        records = [
            json.loads(line)
            for line in state_log.read_text().splitlines()
        ]
        check = next(record for record in records if "check" in record["argv"])
        self.assertEqual(check["alert"]["status"], "resolved")
        self.assertEqual(
            check["alert"]["labels"]["_SYSTEMD_UNIT"], "jellyfin.service"
        )

    def test_continue_uses_existing_thread(self):
        fake = Path(self.directory.name) / "amp"
        write_fake_amp(fake)
        self.args.amp = str(fake)
        Path(self.args.api_key_file).write_text("test-key\n")

        dispatcher.continue_thread(
            self.args,
            "https://ampcode.com/threads/T-existing",
            "still firing",
            "test-key",
            ["triage", "unit-jellyfin-service"],
        )

        record = json.loads(self.log.read_text().strip())
        self.assertEqual(
            record["argv"][:3],
            [
                "threads",
                "continue",
                "https://ampcode.com/threads/T-existing",
            ],
        )
        self.assertIn("still firing", record["argv"])
        self.assertIn("triage", record["argv"])
        self.assertIn("unit-jellyfin-service", record["argv"])


if __name__ == "__main__":
    unittest.main()
