# OpenLogi is the engine; the plugin never speaks HID++ itself

The plugin reads and changes Devices only through OpenLogi's JSON automation API (`openlogi api ...`) and its `openlogi backlight` command, both answered by the OpenLogi Agent. In November 2026 OpenLogi was the only actively maintained Linux engine that controls a Bluetooth MX Keys Mini (battery, backlight, Fn lock, Easy-Switch) and offers a stable, versioned JSON interface (`schema_version: 1`); the Solaar-based plugins were unmaintained, and Solaar itself cannot run beside OpenLogi because only one program may own a Device.

## Consequences

- OpenLogi is a hard requirement. The plugin does not install it; when it is missing or the Agent is down, the panel names the Blocker and the command that fixes it.
- Device ids are OpenLogi route ids: opaque, refreshed after every reconnect, and kept on the machine because they may carry hardware identity.
- Bugs in device behaviour (for example AprilNEA/OpenLogi#1723) are reported upstream, not worked around with our own protocol code.
