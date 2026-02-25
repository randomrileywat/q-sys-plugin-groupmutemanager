# Group Mute Manager — Q-SYS Plugin

A Q-SYS plugin for managing group mute buttons with per-zone control. Supports up to **16 groups** with up to **32 zone members** each.

## Features

- **Group & Zone Mute Control** — Toggle mute for an entire group or individual zones within a group.
- **All Mute** — A master mute button that respects per-group opt-in/opt-out settings.
- **Amp Fault Monitoring** — Accepts amplifier status inputs at both the group and zone level. Faulted buttons flash with a configurable color overlay.
- **Configurable Flash Rate** — Adjustable fault indicator flash rate (knob, 1–100).
- **Custom Colors** — Set colors for muted, unmuted, mixed, and amp fault states via text inputs with live LED previews.
- **Pin I/O** — All mute states, amp status inputs, and zone labels are exposed as user pins for external control and monitoring.
- **Mute State Encoding** — Pin values use a numeric encoding: `0` = unmuted, `1` = muted, `2` = mixed, `3`/`4`/`5` = faulted variants. Also accepts `"muted"`, `"unmuted"`, `"true"`, `"false"`.

## Properties

| Property | Type | Range | Default | Description |
|---|---|---|---|---|
| Group Count | Integer | 1–16 | 2 | Number of mute groups |
| Members Per Group | Integer | 1–32 | 4 | Number of zone members per group |

## Pin Reference

### Per Group (× Group Count)

| Pin | Direction | Description |
|---|---|---|
| `Group_Mute_G{n}` | Both | Group mute state (0/1/2, fault-encoded 3/4/5) |
| `GroupAmpStatus_G{n}` | Input | Amp status for the group (`"OK"` or fault string) |
| `GroupAllMuteEnable_G{n}` | Both | Whether this group respects the All Mute button |

### Per Zone (× Group Count × Members Per Group)

| Pin | Direction | Description |
|---|---|---|
| `ZoneMute_{g}_{m}` | Both | Zone mute state (0 or 1) |
| `ZoneAmpStatus_{g}_{m}` | Input | Amp status for the zone |
| `ZoneLabel_{g}_{m}` | Both | Display label for the zone |

### Global

| Pin | Direction | Description |
|---|---|---|
| `All_Mute` | Both | Master mute state (only when Group Count > 1) |
| `AnyFault` | Output | `"1"` if any group/zone has an amp fault, `"0"` otherwise |

## Settings Page

- **Amp Status Flash Rate** — Controls how fast faulted buttons flash (1 = slow, 100 = fast).
- **Color — Muted / Unmuted / Mixed / Amp Fault** — Custom color strings (e.g. `"Red"`, `"#FF8800"`). Defaults: Red, Green, Yellow, Orange.
- **Disable Status Flash** — Suppresses the flash overlay while retaining fault-encoded pin outputs.
- **Respect All Mute** — Per-group toggles controlling whether the All Mute button affects each group.

## Changelog

| Version | Date | Notes |
|---|---|---|
| 260224.1 | 2026-02-24 | Fixed feedback loop in UpdateFaultOutputs writing back to GroupAmpStatus input pin |
| 260223.1 | 2026-02-23 | Flash timer now fault-gated; pcall guard on updatingState; GetControls scoped to props; fixed nil `m` in groupState handler |
| 260117.1 | 2026-01-17 | Fixed zone mute buttons not always updating mute state |
| 260112.1 | 2026-01-12 | Fixed zone mute desync on group mute pin change |
| 260110.7 | 2026-01-10 | Reduced clock sync drift tolerance |
| 260110.6 | 2026-01-10 | Flash timing uses shared wall-clock time |
| 260110.5 | 2026-01-10 | Fixed race condition on zone mute pin input |
| 260110.3 | 2026-01-10 | Zone mute buttons accept faulted state codes (3/4) |

## License

MIT — see [LICENSE](LICENSE) for details.
