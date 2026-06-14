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
- **Fixed 1-second refresh** — removed the selectable update intervals.
- **Bigger, bolder, monospaced-digit readout** that's easier to read at a glance.
- **Monochrome speed shading** — each line's opacity reflects its speed band, so
  you can tell the throughput range without reading the number:

  | Band     | Speed         | Shade            |
  | -------- | ------------- | ---------------- |
  | Fast     | ≥ 1 MB/s      | full strength    |
  | Moderate | 0.1 – 1 MB/s  | 70% opacity      |
  | Slow     | 0.01 – 0.1    | 45% opacity      |
  | Idle     | < 0.01 MB/s   | 30% opacity      |

- **Arrows on the right** of the figures (`12.34 ↑` / `1.23 ↓`), with tightened
  line and edge spacing.
- **Trimmed menu** — clicking the readout shows just **Start at Login** and **Quit**.
- **Modernized internals** — the state layer uses Swift's `@Observable` macro and
  `async`/`await` instead of Combine + `Timer`.

## Features

1. Live upload/download speed in the menu bar (MB/s, updated every second).
2. Start at login.
3. Quit.

## Requirements

- macOS 14.6 or later.
- Built with SwiftUI; the UI lives entirely in the menu bar (no Dock icon).

## Building

Open `NetSpeedMonitor.xcodeproj` in Xcode and run the `NetSpeedMonitor` scheme.

## License

MIT — inherited from the upstream project. See [`LICENSE`](./LICENSE).
