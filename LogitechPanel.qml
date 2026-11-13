import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Bar entry and popup for Logitech Devices reached through OpenLogi. Same
// structure as com.aeonarc.delux-m900: one Service child owns the processes,
// the popup is a KeyboardPanel, and the rules live in Model.js where
// tests/tst_model.qml covers them. Words follow GLOSSARY.md.
Panel {
  id: root
  moduleName: "com.aeonarc.logitech-panel"
  ipcTarget: "com.aeonarc.logitech-panel"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var snap: logi.snap
  readonly property string phase: logi.phase

  // Bindings that call tr() read the catalog through it, so they re-render
  // when the language changes.
  function tr(key) { return strings.t(key) }
  function num(value) { return Commons.I18n.formatNumber(value) }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  onOpenedChanged: if (opened) {
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: logi
    detailed: root.opened
    lowBatteryWarnings: root.setting("lowBatteryWarnings", true)
    t: root.tr
    formatNumber: root.num
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { logi.refresh(); return "ok" }
  }

  // A right click flips the percentage and saves the choice, as the shell's
  // battery widget does (shell/plugins/panels/power/Panel.qml).
  function togglePercentage(): void {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.setting("showPercentage", false) })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    readonly property var view: Model.barView(root.snap, root.setting("showPercentage", false), root.num)
    text: view.glyph
    labelText: view.label
    // The label keeps the caption size it had before the entry moved to
    // BarIconButton; the glyph is sized by the shell either way.
    fontSize: Style.font.caption
    // Widen the slot so the label fits inside it instead of spilling over the
    // neighbouring widget, as the shell's battery widget does for its
    // percentage (shell/plugins/panels/power/Panel.qml). Measured rather than
    // a fixed 2x because the label can also carry the charging bolt. Label,
    // gap and icon slot mirror BarIconButton's own content width.
    slotSize: vertical || view.label === ""
      ? Style.bar.iconSlot
      : Math.ceil(labelMetrics.advanceWidth + Style.space(4) + Style.bar.iconSlot)
    active: view.active
    dimmed: view.dimmed
    tooltipText: Model.tooltip(root.snap, root.tr, root.num)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }

    TextMetrics {
      id: labelMetrics
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      text: button.view.label
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Before there are Devices to show ----------
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.phase !== "ready"

            PlainText {
              width: parent.width
              text: root.tr("phase." + root.phase + ".title")
              color: Model.isBlocker(root.phase) ? root.urgent : root.fg
              font.pixelSize: Style.font.body
              font.bold: true
            }
            PlainText {
              width: parent.width
              visible: text !== ""
              text: {
                var key = "phase." + root.phase + ".body"
                var body = root.tr(key)
                return body === key ? "" : body
              }
              color: root.dim
            }
            CommandLine {
              visible: Model.isBlocker(root.phase) && !!Model.FIXES[root.phase]
              command: Model.FIXES[root.phase] || ""
            }
          }

          // ---------- One block per Device ----------
          Repeater {
            model: root.phase === "ready" && root.snap ? root.snap.devices : []
            delegate: DeviceBlock {
              required property var modelData
              // modelData is briefly null while a refresh replaces the list.
              device: modelData || ({ capabilities: {} })
            }
          }

          Item { width: parent.width; height: Style.space(2) }
        }
      }
    }
  }

  // Text the plugin owns or got from OpenLogi; never rich text.
  component PlainText: Text {
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  // A command the user runs to clear a Blocker; selectable so it can be copied.
  component CommandLine: Rectangle {
    property string command: ""
    width: parent ? parent.width : 0
    implicitHeight: commandText.implicitHeight + Style.space(12)
    radius: Math.min(4, Style.cornerRadius)
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)

    TextEdit {
      id: commandText
      anchors.fill: parent
      anchors.margins: Style.space(6)
      text: parent.command
      readOnly: true
      selectByMouse: true
      textFormat: TextEdit.PlainText
      wrapMode: TextEdit.WrapAnywhere
      color: root.fg
      font.family: "monospace"
      font.pixelSize: Style.font.caption
    }
  }

  component DeviceBlock: Column {
    id: block
    property var device: ({ capabilities: {} })
    readonly property var failure: logi.changeErrors[device.id] || null
    readonly property var readErrors: device.errors || ({})

    width: parent ? parent.width : 0
    spacing: Style.space(10)
    opacity: device.online ? 1 : 0.5

    // Name and battery.
    Item {
      width: parent.width
      implicitHeight: Math.max(nameText.implicitHeight, percentText.implicitHeight)

      PlainText {
        id: nameText
        anchors.left: parent.left
        anchors.right: percentText.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: block.device.name
        font.pixelSize: Style.font.body
        font.bold: true
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
      }
      PlainText {
        id: percentText
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        visible: Model.hasBattery(block.device)
        text: visible ? root.num(block.device.battery.percentage) + "%" : ""
        color: Model.isLow(block.device) ? root.urgent : root.fg
        font.pixelSize: Style.font.body
        font.bold: true
        wrapMode: Text.NoWrap
      }
    }
    PlainText {
      width: parent.width
      topPadding: -Style.space(8)
      text: Model.batteryNote(block.device, root.tr)
      color: root.dim
    }

    // ---------- Backlight ----------
    // Each section waits for its detail (or its read error), so opening the
    // panel never flashes an empty header.
    Section {
      visible: block.device.online && block.device.capabilities.backlight
        && (block.device.backlight !== undefined || error !== "")
      title: root.tr("section.backlight")
      error: block.readErrors.backlight || ""

      SwitchRow {
        visible: Model.offers(block.device, "on/off")
        label: root.tr("backlight.on")
        checked: !!block.device.backlight && block.device.backlight.on
        onFlipped: logi.change(block.device.id, "backlight", checked ? "off" : "on")
      }
      SwitchRow {
        visible: Model.offers(block.device, "auto")
        enabled: !!block.device.backlight && block.device.backlight.on
        label: root.tr("backlight.auto")
        checked: !!block.device.backlight && block.device.backlight.auto
        onFlipped: logi.change(block.device.id, "backlight", checked ? "auto:off" : "auto:on")
      }
      ValueSlider {
        visible: Model.offers(block.device, "level")
        enabled: Model.levelEditable(block.device)
        label: root.tr("backlight.level")
        minimum: 0
        maximum: block.device.backlight ? block.device.backlight.levels - 1 : 1
        value: block.device.backlight ? block.device.backlight.level : 0
        onCommitted: function(v) { logi.change(block.device.id, "backlight", "level:" + v) }
      }
      PlainText {
        width: parent.width
        visible: !!block.device.backlight && block.device.backlight.on && block.device.backlight.auto
        text: root.tr("backlight.autoNote")
        color: root.dim
      }
      ChangeError {
        device: block.device
        failure: block.failure
        setting: "backlight"
      }
    }

    // ---------- Fn lock ----------
    Section {
      visible: block.device.online && block.device.capabilities.fn_lock
        && (block.device.fn_lock !== undefined || error !== "")
      title: root.tr("section.fnLock")
      error: block.readErrors.fn_lock || ""

      SwitchRow {
        visible: block.device.fn_lock !== undefined
        label: root.tr("fnLock.label")
        checked: block.device.fn_lock === true
        onFlipped: logi.change(block.device.id, "fn-lock", checked ? "off" : "on")
      }
      PlainText {
        width: parent.width
        text: root.tr(block.device.fn_lock === true ? "fnLock.onNote" : "fnLock.offNote")
        color: root.dim
      }
      ChangeError {
        device: block.device
        failure: block.failure
        setting: "fn-lock"
      }
    }

    // ---------- Easy-Switch (read-only: docs/adr/0001) ----------
    Section {
      visible: block.device.online && block.device.capabilities.easy_switch
        && (block.device.easy_switch !== undefined || error !== "")
      title: root.tr("section.easySwitch")
      error: block.readErrors.easy_switch || ""

      Repeater {
        model: block.device.easy_switch ? block.device.easy_switch.channels : []
        delegate: Item {
          required property var modelData
          readonly property bool current: block.device.easy_switch.current === modelData.channel
          width: parent ? parent.width : 0
          implicitHeight: channelText.implicitHeight

          PlainText {
            id: channelText
            anchors.left: parent.left
            anchors.right: currentText.left
            anchors.rightMargin: Style.space(8)
            text: Model.channelLabel(modelData, root.tr)
            color: modelData.paired ? root.fg : root.dim
            font.bold: parent.current
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
          }
          PlainText {
            id: currentText
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            visible: parent.current
            text: root.tr("channel.current")
            color: root.dim
            wrapMode: Text.NoWrap
          }
        }
      }
      PlainText {
        width: parent.width
        text: root.tr("easySwitch.note")
        color: root.dim
      }
    }
  }

  // The last failed change to one setting, shown inside that setting's
  // Section; a Device offline shows nothing because nothing can be sent.
  component ChangeError: PlainText {
    property var device: ({})
    property var failure: null
    property string setting: ""
    visible: !!device.online && !!failure && failure.setting === setting
    text: visible ? failure.message : ""
    color: root.urgent
  }

  // A titled block, laid out like the sections of omarchy.monitor.
  component Section: Column {
    property string title: ""
    property string error: ""
    default property alias rows: body.data

    width: parent ? parent.width : 0
    spacing: Style.space(6)

    PanelSeparator { width: parent.width; foreground: root.fg }
    PanelSectionHeader { text: parent.title; foreground: root.fg; fontFamily: root.fontFamily }
    PlainText {
      width: parent.width
      visible: parent.error !== ""
      text: Model.detailError(parent.error, root.tr)
      color: root.urgent
    }
    Column {
      id: body
      width: parent.width
      spacing: Style.space(8)
    }
  }

  // A plain row with the compact switch on the trailing edge, as in the
  // first-party audio and network panels; the whole row flips it.
  component SwitchRow: Item {
    id: switchRow
    property string label: ""
    property bool checked: false
    signal flipped()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(rowLabel.implicitHeight, rowSwitch.implicitHeight)
    opacity: enabled ? 1 : 0.45

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: function() { switchRow.flipped() }
    }
    PlainText {
      id: rowLabel
      anchors.left: parent.left
      anchors.right: rowSwitch.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: switchRow.label
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
    }
    ToggleSwitch {
      id: rowSwitch
      // The switch draws inside its own inset, so with no margin its edge
      // lines up with the text that has one, as in the first-party panels.
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: switchRow.checked
      foreground: root.fg
      onToggled: switchRow.flipped()
    }
  }

  // Header with the live value on the right, then the slider. The keyboard
  // only hears the value where the drag ends.
  component ValueSlider: Column {
    id: valueSlider
    property string label: ""
    property real minimum: 0
    property real maximum: 1
    property real value: 0
    signal committed(int value)

    width: parent ? parent.width : 0
    spacing: Style.space(4)
    opacity: enabled ? 1 : 0.45

    Item {
      width: parent.width
      implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

      PlainText {
        id: labelText
        anchors.left: parent.left
        anchors.right: valueText.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: valueSlider.label
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
      }
      PlainText {
        id: valueText
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: root.num(Math.round(slider.dragging ? slider.liveValue : valueSlider.value))
        color: root.dim
        font.bold: true
        wrapMode: Text.NoWrap
      }
    }

    PanelSlider {
      id: slider
      bar: root.bar
      width: parent.width
      minimum: valueSlider.minimum
      maximum: valueSlider.maximum
      step: 1
      integer: true
      value: valueSlider.value
      onReleased: function(v) {
        var snapped = Math.round(v)
        if (snapped !== valueSlider.value) valueSlider.committed(snapped)
      }
    }
  }
}
