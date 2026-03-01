# Group Mute Manager — Q-SYS Plugin Suite

A pair of Q-SYS plugins for managing group mute buttons with per-zone control and optional centralized master control.

---

## Group Mute Manager

Manages up to **16 groups** with up to **32 zone members** each. Provides per-zone and per-group mute control, amp fault monitoring with synchronized flash indicators, and full pin I/O.

### Features

- **Group & Zone Mute Control** — Toggle mute for an entire group or individual zones within a group.
- **All Mute** — A master mute button that respects per-group opt-in/opt-out settings.
- **Amp Fault Monitoring** — Accepts amplifier status inputs at both the group and zone level. Faulted buttons flash with a configurable color overlay.
- **Configurable Flash Rate** — Adjustable fault indicator flash rate (knob, 1–100).
- **Clock to Master** — Optional synchronization of fault flash timing to a Group Mute Master Controller instance via its `Flash_Clock` output. Falls back to local `os.time()` wall-clock when master is unavailable; auto-reconnects every 5 seconds.
- **Custom Colors** — Set colors for muted, unmuted, mixed, and amp fault states via text inputs with live LED previews.
- **Pin I/O** — All mute states, amp status inputs, and zone labels are exposed as user pins for external control and monitoring.
- **Mute State Encoding** — Pin values use a numeric encoding: `0` = unmuted, `1` = muted, `2` = mixed, `3`/`4`/`5` = faulted variants. Also accepts `"muted"`, `"unmuted"`, `"true"`, `"false"`.

### Properties

| Property | Type | Range | Default | Description |
|---|---|---|---|---|
| Group Count | Integer | 1–16 | 2 | Number of mute groups |
| Members Per Group | Integer | 1–32 | 4 | Number of zone members per group |

### Pin Reference

#### Per Group (× Group Count)

| Pin | Direction | Description |
|---|---|---|
| `Group_Mute_G{n}` | Both | Group mute state (0/1/2, fault-encoded 3/4/5) |
| `GroupAmpStatus_G{n}` | Input | Amp status for the group (`"OK"` or fault string) |
| `GroupAllMuteEnable_G{n}` | Both | Whether this group respects the All Mute button |

#### Per Zone (× Group Count × Members Per Group)

| Pin | Direction | Description |
|---|---|---|
| `ZoneMute_{g}_{m}` | Both | Zone mute state (0 or 1) |
| `ZoneAmpStatus_{g}_{m}` | Input | Amp status for the zone |
| `ZoneLabel_{g}_{m}` | Both | Display label for the zone |

#### Global

| Pin | Direction | Description |
|---|---|---|
| `All_Mute` | Both | Master mute state (only when Group Count > 1) |
| `AnyFault` | Output | `"1"` if any group/zone has an amp fault, `"0"` otherwise |

### Settings Page

- **Amp Status Flash Rate** — Controls how fast faulted buttons flash (1 = slow, 100 = fast).
- **Color — Muted / Unmuted / Mixed / Amp Fault** — Custom color strings (e.g. `"Red"`, `"#FF8800"`). Defaults: Red, Green, Yellow, Orange.
- **Disable Status Flash** — Suppresses the flash overlay while retaining fault-encoded pin outputs.
- **Clock to Master** — Toggle to sync fault flash to a Master Controller's `Flash_Clock` output.
- **Master Code Name** — Q-SYS code name of the Master Controller instance (default: `GroupMuteMasterController`).
- **Respect All Mute** — Per-group toggles controlling whether the All Mute button affects each group.

### Changelog

| Version | Date | Notes |
|---|---|---|
| 260301.1 | 2026-03-01 | Added "Clock to Master" flash sync (EventHandler-driven, auto-reconnect, local fallback); `updatingAllMute` guard flag fix for All_Mute EventHandler |
| 260228.1 | 2026-02-28 | Updated default Muted and Mixed colors to 80 opacity hex format |
| 260227.1 | 2026-02-27 | Restored GetControls() to always create max controls |
| 260224.1 | 2026-02-24 | Fixed feedback loop in UpdateFaultOutputs writing back to GroupAmpStatus input pin |
| 260223.1 | 2026-02-23 | Flash timer now fault-gated; pcall guard on updatingState; fixed nil variable in groupState handler |
| 260117.1 | 2026-01-17 | Fixed zone mute buttons not always updating mute state |
| 260112.1 | 2026-01-12 | Fixed zone mute desync on group mute pin change |
| 260110.7 | 2026-01-10 | Reduced clock sync drift tolerance |
| 260110.6 | 2026-01-10 | Flash timing uses shared wall-clock time |
| 260110.5 | 2026-01-10 | Fixed race condition on zone mute pin input |
| 260110.3 | 2026-01-10 | Zone mute buttons accept faulted state codes (3/4) |

---

## Group Mute Master Controller

Companion plugin that provides centralized "All Mute" control over multiple Group Mute Manager instances and broadcasts a master flash clock for synchronized fault indicators.

### Features

- **Per-Instance Mute Control** — Connect up to **32** Group Mute Manager instances by Q-SYS code name. Each gets a mute button with live status and connection LED.
- **Global Mute All** — A single button to mute/unmute every connected instance at once.
- **Tri-State Handling** — Button handlers use string state logic (`"0"` / `"1"` / `"2"`) rather than Boolean toggle, correctly handling muted / unmuted / mixed states.
- **Flash Clock Broadcast** — Outputs a `Flash_Clock` signal (`"1"` / `"0"`) that Group Mute Manager instances can subscribe to for perfectly synchronized fault flash timing.
- **Auto-Reconnect** — Automatically reconnects to instances whose code names become available.
- **Script Access Detection** — Shows "No Script Access" when target component controls aren't accessible (dot-notation: `All.Mute`, `Group.Mute.1`).
- **Custom Colors** — Configurable colors for muted, unmuted, mixed, and disconnected states with live previews.

### Properties

| Property | Type | Range | Default | Description |
|---|---|---|---|---|
| Instance Count | Integer | 1–32 | 2 | Number of Group Mute Manager instances to control |

### Pin Reference

| Pin | Direction | Description |
|---|---|---|
| `Global_Mute` | Both | Global mute state text (`"0"` / `"1"` / `"2"`) |
| `GlobalMuteSet` | Input | Trigger to mute all instances |
| `GlobalMuteReset` | Input | Trigger to unmute all instances |
| `Flash_Clock` | Output | Flash clock broadcast (`"1"` = on, `"0"` = off) |

### Settings Page

- **Poll Rate (ms)** — How often to read instance states (100–5000 ms, default 500).
- **Auto-Reconnect** — Automatically retry disconnected instances on each poll cycle.
- **Color — Muted / Unmuted / Mixed / Disconnected** — Custom color strings with live LED previews.
- **Flash Rate** — Controls the flash clock speed (1 = slow, 100 = fast). Matches the Group Mute Manager's rate knob scale.

### Changelog

| Version | Date | Notes |
|---|---|---|
| 260301.2 | 2026-03-01 | Added flash clock broadcast (`Flash_Clock` output, `FlashRate` knob, `FlashClock_Preview` LED) |
| 260301.1 | 2026-03-01 | Initial release: per-instance mute, global mute, tri-state logic, auto-reconnect, color customization |

---

## License

MIT — see [LICENSE](LICENSE) for details.
