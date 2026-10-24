# NetSpeedMonitor (personal fork)

A minimal macOS menu bar app showing live upload/download speed. Personal fork
of [elegracer/NetSpeedMonitor](https://github.com/elegracer/NetSpeedMonitor);
see the README for what differs from upstream.

## What's new in 1.10 (2026-10-24)

- The menu bar readout no longer wiggles as the numbers change: the item is
  drawn at a fixed width, so the ↑/↓ arrows stay put and only the digits move.

## What's new in 1.9 (2026-10-24)

- K rates read as whole numbers: `120K`, `512K` instead of `120.5K`. Below ten
  the decimals stay (`9.50K`), so slow rates don't collapse to `0`.

## What's new in 1.8 (2026-10-24)

- The throughput graph's caption shows the peak upload and peak download
  separately — `last 2 min · Peak ↑ 0.33 MB/s · ↓ 1.23 MB/s` — each in the
  colour of its line, instead of one figure for whichever direction was higher.
- Changing the update interval no longer blanks the graph while it warms up:
  samples are kept and placed by their timestamp, so the curve continues
  through the switch.
- Clearer Units switch: "Show Slow Speeds in K" is now "Show K Below 1 M".

## What's new in 1.7 (2026-10-23)

- Session totals now survive quitting, relaunching and updating, until you
  press Reset Session Totals.
- Units menu: MB/s or Mbps, plus an option to show slow speeds in K.
- Throughput graph at the top of the menu.
- Top Apps submenu showing the busiest processes (via `nettop`).
- Interface picker: follow the primary interface or pin one.
- Speed test failures are shown in the menu instead of silently ignored.
- Update interval changes apply immediately; the readout redraws instantly on
  light/dark switches; sampling pauses while the displays sleep.

## What's new in 1.5 (2026-08-03)

- Lower idle CPU and energy use through reused menu-bar rendering and
  coalescible sampling.
- More responsive UI with traffic sampling off the main thread.
- Correct session totals across resets, interface changes or disconnects, and
  sampling failures.
- Support for IPv6-only primary interfaces.

## What's new in 1.4

- New app icon — a distinct up/down transfer glyph on a graphite squircle,
  replacing the inherited speedometer artwork.

## What's new in 1.3

- One-click speed test using the built-in macOS `networkQuality` tool (~15 s):
  download / upload (MB/s) and responsiveness (RPM), shown in the menu. The
  readout blinks in your accent colour when the test finishes.
- This build is unsandboxed so it can launch `networkQuality`.

## Also in this build

- Always MB/s, bigger monospaced-digit readout, arrows on the right.
- Monochrome per-line shading by speed band.
- Selectable refresh interval (0.5 / 1 / 2 / 5 s).
- Session totals (received / sent) with a reset, plus the version, in the menu.
- 64-bit interface counters (`NET_RT_IFLIST2` / `if_data64`) — no 4 GB wrap.

## Requirements

macOS 14.6 or later. Universal (Apple silicon + Intel).

## Running an unsigned build

The CI artifact is ad-hoc signed, so macOS may quarantine it. Clear it with:

```bash
xattr -rd com.apple.quarantine ./NetSpeedMonitor.app
```
