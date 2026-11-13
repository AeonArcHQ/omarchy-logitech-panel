import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Device state for one bar entry. `openlogi-bridge snapshot` is read on a
// timer: rarely while the panel is closed (battery changes slowly), often and
// with --details while it is open, so changes made on the keyboard itself
// (Fn+Esc, the backlight keys) show up. Changes go out one at a time through
// `openlogi-bridge set`, shown at once and confirmed by the next snapshot.
Item {
  id: root

  // The panel is open: read the Capability details and read more often.
  property bool detailed: false
  property bool lowBatteryWarnings: true
  // Translator for notification text; set by the panel.
  property var t: function(key) { return key }
  property var formatNumber: String

  property var snap: null
  // Device id -> { setting, message } for the last change that failed.
  property var changeErrors: ({})
  property bool busy: false

  readonly property string bridgePath: String(Qt.resolvedUrl("openlogi-bridge")).replace(/^file:\/\//, "")
  readonly property string phase: Model.phase(root.snap)

  property var _queue: []
  property var _running: null
  property var _warned: ({})
  property var _notices: []
  // Bump on every change sent; a snapshot records it when it starts and its
  // answer is dropped when a change went out in the meantime (it was read
  // before the change could land).
  property int _generation: 0
  property int _snapshotGeneration: 0
  // Recorded when a read starts, like _snapshotGeneration: whether this read
  // asks for the Capability details, so onSnapshot knows what it can keep.
  property bool _snapshotDetailed: false
  // Reads keep asking for the Capability details until one snapshot with
  // Devices lands; a Blocker or a still-searching answer keeps them coming.
  property bool _hasDetails: false

  function refresh() {
    if (snapshotProcess.running) {
      root._again = true
      return
    }
    root._snapshotGeneration = root._generation
    root._snapshotDetailed = root.detailed || !root._hasDetails
    snapshotProcess.command = root._snapshotDetailed ? [root.bridgePath, "snapshot", "--details"] : [root.bridgePath, "snapshot"]
    snapshotProcess.running = true
  }
  property bool _again: false

  onDetailedChanged: if (detailed) refresh()

  function change(deviceId, setting, value) {
    var device = Model.findDevice(root.snap, deviceId)
    if (device === null) return
    root.snap = Model.replaceDevice(root.snap, Model.withChange(device, setting, value))
    root._generation++
    // A newer change to the same setting replaces one still waiting.
    root._queue = root._queue.filter(function(job) { return job.id !== deviceId || job.setting !== setting })
      .concat([{ id: deviceId, setting: setting, value: value }])
    root.flush()
  }

  function flush() {
    if (changeProcess.running || root._queue.length === 0) return
    root._running = root._queue[0]
    root._queue = root._queue.slice(1)
    root.busy = true
    changeProcess.command = [root.bridgePath, "set", root._running.id, root._running.setting, root._running.value]
    changeProcess.running = true
  }

  function onSnapshot(text) {
    // A change sent since this snapshot started would be undone by it.
    if (root._snapshotGeneration !== root._generation) return
    if (changeProcess.running || root._queue.length > 0) return
    var next = Model.parseSnapshot(text)
    if (!next.blocker && next.devices.length > 0) root._hasDetails = true
    root.snap = root._snapshotDetailed ? next : Model.keepDetails(root.snap, next)
    var due = Model.warnings(root._warned, next.devices)
    root._warned = due.memory
    if (root.lowBatteryWarnings) {
      for (var i = 0; i < due.notify.length; i++) root.warn(due.notify[i])
    }
  }

  function warn(notice) {
    var title = root.t("warning.title")
    var body = Model.fill(root.t(notice.threshold === Model.CRITICAL ? "warning.critical" : "warning.low"),
      [notice.name, root.formatNumber(notice.percentage)])
    root._notices = root._notices.concat([[
      "notify-send", "--app-name=Logitech Panel", "--icon=input-keyboard",
      "--urgency=" + (notice.threshold === Model.CRITICAL ? "critical" : "normal"),
      title, Model.escapeMarkup(body)
    ]])
    root.flushNotices()
  }

  function flushNotices() {
    if (notifyProcess.running || root._notices.length === 0) return
    notifyProcess.command = root._notices[0]
    root._notices = root._notices.slice(1)
    notifyProcess.running = true
  }

  Timer {
    id: pollTimer
    running: true
    repeat: true
    triggeredOnStart: true
    // While OpenLogi is still looking for Devices, look again soon.
    interval: root.detailed ? 4000 : (root.phase === "searching" || root.phase === "starting" ? 3000 : 60000)
    onTriggered: root.refresh()
  }

  Process {
    id: snapshotProcess
    running: false
    command: []
    stdout: StdioCollector { id: snapshotOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.onSnapshot(snapshotOut.text)
      if (root._again) {
        root._again = false
        root.refresh()
      }
    }
  }

  Process {
    id: changeProcess
    running: false
    command: []
    stdout: StdioCollector { id: changeOut; waitForEnd: true }
    onExited: function(exitCode) {
      var job = root._running
      var message = Model.changeError(changeOut.text, root.t)
      var errors = Object.assign({}, root.changeErrors)
      if (message === "") delete errors[job.id]
      else errors[job.id] = { setting: job.setting, message: message }
      root.changeErrors = errors
      root._running = null
      root.busy = false
      root.flush()
      if (!changeProcess.running) root.refresh()
    }
  }

  Process {
    id: notifyProcess
    running: false
    command: []
    onExited: root.flushNotices()
  }
}
