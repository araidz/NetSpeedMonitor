import Foundation

/// The unit throughput is shown in. Rates are kept in bytes/sec everywhere and
/// converted only by `RateFormat`.
enum RateUnit: String, CaseIterable {
    case megabytes, megabits

    var title: String { self == .megabytes ? "MB/s" : "Mbps" }
}

/// Turns a bytes/sec rate into display text for the chosen unit.
struct RateFormat: Equatable {
    var unit: RateUnit = .megabytes
    /// Show rates below one "M" in K (KB/s or Kbps) instead of e.g. "0.01".
    var autoScale = false

    // Bytes are binary (matching the byte-count session totals); bits are
    // decimal (matching ISP plans and networkQuality).
    private var bytesPerMega: Double { unit == .megabytes ? 1024 * 1024 : 1_000_000 / 8 }
    private var bytesPerKilo: Double { unit == .megabytes ? 1024 : 1_000 / 8 }

    /// Menu-bar figure without a unit: "12.3", or with auto-scale "512K" / "1.23M".
    func compact(_ bytesPerSec: Double) -> String {
        let (value, prefix) = scaled(bytesPerSec)
        return Self.number(value) + (autoScale ? prefix : "")
    }

    /// Full label for menus: "12.3 MB/s", "512 KB/s", "98.4 Mbps".
    func full(_ bytesPerSec: Double) -> String {
        let (value, prefix) = scaled(bytesPerSec)
        return Self.number(value) + " " + prefix + (unit == .megabytes ? "B/s" : "bps")
    }

    private func scaled(_ bytesPerSec: Double) -> (Double, String) {
        if autoScale && bytesPerSec < bytesPerMega { return (bytesPerSec / bytesPerKilo, "K") }
        return (bytesPerSec / bytesPerMega, "M")
    }

    /// Fewer decimals as the value grows, keeping the readout compact.
    static func number(_ value: Double) -> String {
        switch value {
        case 100...: return String(format: "%.0f", value)
        case 10...:  return String(format: "%.1f", value)
        default:     return String(format: "%.2f", value)
        }
    }
}
