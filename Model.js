.pragma library

// Rules for the bar entry and the panel, kept out of QML so tests/tst_model.qml
// can reach them. Words follow GLOSSARY.md. Every function that produces text
// takes `t`, the plugin's translator (key -> template), so the same rules serve
// every language; templates are filled with fill(), never glued together.

var LOW = 15
var CRITICAL = 5
// A charge back above this starts a new discharge for the warnings.
var HYSTERESIS = 20
var GLYPH = { keyboard: "\u{F030C}", mouse: "\u{F037D}", other: "\u{F030C}" }
var GLYPH_CHARGING = "\u{F140B}"
var GLYPH_ALERT = "\u{F0026}"
var BLOCKERS = ["missing", "agent", "solaar", "incompatible", "bridge"]
// The command that clears each Blocker, shown in the panel; null when the
// fix is not one command.
var FIXES = {
  missing: "yay -S openlogi-bin",
  agent: "systemctl --user enable --now openlogi-agent",
  solaar: "systemctl --user disable --now solaar 2>/dev/null; pkill -x solaar",
  incompatible: null,
  bridge: null
}

function fill(template, args) {
  return String(template).replace(/%(\d)/g, function(match, n) {
    var value = args[Number(n) - 1]
    return value === undefined ? match : String(value)
  })
}

// The bridge's output, or a "bridge" Blocker when it is not what the bridge prints.
function parseSnapshot(text) {
  var raw = null
  try { raw = JSON.parse(String(text || "")) } catch (error) { raw = null }
  if (!raw || typeof raw !== "object" || !Array.isArray(raw.devices))
    return { blocker: "bridge", inventory: "", devices: [] }
  var blocker = BLOCKERS.indexOf(raw.blocker) >= 0 ? raw.blocker : null
  if (raw.blocker !== null && blocker === null) blocker = "bridge"
  return { blocker: blocker, inventory: String(raw.inventory || ""), devices: sortDevices(raw.devices) }
}

// Online Devices first, then Offline Devices; by name within each group.
function sortDevices(devices) {
  return devices.slice().sort(function(a, b) {
    if (a.online !== b.online) return a.online ? -1 : 1
    return String(a.name).localeCompare(String(b.name))
  })
}

function hasBattery(device) {
  return device.online && device.battery && typeof device.battery.percentage === "number"
}

// The Device whose charge is the Bar Battery: the lowest among online Devices.
function barBatteryDevice(devices) {
  var lowest = null
  for (var i = 0; i < devices.length; i++) {
    if (!hasBattery(devices[i])) continue
    if (lowest === null || devices[i].battery.percentage < lowest.battery.percentage) lowest = devices[i]
  }
  return lowest
}

function isLow(device) {
  return device !== null && device.battery.status === "discharging" && device.battery.percentage <= LOW
}

// What the panel has to say before it can show Devices: "starting" (no
// snapshot yet), a Blocker, "searching" (OpenLogi has not finished looking),
// "none" (it looked and found nothing), or "ready".
function phase(snap) {
  if (snap === null || snap === undefined) return "starting"
  if (snap.blocker) return snap.blocker
  if (snap.devices.length > 0) return "ready"
  return snap.inventory === "ready" ? "none" : "searching"
}

function isBlocker(phaseName) {
  return BLOCKERS.indexOf(phaseName) >= 0
}

function barView(snap, showPercentage, formatNumber) {
  var format = formatNumber || String
  var current = phase(snap)
  if (isBlocker(current)) return { text: GLYPH_ALERT, active: true, dimmed: false }
  if (current !== "ready") return { text: GLYPH.keyboard, active: false, dimmed: true }
  var device = barBatteryDevice(snap.devices)
  if (device === null) {
    // Online Devices without a level still mean "something is on": show the
    // first one's glyph undimmed; only all-offline dims.
    var online = null
    for (var i = 0; i < snap.devices.length; i++) {
      if (snap.devices[i].online) { online = snap.devices[i]; break }
    }
    var shown = online || snap.devices[0]
    return { text: GLYPH[shown.kind] || GLYPH.other, active: false, dimmed: online === null }
  }
  var text = GLYPH[device.kind] || GLYPH.other
  if (device.battery.status === "charging") text += " " + GLYPH_CHARGING
  if (showPercentage) text += " " + format(device.battery.percentage) + "%"
  return { text: text, active: isLow(device), dimmed: false }
}

// One line per Device, or only the Blocker when there is one.
function tooltip(snap, t, formatNumber) {
  var format = formatNumber || String
  var current = phase(snap)
  if (current !== "ready") return t("phase." + current + ".title")
  return snap.devices.map(function(device) { return deviceLine(device, t, format) }).join("\n")
}

