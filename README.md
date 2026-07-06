# NetSpeedMonitor

A minimal macOS menu bar app that shows your live upload/download speed.

> **Fork notice**
> This is a personal fork of [**elegracer/NetSpeedMonitor**](https://github.com/elegracer/NetSpeedMonitor),
> customized to my own taste. All credit for the original app and its network
> sampling core goes to the upstream author. Licensed under MIT (see `LICENSE`).

It reads per-interface byte counters via `sysctl` (a small C++/Objective-C++
core) and renders the speeds directly into the menu bar.

## What this fork changes

Compared to upstream, this version:

- **Always shows MB/s** — no automatic unit switching between B/KB/MB/GB.
- **Selectable refresh interval** — pick 0.5s / 1s / 2s / 5s from the menu.
  Per-second rates are time-normalized, so the number stays correct at any interval.
- **Bigger, bolder, monospaced-digit readout** that's easier to read at a glance.
- **Monochrome speed shading** — each line's opacity reflects its speed band, so
  you can tell the throughput range without reading the number:

  | Band     | Speed         | Shade            |
  | -------- | ------------- | ---------------- |
  | Fast     | ≥ 1 MB/s      | full strength    |
  | Moderate | 0.1 – 1 MB/s  | 70% opacity      |
  | Slow     | 0.01 – 0.1    | 55% opacity      |
  | Idle     | < 0.01 MB/s   | 40% opacity      |

- **Arrows on the right** of the figures (`12.34 ↑` / `1.23 ↓`), with tightened
  line and edge spacing.
- **Compact menu** — clicking the readout shows session totals (with a reset),
  the refresh interval, **Launch at Login**, the version, and **Quit**.
- **Modernized internals** — the state layer uses Swift's `@Observable` macro and
  `async`/`await` instead of Combine + `Timer`.
- **64-bit byte counters** — samples via `NET_RT_IFLIST2` / `if_data64`, so the
  counters never wrap (no 4 GB roll-over math).

## Features

1. Live upload/download speed in the menu bar (MB/s).
2. Selectable refresh interval (0.5–5 s).
3. Session totals (received / sent) with a reset.
4. Launch at login.
5. Quit.

## Requirements

- macOS 14.6 or later.
- Built with SwiftUI; the UI lives entirely in the menu bar (no Dock icon).

## Building

Open `NetSpeedMonitor.xcodeproj` in Xcode and run the `NetSpeedMonitor` scheme.

## License

MIT — inherited from the upstream project. See [`LICENSE`](./LICENSE).
