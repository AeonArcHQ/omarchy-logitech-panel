# Logitech Panel

Logitech keyboards and mice in the Omarchy bar: battery, backlight, Fn lock
and Easy-Switch channels.

Powered by [OpenLogi](https://github.com/AprilNEA/OpenLogi). This project is
not affiliated with OpenLogi or Logitech.

- The bar shows the device glyph, with 󱐋 while charging, and, with
  `showPercentage` on, the lowest battery among the devices that are on.
  The entry takes the warning color at 15% or less on battery, and dims
  while every device is asleep or out of range.
- The tooltip has one line per device: `MX Keys Mini — 80%`, or `offline`.
- A click opens the panel, one block per device: battery state, then the
  sections the device announces to OpenLogi. Backlight: on/off, automatic
  brightness (the light sensor) and the level. Fn lock: whether the top row
  sends F1–F12 or media keys. Easy-Switch: the channels, which one is in use
  and the name each computer gave it.
- Easy-Switch is read-only: OpenLogi 0.9.0 cannot move a keyboard to another
  channel ([AprilNEA/OpenLogi#650](https://github.com/AprilNEA/OpenLogi/issues/650)).
  Use the Easy-Switch keys.
- A notification at 15% and another at 5%, once per discharge.
- When something stops the panel from reaching the devices (OpenLogi missing,
  its agent stopped, Solaar holding the devices), the bar shows 󰀦 and the
  panel names the problem and the command that fixes it. The plugin never
  installs or starts anything by itself.
- Settings: `showPercentage` (default off; a right click on the bar entry
  flips it) and `lowBatteryWarnings` (default
  on).
- IPC: `omarchy-shell com.aeonarc.logitech-panel open|close|toggle|refresh`.

Tested only with an MX Keys Mini over Bluetooth. Other devices OpenLogi lists
show up with whatever controls they announce; reports are welcome.

## Requirements

[OpenLogi](https://github.com/AprilNEA/OpenLogi) 0.9 and its agent:

```sh
yay -S openlogi-bin
systemctl --user enable --now openlogi-agent
```

Solaar and OpenLogi cannot share a device. If Solaar is installed, quit it
and turn off its autostart.

## Installation

```sh
omarchy plugin add https://github.com/AeonArcHQ/omarchy-logitech-panel --enable
```

## Removing

```sh
omarchy plugin remove com.aeonarc.logitech-panel
```

## How it works

- `openlogi-bridge`: Python helper. `snapshot [--details]` reads OpenLogi's
  JSON API (`openlogi api devices`, `fn-lock`, `easy-switch`) and the
  `openlogi backlight` command, and prints one bounded JSON object.
  `set <device> fn-lock|backlight <value>` accepts only a fixed vocabulary
  and refuses devices that are not online.
- `Model.js`: what the bar, the tooltip, the panel and the warnings show.
- `Service.qml`: polls the bridge (every minute with the panel closed, every
  4 s with it open) and sends changes one at a time.
  `LogitechPanel.qml`: bar entry and panel.
- The plugin never speaks HID++ itself; see
  [docs/adr/0001](docs/adr/0001-openlogi-as-the-engine.md).

## Development

```sh
git config core.hooksPath .githooks   # once per clone: enables the pre-commit hook
tests/check.sh                        # i18n, unittest, qmltestrunner, plugin validate
```

After changing QML, run `omarchy restart shell`; hot reload does not replace
a panel already loaded. QML errors show up in
`journalctl --user | grep LogitechPanel.qml`.

## License

MIT.
