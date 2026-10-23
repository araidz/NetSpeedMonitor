import Foundation
import SystemConfiguration

/// One network-throughput reading: live rates in bytes/sec plus the raw byte
/// deltas since the previous sample (used to accumulate session totals).
struct NetReading: Sendable {
    var downBytesPerSec: Double = 0
    var upBytesPerSec: Double = 0
    var deltaDownBytes: Int64 = 0
    var deltaUpBytes: Int64 = 0
    var generation: UInt = 0
    /// The interface that was sampled; nil when offline.
    var interface: String?
}

/// Off-main network sampler. `reading()` is serialized by an internal lock, so
/// the shared C/Obj-C sampling handles are only ever touched by one thread at a
/// time — which is what makes the `@unchecked Sendable` conformance sound.
final class NetSampler: @unchecked Sendable {
    private let lock = NSLock()
    private let receiver = NetTrafficStatReceiver()
    private let store = SCDynamicStoreCreate(nil, "NetSpeedMonitor" as CFString, nil, nil)
    private var generation: UInt = 0

    /// Takes one traffic sample for `pinned`, or for the primary interface when
    /// nil. Returns a zeroed reading when offline / the interface is absent.
    func reading(interface pinned: String?) -> NetReading {
        lock.lock()
        defer { lock.unlock() }

        guard let iface = pinned ?? queryPrimaryInterface() else { return NetReading(generation: generation) }

        var down = 0.0, up = 0.0
        var deltaDown: Int64 = 0, deltaUp: Int64 = 0
        guard receiver.getStatForInterface(iface,
                                           downBytesPerSec: &down, upBytesPerSec: &up,
                                           deltaDownBytes: &deltaDown, deltaUpBytes: &deltaUp) else {
            return NetReading(generation: generation, interface: iface)
        }

        return NetReading(downBytesPerSec: down, upBytesPerSec: up,
                          deltaDownBytes: deltaDown, deltaUpBytes: deltaUp,
                          generation: generation, interface: iface)
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
