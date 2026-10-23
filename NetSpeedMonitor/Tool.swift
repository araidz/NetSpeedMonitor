import Foundation

/// Runs a bundled macOS command-line tool to completion and returns its stdout.
enum Tool {
    /// A non-zero exit; the message is the tool's own stderr when it wrote one.
    struct Failure: LocalizedError {
        let tool: String
        let status: Int32
        let stderr: String

        var errorDescription: String? {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(tool) exited with status \(status)" : detail
        }
    }

    // ponytail: stdout is drained before stderr, so a tool writing >64 KB to
    // stderr would block. networkQuality and nettop write little there; read
    // both concurrently if a chattier tool is ever added.
    static func run(_ path: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(tool: process.executableURL?.lastPathComponent ?? path,
                          status: process.terminationStatus,
                          stderr: String(decoding: errData, as: UTF8.self))
        }
        return data
    }
}