function deviceLine(device, t, formatNumber) {
  var format = formatNumber || String
  if (!device.online) return fill(t("device.offlineLine"), [device.name])
  if (!hasBattery(device)) return device.name
  return fill(t("device.batteryLine"), [device.name, format(device.battery.percentage)])
}

// The battery state under the Device name in the panel.
function batteryNote(device, t) {
  if (!device.online) return t("battery.offline")
  if (!hasBattery(device)) return t("battery.unknown")
  return t("battery." + device.battery.status)
}

// Low Battery Warnings due now, and the memory of which thresholds each
// Device has been warned about in its current discharge, keyed by name
// because ids change on reconnect (docs/adr/0001). Only charging, a full
// battery or a charge back above HYSTERESIS starts a new discharge; an
// "unknown" status and Offline Devices keep what they had, so a keyboard
// that sleeps or bounces around LOW is not warned twice.
function warnings(memory, devices) {
  var next = {}
  var notify = []
  for (var key in memory) next[key] = memory[key].slice()
  for (var i = 0; i < devices.length; i++) {
    var device = devices[i]
    if (!device.online) continue
    var name = String(device.name)
    var battery = device.battery || {}
    var status = battery.status
    var level = typeof battery.percentage === "number" ? battery.percentage : null
    if (status === "charging" || status === "full" || (status === "discharging" && level !== null && level > HYSTERESIS)) {
      delete next[name]
      continue
    }
    if (status !== "discharging" || level === null || level > LOW) continue
    var warned = next[name] || []
    var threshold = level <= CRITICAL ? CRITICAL : LOW
    if (warned.indexOf(threshold) < 0) {
      notify.push({ id: device.id, name: device.name, threshold: threshold, percentage: level })
      warned = warned.concat(threshold === CRITICAL ? [LOW, CRITICAL] : [LOW])
    }
    next[name] = warned
  }
  return { memory: next, notify: notify }
}

// notify-send bodies are read as markup by the notification daemon; Device
// names come from OpenLogi and must reach it as plain text.
function escapeMarkup(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;")
}

// Lists that reach QML through a Repeater's modelData are Qt lists, not JS
// arrays, so this walks anything with a length.
function offers(device, what) {
  var list = device.backlight ? device.backlight.offers : null
  if (!list || typeof list.length !== "number") return false
  for (var i = 0; i < list.length; i++) if (list[i] === what) return true
  return false
}

// The level slider means something only while the backlight is on and the
// ambient-light sensor is not choosing the level.
function levelEditable(device) {
  return offers(device, "level") && device.backlight.on && !device.backlight.auto
}

// The Device as it will look once a change lands, so the panel answers the
// click at once; the next snapshot replaces it either way.
function withChange(device, setting, value) {
  var next = JSON.parse(JSON.stringify(device))
  if (setting === "fn-lock") next.fn_lock = value === "on"
  if (setting === "backlight" && next.backlight) {
    if (value === "on" || value === "off") next.backlight.on = value === "on"
    else if (value === "auto:on" || value === "auto:off") next.backlight.auto = value === "auto:on"
    else if (value.indexOf("level:") === 0) {
      next.backlight.level = Number(value.slice(6))
      next.backlight.auto = false
    }
  }
  return next
}

function replaceDevice(snap, device) {
  if (!snap) return snap
  return {
    blocker: snap.blocker,
    inventory: snap.inventory,
    devices: snap.devices.map(function(d) { return d.id === device.id ? device : d })
  }
}

function findDevice(snap, id) {
  if (!snap) return null
  for (var i = 0; i < snap.devices.length; i++) if (snap.devices[i].id === id) return snap.devices[i]
  return null
}

// The bridge's answer to a change: "" when it landed, otherwise the text to
// show under the block. Bridge codes become sentences; OpenLogi's own
// messages are shown as they come.
function changeError(text, t) {
  var raw = null
  try { raw = JSON.parse(String(text || "")) } catch (error) { raw = null }
  if (!raw || typeof raw !== "object") return t("change.failed")
  if (raw.ok === true) return ""
  var code = String(raw.error || "")
  var known = ["device-gone", "invalid-change", "ambiguous-name", "missing", "agent", "solaar", "incompatible"]
  if (known.indexOf(code) >= 0) return t("change." + code)
  return code !== "" ? code : t("change.failed")
}

function channelLabel(channel, t) {
  if (!channel.paired) return fill(t("channel.empty"), [channel.channel])
  if (channel.name) return fill(t("channel.named"), [channel.channel, channel.name])
  return fill(t("channel.paired"), [channel.channel])
}

// A Capability detail OpenLogi could not read, shown at the top of its
// Section. Bridge codes become their sentence; anything else is OpenLogi's
// own message.
function detailError(code, t) {
  if (code === "ambiguous-name") return t("change.ambiguous-name")
  return fill(t("detail.error"), [code])
}
