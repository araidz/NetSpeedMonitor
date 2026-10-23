import Foundation

/// Per-process throughput over one second, measured by macOS's built-in `nettop`.
enum AppTraffic {
    struct Row: Equatable {
        let name: String
        let pid: pid_t
        let downBytes: Int64
        let upBytes: Int64
    }

    /// Samples every process's non-loopback traffic. Takes about one second,
    /// so it only runs when the Top Apps submenu is opened.
    static func sample() async throws -> [Row] {
        parse(try Tool.run("/usr/bin/nettop", [
            "-P", "-L", "2", "-s", "1", "-d", "-x", "-n",
            "-t", "external", "-J", "bytes_in,bytes_out",
        ]))
    }

    /// nettop prints one CSV block per sample, each led by a header line that
    /// starts with ",". In delta mode only the last block is a one-second delta.
    /// Rows look like `com.apple.Safar.1438,5156,5657,` (name truncated by nettop).
    static func parse(_ data: Data) -> [Row] {
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
        guard let header = lines.lastIndex(where: { $0.hasPrefix(",") }) else { return [] }
        return lines[(header + 1)...].compactMap { line in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3,
                  let dot = fields[0].lastIndex(of: "."),
                  let pid = pid_t(fields[0][fields[0].index(after: dot)...]),
                  let down = Int64(fields[1]), let up = Int64(fields[2]) else { return nil }
            return Row(name: String(fields[0][..<dot]), pid: pid, downBytes: down, upBytes: up)
        }
    }
}
