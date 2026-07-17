import Foundation

/// One on-demand speed test, measured by macOS's built-in `networkQuality`.
/// Throughput is reported in MB/s to match the live menu-bar readout;
/// responsiveness is Apple's RPM score (higher is better).
struct SpeedTestResult {
    let downloadMBps: Double
    let uploadMBps: Double
    let responsiveness: Double
}

enum SpeedTest {
    private static let toolPath = "/usr/bin/networkQuality"

    // networkQuality reports throughput in bits/sec. Convert to binary MB/s,
    // the same unit (1024*1024 bytes) the live readout uses.
    private static let bitsPerMB = 8.0 * 1024.0 * 1024.0

    /// The subset of `networkQuality -c` JSON we care about.
    private struct Raw: Decodable {
        let dl_throughput: Double
        let ul_throughput: Double
        let responsiveness: Double
    }

    enum Failure: Error { case nonZeroExit(Int32), noData }

    /// Runs one test (~15s, capped in `launch`) and returns the parsed result.
    /// Non-isolated, so the blocking process wait runs off the main actor.
    // ponytail: blocks one cooperative-pool thread for the test's duration; fine
    // for a single user-initiated test. Revisit only if made concurrent/scheduled.
    static func run() async throws -> SpeedTestResult {
        try parse(try launch())
    }

    /// Pure decode + unit conversion, split from `launch` so it can be unit-checked
    /// without spending seconds on a live test.
    static func parse(_ data: Data) throws -> SpeedTestResult {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        return SpeedTestResult(
            downloadMBps: raw.dl_throughput / bitsPerMB,
            uploadMBps: raw.ul_throughput / bitsPerMB,
            responsiveness: raw.responsiveness
        )
    }

    private static func launch() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        // -M caps runtime. The uncapped test runs ~25s; 15s trades a little
        // accuracy (throughput reads slightly low, TCP needs time to ramp) for
        // a faster result. Raise it toward 25 if you want more accurate numbers.
        process.arguments = ["-c", "-M", "15"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.nonZeroExit(process.terminationStatus)
        }
        guard !data.isEmpty else { throw Failure.noData }
        return data
    }
}
