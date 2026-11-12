import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "LogitechPanelModel"

  // A translator that shows which key was used and keeps the placeholders.
  function t(key) {
    var templates = {
      "device.batteryLine": "%1 — %2%",
      "device.offlineLine": "%1 — offline",
      "channel.empty": "%1 · empty",
      "channel.named": "%1 · %2",
      "channel.paired": "%1 · paired"
    }
    return templates[key] || key
  }

  function keyboard(extra) {
    var device = {
      id: "direct 046d:b369", name: "MX Keys Mini", kind: "keyboard", online: true,
      battery: { percentage: 100, status: "discharging" },
      capabilities: { backlight: true, fn_lock: true, easy_switch: true }
    }
    for (var key in extra) device[key] = extra[key]
    return device
  }

  function snapOf(devices) {
    return { blocker: null, inventory: "ready", devices: devices }
  }

  function test_bar_shows_the_lowest_online_battery() {
    var mouse = keyboard({ id: "m", name: "MX Master 3S", kind: "mouse", battery: { percentage: 40, status: "discharging" } })
    var asleep = keyboard({ id: "k", name: "K380", online: false, battery: { percentage: 3, status: "discharging" } })
    var snap = snapOf([keyboard(), mouse, asleep])
    compare(Model.barView(snap, true), { glyph: "\u{F037D}", label: "40%", active: false, dimmed: false })
    compare(Model.barView(snap, false), { glyph: "\u{F037D}", label: "", active: false, dimmed: false })
  }

  function test_low_battery_is_highlighted_only_while_discharging() {
    var low = snapOf([keyboard({ battery: { percentage: 15, status: "discharging" } })])
    compare(Model.barView(low, true).active, true)
    var charging = snapOf([keyboard({ battery: { percentage: 10, status: "charging" } })])
    compare(Model.barView(charging, true), { glyph: "\u{F030C}", label: "\u{F140B} 10%", active: false, dimmed: false })
    compare(Model.barView(charging, false), { glyph: "\u{F030C}", label: "\u{F140B}", active: false, dimmed: false })
    var fine = snapOf([keyboard({ battery: { percentage: 16, status: "discharging" } })])
    compare(Model.barView(fine, true).active, false)
  }

  function test_numbers_go_through_the_language_formatter() {
    var snap = snapOf([keyboard({ battery: { percentage: 42, status: "discharging" } })])
    compare(Model.barView(snap, true, function(n) { return "٤٢" }), { glyph: "\u{F030C}", label: "٤٢%", active: false, dimmed: false })
  }

  function test_phases_before_devices_show() {
    compare(Model.phase(null), "starting")
    compare(Model.phase({ blocker: null, inventory: "loading", devices: [] }), "searching")
    compare(Model.phase({ blocker: null, inventory: "ready", devices: [] }), "none")
    compare(Model.phase({ blocker: "agent", inventory: "", devices: [] }), "agent")
    compare(Model.phase(snapOf([keyboard()])), "ready")
  }

  function test_a_blocker_shows_the_alert_and_only_itself_in_the_tooltip() {
    var snap = { blocker: "solaar", inventory: "", devices: [] }
    compare(Model.barView(snap, true), { glyph: "\u{F0026}", label: "", active: true, dimmed: false })
    compare(Model.tooltip(snap, t), "phase.solaar.title")
    verify(Model.FIXES.solaar.indexOf("solaar") >= 0)
  }

  function test_waiting_and_all_offline_dim_the_icon() {
    compare(Model.barView(null, true).dimmed, true)
    compare(Model.barView({ blocker: null, inventory: "loading", devices: [] }, true).dimmed, true)
    var asleep = snapOf([keyboard({ online: false })])
    compare(Model.barView(asleep, true), { glyph: "\u{F030C}", label: "", active: false, dimmed: true })
  }

  function test_an_online_device_without_a_level_does_not_dim_the_icon() {
    var mute = keyboard({ name: "MX Master 3S", kind: "mouse", battery: { status: "unknown" } })
    compare(Model.barView(snapOf([mute]), true), { glyph: "\u{F037D}", label: "", active: false, dimmed: false })
    var asleep = keyboard({ id: "k", name: "K380", online: false })
    compare(Model.barView(snapOf([mute, asleep]), true).dimmed, false)
  }

  function test_tooltip_has_one_line_per_device() {
    var asleep = keyboard({ id: "k", name: "K380", online: false })
    compare(Model.tooltip(snapOf([keyboard(), asleep]), t), "MX Keys Mini — 100%\nK380 — offline")
  }

  function test_snapshot_parsing_sorts_and_rejects_garbage() {
    var text = JSON.stringify({ blocker: null, inventory: "ready", devices: [
      keyboard({ id: "z", name: "Zeta", online: false }), keyboard({ id: "b", name: "Beta" }), keyboard({ id: "a", name: "Alpha" })] })
    compare(Model.parseSnapshot(text).devices.map(function(d) { return d.name }), ["Alpha", "Beta", "Zeta"])
    compare(Model.parseSnapshot("not json").blocker, "bridge")
    compare(Model.parseSnapshot(JSON.stringify({ blocker: "weird", devices: [] })).blocker, "bridge")
    compare(Model.parseSnapshot(JSON.stringify({ blocker: "agent", devices: [] })).blocker, "agent")
  }

  function test_warnings_fire_once_per_threshold_per_discharge() {
    var at = function(percentage, status) { return [keyboard({ battery: { percentage: percentage, status: status || "discharging" } })] }
    var step = Model.warnings({}, at(16))
    compare(step.notify, [])
    step = Model.warnings(step.memory, at(15))
    compare(step.notify.map(function(n) { return n.threshold }), [15])
    step = Model.warnings(step.memory, at(12))
    compare(step.notify, [])
    step = Model.warnings(step.memory, at(5))
    compare(step.notify.map(function(n) { return n.threshold }), [5])
    step = Model.warnings(step.memory, at(4))
    compare(step.notify, [])
    // Charging starts a new discharge.
    step = Model.warnings(step.memory, at(6, "charging"))
    step = Model.warnings(step.memory, at(14))
    compare(step.notify.map(function(n) { return n.threshold }), [15])
  }

  function test_a_device_found_already_critical_gets_one_warning() {
    var step = Model.warnings({}, [keyboard({ battery: { percentage: 3, status: "discharging" } })])
    compare(step.notify.length, 1)
    compare(step.notify[0].threshold, 5)
    compare(Model.warnings(step.memory, [keyboard({ battery: { percentage: 3, status: "discharging" } })]).notify, [])
  }

  function test_an_offline_device_keeps_its_warnings() {
    var step = Model.warnings({}, [keyboard({ battery: { percentage: 10, status: "discharging" } })])
    step = Model.warnings(step.memory, [keyboard({ online: false })])
    step = Model.warnings(step.memory, [keyboard({ battery: { percentage: 10, status: "discharging" } })])
    compare(step.notify, [])
  }

  function test_small_bounces_and_unknown_status_do_not_warn_twice() {
    var at = function(percentage, status) { return [keyboard({ battery: { percentage: percentage, status: status || "discharging" } })] }
    var step = Model.warnings({}, at(15))
    compare(step.notify.length, 1)
    step = Model.warnings(step.memory, at(16))
    step = Model.warnings(step.memory, at(15))
    compare(step.notify, [])
    step = Model.warnings(step.memory, at(15, "unknown"))
    step = Model.warnings(step.memory, at(14))
    compare(step.notify, [])
  }

  function test_the_warning_memory_follows_the_name_not_the_id() {
    var at = function(id) { return [keyboard({ id: id, battery: { percentage: 12, status: "discharging" } })] }
    var step = Model.warnings({}, at("id-a"))
    compare(step.notify.length, 1)
    step = Model.warnings(step.memory, at("id-b"))
    compare(step.notify, [])
  }

  function test_charging_or_recovering_past_twenty_starts_a_new_discharge() {
    var at = function(percentage, status) { return [keyboard({ battery: { percentage: percentage, status: status || "discharging" } })] }
    var step = Model.warnings({}, at(14))
    compare(step.notify.length, 1)
    step = Model.warnings(step.memory, at(14, "charging"))
    step = Model.warnings(step.memory, at(14))
    compare(step.notify.map(function(n) { return n.threshold }), [15])
    step = Model.warnings(step.memory, at(21))
    step = Model.warnings(step.memory, at(14))
    compare(step.notify.map(function(n) { return n.threshold }), [15])
  }

  function test_names_reach_notifications_as_plain_text() {
    compare(Model.escapeMarkup("<img src=\"https://example.invalid/t\"> & 'x'"),
      "&lt;img src=&quot;https://example.invalid/t&quot;&gt; &amp; &#39;x&#39;")
  }

  function test_fill_keeps_placeholders_it_has_no_value_for() {
    compare(Model.fill("%2 then %1, %3", ["a", "b"]), "b then a, %3")
    compare(Model.fill("%1", ["%2"]), "%2")
  }

  function test_level_is_editable_only_when_on_and_not_automatic() {
    var light = { on: true, auto: true, level: 2, levels: 8, offers: ["on/off", "auto", "level"] }
    verify(!Model.levelEditable(keyboard({ backlight: light })))
    verify(Model.levelEditable(Model.withChange(keyboard({ backlight: light }), "backlight", "auto:off")))
    verify(!Model.levelEditable(Model.withChange(keyboard({ backlight: light }), "backlight", "off")))
    verify(!Model.levelEditable(keyboard({ backlight: { on: true, auto: false, level: 2, levels: 8, offers: ["on/off"] } })))
  }

  // A Repeater hands modelData's arrays to QML as Qt lists, which fail
  // Array.isArray; offers() must take anything with a length.
  function test_offers_reads_array_like_lists() {
    var qtList = { length: 2, 0: "on/off", 1: "level" }
    verify(Model.offers(keyboard({ backlight: { on: true, auto: false, level: 1, levels: 8, offers: qtList } }), "level"))
    verify(!Model.offers(keyboard({ backlight: { on: true, auto: false, level: 1, levels: 8, offers: qtList } }), "auto"))
    verify(!Model.offers(keyboard({}), "level"))
  }

  function test_changes_predict_the_new_state_without_touching_the_original() {
    var device = keyboard({ fn_lock: false, backlight: { on: true, auto: true, level: 2, levels: 8, offers: [] } })
    var next = Model.withChange(device, "backlight", "level:5")
    compare([next.backlight.level, next.backlight.auto], [5, false])
    compare(device.backlight.level, 2)
    compare(Model.withChange(device, "fn-lock", "on").fn_lock, true)
    var snap = Model.replaceDevice(snapOf([device]), next)
    compare(Model.findDevice(snap, device.id).backlight.level, 5)
  }

  function test_change_errors() {
    compare(Model.changeError('{"ok": true}', t), "")
    compare(Model.changeError('{"ok": false, "error": "device-gone"}', t), "change.device-gone")
    compare(Model.changeError('{"ok": false, "error": "the keyboard does not offer backlight level 9"}', t),
      "the keyboard does not offer backlight level 9")
    compare(Model.changeError("", t), "change.failed")
  }

  function test_channel_labels() {
    compare(Model.channelLabel({ channel: 1, paired: true, name: "omarchy" }, t), "1 · omarchy")
    compare(Model.channelLabel({ channel: 2, paired: true, name: "" }, t), "2 · paired")
    compare(Model.channelLabel({ channel: 3, paired: false, name: "" }, t), "3 · empty")
  }

  // A detail read that fails with a known bridge code shows its sentence, not the code.
  function test_detail_errors_translate_known_codes() {
    compare(Model.detailError("ambiguous-name", t), "change.ambiguous-name")
    compare(Model.detailError("timed out", function(key) { return key === "detail.error" ? "Could not read this: %1" : key }),
      "Could not read this: timed out")
  }
}
