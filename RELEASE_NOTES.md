# NetSpeedMonitor (personal fork)

A minimal macOS menu bar app showing live upload/download speed. Personal fork
of [elegracer/NetSpeedMonitor](https://github.com/elegracer/NetSpeedMonitor);
see the README for what differs from upstream.

## This build

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
