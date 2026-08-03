import Foundation
import SystemConfiguration

/// One network-throughput reading: live rates in MB/s plus the raw byte deltas
/// since the previous sample (used to accumulate session totals).
struct NetReading: Sendable {
    var downloadMBps: Double = 0
    var uploadMBps: Double = 0
    var deltaDownBytes: Int64 = 0
    var deltaUpBytes: Int64 = 0
    var generation: UInt = 0
}

/// Off-main network sampler. `reading()` is serialized by an internal lock, so
/// the shared C/Obj-C sampling handles are only ever touched by one thread at a
/// time — which is what makes the `@unchecked Sendable` conformance sound.
final class NetSampler: @unchecked Sendable {
    private static let bytesPerMB = 1024.0 * 1024.0

    private let lock = NSLock()
    private let receiver = NetTrafficStatReceiver()
    private let store = SCDynamicStoreCreate(nil, "NetSpeedMonitor" as CFString, nil, nil)
    private var generation: UInt = 0

    /// Takes one traffic sample for the primary interface. Returns a zeroed
    /// reading when offline (no primary interface / interface not found).
    func reading() -> NetReading {
        lock.lock()
        defer { lock.unlock() }

        guard let iface = queryPrimaryInterface() else { return NetReading(generation: generation) }

        var down = 0.0, up = 0.0
        var deltaDown: Int64 = 0, deltaUp: Int64 = 0
        guard receiver.getStatForInterface(iface,
                                           downBytesPerSec: &down, upBytesPerSec: &up,
                                           deltaDownBytes: &deltaDown, deltaUpBytes: &deltaUp) else {
            return NetReading(generation: generation)
        }

        return NetReading(downloadMBps: down / Self.bytesPerMB,
                          uploadMBps: up / Self.bytesPerMB,
                          deltaDownBytes: deltaDown, deltaUpBytes: deltaUp,
                          generation: generation)
    }

    func resetBaseline() -> UInt {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        receiver.resetBaseline()
        return generation
    }

    /// Prefer the IPv4 primary; fall back to IPv6 so an IPv6-only link still reads.
    private func queryPrimaryInterface() -> String? {
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            if let dict = SCDynamicStoreCopyValue(store, key as CFString),
               let iface = dict.value(forKey: "PrimaryInterface") as? String {
                return iface
            }
        }
        return nil
    }
}
