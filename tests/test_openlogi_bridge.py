import importlib.machinery
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("openlogi_bridge", str(ROOT / "openlogi-bridge"))
spec = importlib.util.spec_from_loader("openlogi_bridge", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

KEYBOARD_ID = "direct 046d:b369"

# Output of OpenLogi 0.9.0 against an MX Keys Mini over Bluetooth, 2026-11-12.
DEVICES = {
    "schema_version": 1, "ok": True,
    "data": {"inventory": "ready", "devices": [{
        "id": KEYBOARD_ID, "name": "MX Keys Mini", "kind": "keyboard", "online": True,
        "battery": {"percentage": 100, "level": "full", "status": "discharging"},
        "capabilities": {"fn_lock": True, "backlight": True, "easy_switch": True, "dpi": False},
    }]},
}
FN_LOCK = {"schema_version": 1, "ok": True,
           "data": {"device": KEYBOARD_ID, "persistence": "not_saved", "fn_lock": False, "default_fn_lock": False}}
EASY_SWITCH = {"schema_version": 1, "ok": True, "data": {
    "device": KEYBOARD_ID, "current_channel": 1, "can_rename": True, "channels": [
        {"channel": 1, "paired": True, "connection": "bluetooth", "name": "omarchy", "name_max_len": 24, "os": None},
        {"channel": 2, "paired": False, "connection": "unknown", "name": None, "name_max_len": 24, "os": None},
        {"channel": 3, "paired": False, "connection": "unknown", "name": None, "name_max_len": 24, "os": None},
    ]}}
BACKLIGHT_AUTO = (
    "device: MX Keys Mini (direct 046d:b369)\n"
    "  current: enabled=true mode=automatic (ambient-light sensor) status=on (following ambient light) "
    "level=2/7 battery-saving=true duration=15s\n"
    "  offers: on/off, auto, level, battery-saving, duration\n")
BACKLIGHT_SET = (
    "device: MX Keys Mini (direct 046d:b369)\n"
    "  current: enabled=true mode=automatic (ambient-light sensor) status=on (level from backlight keys) "
    "level=0/7 battery-saving=true duration=15s\n"
    "  read-back: enabled=false mode=permanent manual (software) status=off (disabled by software) "
    "level=0/7 battery-saving=true duration=15s\n"
    "✓ backlight off — persisted to the keyboard, survives reconnect and power cycle\n")
AGENT_DOWN = {"schema_version": 1, "ok": False, "error": {
    "code": "agent_unavailable", "message": "could not reach the agent's IPC endpoint: Connection refused (os error 111)"}}


class FakeOpenLogi:
    """Answers OpenLogi command lines from a table and records every call."""

    def __init__(self, answers):
        self.answers = answers
        self.calls = []

    def __call__(self, args):
        self.calls.append(args)
        key = " ".join(args)
        for prefix, answer in self.answers.items():
            if key.startswith(prefix):
                code, out, err = answer
                return code, json.dumps(out) if isinstance(out, dict) else out, err
        raise AssertionError("unexpected openlogi call: " + key)


def healthy(**extra):
    answers = {
        "api devices": (0, DEVICES, ""),
        "api fn-lock --device " + KEYBOARD_ID + " --set": (0, FN_LOCK, ""),
        "api fn-lock": (0, FN_LOCK, ""),
        "api easy-switch": (0, EASY_SWITCH, ""),
        "backlight --device MX Keys Mini status": (0, BACKLIGHT_AUTO, ""),
        "backlight --device MX Keys Mini": (0, BACKLIGHT_SET, ""),
    }
    answers.update(extra)
    return FakeOpenLogi(answers)


class ParseBacklightTest(unittest.TestCase):
    def test_automatic_mode_with_its_level_and_offers(self):
        self.assertEqual(bridge.parse_backlight(BACKLIGHT_AUTO), {
            "on": True, "auto": True, "level": 2, "levels": 8,
            "offers": ["on/off", "auto", "level", "battery-saving", "duration"]})

    def test_read_back_wins_over_the_state_before_the_change(self):
        parsed = bridge.parse_backlight(BACKLIGHT_SET)
        self.assertEqual((parsed["on"], parsed["auto"], parsed["level"]), (False, False, 0))

    def test_text_without_a_state_line_is_not_a_backlight(self):
        self.assertIsNone(bridge.parse_backlight("Error: something"))
        self.assertIsNone(bridge.parse_backlight(""))


class ErrorLineTest(unittest.TestCase):
    def test_first_error_line_without_its_prefix(self):
        text = "Error: no matching online backlight device; use --device <unique name substring>.\nOnline HID++ devices:\n"
        self.assertEqual(bridge.error_line(text), "no matching online backlight device; use --device <unique name substring>.")

    def test_the_reason_under_caused_by_wins_over_the_action(self):
        text = "Error: set backlight level 9\n\nCaused by:\n    the keyboard does not offer backlight level 9\n"
        self.assertEqual(bridge.error_line(text), "the keyboard does not offer backlight level 9")
        text = "Error: x\n\nCaused by:\n    0: could not reach the agent\n    1: Connection refused\n"
        self.assertEqual(bridge.error_line(text), "could not reach the agent")

    def test_long_or_empty_output_still_gives_a_bounded_message(self):
        self.assertLessEqual(len(bridge.error_line("Error: " + "x" * 2000)), bridge.MAX_TEXT)
        self.assertTrue(bridge.error_line(""))


class SnapshotTest(unittest.TestCase):
    def test_a_healthy_keyboard_without_details(self):
        fake = healthy()
        snap = bridge.snapshot(fake, details=False, solaar=False)
        self.assertIsNone(snap["blocker"])
        self.assertEqual(snap["inventory"], "ready")
        device = snap["devices"][0]
        self.assertEqual(device, {
            "id": KEYBOARD_ID, "name": "MX Keys Mini", "kind": "keyboard", "online": True,
            "battery": {"percentage": 100, "status": "discharging"},
            "capabilities": {"backlight": True, "fn_lock": True, "easy_switch": True}})
        self.assertEqual(fake.calls, [["api", "devices"]])

    def test_details_read_every_announced_capability(self):
        snap = bridge.snapshot(healthy(), details=True, solaar=False)
        device = snap["devices"][0]
        self.assertEqual(device["fn_lock"], False)
        self.assertEqual(device["backlight"]["level"], 2)
        self.assertEqual(device["easy_switch"], {"current": 1, "channels": [
            {"channel": 1, "paired": True, "name": "omarchy"},
            {"channel": 2, "paired": False, "name": ""},
            {"channel": 3, "paired": False, "name": ""}]})

    def test_details_skip_offline_devices_and_missing_capabilities(self):
        offline = json.loads(json.dumps(DEVICES))
        offline["data"]["devices"][0]["online"] = False
        fake = healthy(**{"api devices": (0, offline, "")})
        bridge.snapshot(fake, details=True, solaar=False)
        self.assertEqual(fake.calls, [["api", "devices"]])

    def test_a_failed_detail_is_kept_on_the_device_not_raised_as_a_blocker(self):
        refused = {"schema_version": 1, "ok": False, "error": {"code": "unsupported", "message": "not answering"}}
        snap = bridge.snapshot(healthy(**{"api fn-lock": (1, refused, "")}), details=True, solaar=False)
        self.assertIsNone(snap["blocker"])
        self.assertEqual(snap["devices"][0]["errors"], {"fn_lock": "not answering"})
        self.assertNotIn("fn_lock", snap["devices"][0])

    def test_agent_down_is_a_blocker(self):
        snap = bridge.snapshot(healthy(**{"api devices": (1, AGENT_DOWN, "")}), details=True, solaar=False)
        self.assertEqual(snap["blocker"], "agent")
        self.assertEqual(snap["devices"], [])

    def test_openlogi_missing_is_a_blocker(self):
        def missing(args):
            raise bridge.OpenLogiMissing()
        self.assertEqual(bridge.snapshot(missing, details=False, solaar=False)["blocker"], "missing")

    def test_solaar_running_is_a_blocker_even_when_openlogi_answers(self):
        self.assertEqual(bridge.snapshot(healthy(), details=False, solaar=True)["blocker"], "solaar")

    def test_an_unknown_schema_or_garbage_is_incompatible(self):
        newer = dict(DEVICES, schema_version=2)
        self.assertEqual(bridge.snapshot(healthy(**{"api devices": (0, newer, "")}), False, False)["blocker"], "incompatible")
        self.assertEqual(bridge.snapshot(healthy(**{"api devices": (0, "not json", "")}), False, False)["blocker"], "incompatible")
        refused = {"schema_version": 1, "ok": False, "error": {
            "code": "unsupported_schema", "message": "this bridge speaks schema 1"}}
        self.assertEqual(bridge.snapshot(healthy(**{"api devices": (1, refused, "")}), False, False)["blocker"], "incompatible")

    def test_a_timeout_is_the_agent_not_an_incompatible_openlogi(self):
        timed_out = healthy(**{"api devices": (124, "", "Error: openlogi did not answer within 10 seconds")})
        self.assertEqual(bridge.snapshot(timed_out, details=False, solaar=False)["blocker"], "agent")

    def test_an_unknown_envelope_error_is_the_agent_not_incompatible(self):
        refused = {"schema_version": 1, "ok": False, "error": {
            "code": "hidpp_busy", "message": "the device did not answer"}}
        self.assertEqual(bridge.snapshot(healthy(**{"api devices": (1, refused, "")}), False, False)["blocker"], "agent")

    def test_device_fields_are_bounded_and_typed(self):
        hostile = json.loads(json.dumps(DEVICES))
        entry = hostile["data"]["devices"][0]
        entry["name"] = "<img src=x>" + "A" * 500
        entry["kind"] = "toaster"
        entry["battery"] = {"percentage": 900, "status": "on fire"}
        hostile["data"]["devices"] = [entry] * 100
        snap = bridge.snapshot(healthy(**{"api devices": (0, hostile, "")}), False, False)
        self.assertLessEqual(len(snap["devices"]), bridge.MAX_DEVICES)
        device = snap["devices"][0]
        self.assertLessEqual(len(device["name"]), bridge.MAX_NAME)
        self.assertEqual(device["kind"], "other")
        self.assertEqual(device["battery"], {"percentage": None, "status": "unknown"})


class ChangeTest(unittest.TestCase):
    def test_fn_lock_is_set_and_saved(self):
        fake = healthy()
        self.assertEqual(bridge.change(fake, KEYBOARD_ID, "fn-lock", "on"), {"ok": True})
        self.assertEqual(fake.calls[-1], ["api", "fn-lock", "--device", KEYBOARD_ID, "--set", "on", "--save"])

    def test_backlight_goes_by_the_device_name(self):
        fake = healthy()
        self.assertEqual(bridge.change(fake, KEYBOARD_ID, "backlight", "level:3"), {"ok": True})
        self.assertEqual(fake.calls[-1], ["backlight", "--device", "MX Keys Mini", "level", "3"])
        bridge.change(fake, KEYBOARD_ID, "backlight", "auto:off")
        self.assertEqual(fake.calls[-1], ["backlight", "--device", "MX Keys Mini", "auto", "off"])
        bridge.change(fake, KEYBOARD_ID, "backlight", "off")
        self.assertEqual(fake.calls[-1], ["backlight", "--device", "MX Keys Mini", "off"])

    def test_values_outside_the_vocabulary_never_reach_openlogi(self):
        for setting, value in [("fn-lock", "maybe"), ("backlight", "level:99"), ("backlight", "level:x"),
                               ("backlight", "rm -rf"), ("dpi", "800")]:
            fake = healthy()
            result = bridge.change(fake, KEYBOARD_ID, setting, value)
            self.assertFalse(result["ok"], (setting, value))
            self.assertEqual(fake.calls, [], (setting, value))

    def test_an_unknown_device_is_refused(self):
        result = bridge.change(healthy(), "direct 046d:0000", "fn-lock", "on")
        self.assertEqual(result, {"ok": False, "error": "device-gone"})

    def test_a_backlight_change_refuses_a_name_that_matches_another_device(self):
        devices = json.loads(json.dumps(DEVICES))
        devices["data"]["devices"].append(
            dict(devices["data"]["devices"][0], id="bolt 046d:c548", name="MX Keys"))
        fake = healthy(**{"api devices": (0, devices, "")})
        self.assertEqual(bridge.change(fake, "bolt 046d:c548", "backlight", "off"),
                         {"ok": False, "error": "ambiguous-name"})
        self.assertEqual(fake.calls, [["api", "devices"]])

    def test_the_detail_read_stores_an_error_instead_of_reading_the_wrong_device(self):
        devices = json.loads(json.dumps(DEVICES))
        devices["data"]["devices"].append(
            dict(devices["data"]["devices"][0], id="bolt 046d:c548", name="MX Keys"))
        fake = healthy(**{"api devices": (0, devices, ""),
                          "api fn-lock --device bolt 046d:c548": (0, FN_LOCK, ""),
                          "api easy-switch --device bolt 046d:c548": (0, EASY_SWITCH, "")})
        snap = bridge.snapshot(fake, details=True, solaar=False)
        mx_keys = next(d for d in snap["devices"] if d["id"] == "bolt 046d:c548")
        self.assertEqual(mx_keys["errors"]["backlight"], "ambiguous-name")
        self.assertNotIn("backlight", mx_keys)
        for call in fake.calls:
            self.assertNotEqual(call[:3], ["backlight", "--device", "MX Keys"])

    def test_a_refused_change_carries_openlogi_s_message(self):
        failing = healthy(**{"backlight --device MX Keys Mini": (1, "", "Error: the keyboard did not answer\n")})
        self.assertEqual(bridge.change(failing, KEYBOARD_ID, "backlight", "on"),
                         {"ok": False, "error": "the keyboard did not answer"})


if __name__ == "__main__":
    unittest.main()
