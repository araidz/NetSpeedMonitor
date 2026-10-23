import Foundation

/// One on-demand speed test, measured by macOS's built-in `networkQuality`.
/// Throughput is in bytes/sec (shown in the user's chosen unit);
/// responsiveness is Apple's RPM score (higher is better).
struct SpeedTestResult {
    let downloadBytesPerSec: Double
    let uploadBytesPerSec: Double
    let responsiveness: Double
}

enum SpeedTest {
    /// The subset of `networkQuality -c` JSON we care about.
    private struct Raw: Decodable {
        let dl_throughput: Double
        let ul_throughput: Double
        let responsiveness: Double
    }

    enum Failure: LocalizedError {
        case noData
        var errorDescription: String? { "networkQuality returned no results" }
    }

    /// Runs one test (~15s, capped below) and returns the parsed result.
    /// Non-isolated, so the blocking process wait runs off the main actor.
    // ponytail: blocks one cooperative-pool thread for the test's duration; fine
    // for a single user-initiated test. Revisit only if made concurrent/scheduled.
    static func run() async throws -> SpeedTestResult {
        // -M caps runtime. The uncapped test runs ~25s; 15s trades a little
        // accuracy (throughput reads slightly low, TCP needs time to ramp) for
        // a faster result. Raise it toward 25 if you want more accurate numbers.
        let data = try Tool.run("/usr/bin/networkQuality", ["-c", "-M", "15"])
        guard !data.isEmpty else { throw Failure.noData }
        return try parse(data)
    }

    /// Pure decode + unit conversion, split from `run` so it can be unit-tested
    /// without spending seconds on a live test.
    static func parse(_ data: Data) throws -> SpeedTestResult {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        // networkQuality reports bits/sec.
        return SpeedTestResult(
            downloadBytesPerSec: raw.dl_throughput / 8,
            uploadBytesPerSec: raw.ul_throughput / 8,
            responsiveness: raw.responsiveness
        )
    }
}
