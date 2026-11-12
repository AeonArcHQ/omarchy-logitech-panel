# Logitech Panel

An Omarchy bar widget that shows and changes the state of Logitech keyboards and mice through OpenLogi.

## Language

**Device**:
A Logitech keyboard or mouse that OpenLogi lists, whether online or not.
_Avoid_: Peripheral, gadget, hardware

**Offline Device**:
A Device OpenLogi lists but cannot reach right now, for example a keyboard that is asleep or switched to another Channel.
_Avoid_: Disconnected, missing

**Capability**:
A feature a Device announces it supports, such as backlight, Fn lock or Easy-Switch. The panel offers a control only for the Capabilities a Device announces.
_Avoid_: Feature, support flag

**Agent**:
OpenLogi's background service, the one program that owns the Devices and answers the panel's requests.
_Avoid_: Daemon, server, backend

**Blocker**:
A condition outside the plugin that keeps it from reaching the Devices: OpenLogi not installed, the Agent not running, or another program (such as Solaar) holding the Device.
_Avoid_: Error, failure

**Channel**:
One of a Device's Easy-Switch host slots, numbered from 1. A Channel is either paired with a host or empty.
_Avoid_: Slot, host, profile

**Current Channel**:
The Channel the Device is talking to right now. Switching away from it moves the Device to another host.

**Bar Battery**:
The battery the bar icon shows: the lowest charge among the online Devices.
_Avoid_: Main battery

**Low Battery Warning**:
A desktop notification sent once per discharge when a Device falls to 15%, and again at 5%.
