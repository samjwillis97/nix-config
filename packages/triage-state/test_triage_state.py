import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import triage_state  # noqa: E402


def make_alert(unit="jellyfin.service", status="firing", summary="boom"):
    return {
        "status": status,
        "labels": {
            "alertname": "ErrorSpike",
            "host": "teeny",
            "_SYSTEMD_UNIT": unit,
        },
        "annotations": {"summary": summary},
    }


class TriageStateTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.directory.name, "state.db")
        self.connection = triage_state.open_state(self.path)

    def tearDown(self):
        self.connection.close()
        self.directory.cleanup()

    def test_fingerprint_ignores_summary_and_value(self):
        first = triage_state.fingerprint(make_alert(summary="1 error"))
        second = triage_state.fingerprint(make_alert(summary="999 errors"))
        self.assertEqual(first, second)

    def test_fingerprint_separates_units(self):
        first = triage_state.fingerprint(make_alert("jellyfin.service"))
        second = triage_state.fingerprint(make_alert("actual.service"))
        self.assertNotEqual(first, second)

    def test_cooldown_suppresses_similar_alert(self):
        now = 1_000_000
        first = triage_state.check(self.connection, make_alert(), now)
        self.assertEqual(first["decision"], "spawn")

        triage_state.record(
            self.connection, make_alert(), "https://amp.example/1", now
        )

        second = triage_state.check(self.connection, make_alert(), now + 60)
        self.assertEqual(second["decision"], "suppress")
        self.assertEqual(second["reason"], "cooldown")

        later = triage_state.check(
            self.connection,
            make_alert(summary="changed"),
            now + triage_state.DEFAULT_COOLDOWN + 1,
        )
        self.assertEqual(later["decision"], "continue")

    def test_hourly_limit_is_global(self):
        now = 1_000_000
        for unit in ("jellyfin.service", "actual.service"):
            result = triage_state.check(
                self.connection,
                make_alert(unit),
                now,
                max_per_hour=2,
                max_per_day=100,
            )
            self.assertEqual(result["decision"], "spawn")
            triage_state.record(
                self.connection, make_alert(unit), "url", now
            )

        blocked = triage_state.check(
            self.connection,
            make_alert("supernote.service"),
            now,
            max_per_hour=2,
            max_per_day=100,
        )
        self.assertEqual(blocked["decision"], "suppress")
        self.assertEqual(blocked["reason"], "hourly_limit")

    def test_daily_limit_is_global(self):
        now = 1_000_000
        for unit in ("jellyfin.service", "actual.service"):
            triage_state.check(
                self.connection,
                make_alert(unit),
                now,
                max_per_hour=100,
                max_per_day=2,
            )
            triage_state.record(
                self.connection, make_alert(unit), "url", now
            )

        blocked = triage_state.check(
            self.connection,
            make_alert("supernote.service"),
            now,
            max_per_hour=100,
            max_per_day=2,
        )
        self.assertEqual(blocked["decision"], "suppress")
        self.assertEqual(blocked["reason"], "daily_limit")

    def test_resolved_alert_is_suppressed(self):
        now = 1_000_000
        triage_state.check(self.connection, make_alert(), now)
        triage_state.record(self.connection, make_alert(), "url", now)

        resolved = triage_state.check(
            self.connection,
            make_alert(status="resolved"),
            now + 60,
        )
        self.assertEqual(resolved["decision"], "suppress")
        self.assertEqual(resolved["reason"], "resolved")
        self.assertEqual(resolved["incident"]["status"], "resolved")

    def test_existing_incident_continues_after_cooldown(self):
        now = 1_000_000
        triage_state.check(self.connection, make_alert(), now)
        triage_state.record(self.connection, make_alert(), "url", now)

        result = triage_state.check(
            self.connection,
            make_alert(summary="still failing"),
            now + triage_state.DEFAULT_COOLDOWN + 1,
        )
        self.assertEqual(result["decision"], "continue")
        self.assertEqual(result["reason"], "existing_incident")
        self.assertEqual(result["thread_url"], "url")

    def test_resolved_then_refire_spawns_after_cooldown(self):
        now = 1_000_000
        triage_state.check(self.connection, make_alert(), now)
        triage_state.record(self.connection, make_alert(), "url", now)
        triage_state.check(
            self.connection,
            make_alert(status="resolved"),
            now + 60,
        )

        result = triage_state.check(
            self.connection,
            make_alert(),
            now + triage_state.DEFAULT_COOLDOWN + 1,
        )
        self.assertEqual(result["decision"], "spawn")

    def test_prune_removes_old_rows(self):
        now = 1_000_000
        triage_state.check(self.connection, make_alert(), now)
        triage_state.record(self.connection, make_alert(), "url", now)
        triage_state.prune(self.connection, now + 1)

        rows = self.connection.execute(
            "SELECT COUNT(*) AS count FROM incidents"
        ).fetchone()
        self.assertEqual(rows["count"], 0)


if __name__ == "__main__":
    unittest.main()
