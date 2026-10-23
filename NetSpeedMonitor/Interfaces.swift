import Foundation
import SystemConfiguration

/// Lists the interfaces the menu offers for pinning.
enum Interfaces {
    /// BSD names of interfaces that are up, not loopback, and have a routable
    /// (non-link-local) address — e.g. `en0` and an active VPN's `utunN`.
    static func active() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var names: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let addr = entry.pointee.ifa_addr else { continue }
            switch Int32(addr.pointee.sa_family) {
            case AF_INET:
                break
            case AF_INET6:
                let bytes = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    $0.pointee.sin6_addr.__u6_addr.__u6_addr8
                }
                if bytes.0 == 0xfe && bytes.1 & 0xc0 == 0x80 { continue } // fe80::/10
            default:
                continue
            }
            let name = String(cString: entry.pointee.ifa_name)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// "Wi-Fi (en0)" for hardware the system knows; bare BSD names otherwise
    /// (VPN tunnels such as `utun4`).
    static func displayNames() -> [String: String] {
        let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        var names: [String: String] = [:]
        for interface in all {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let label = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? else { continue }
            names[bsd] = "\(label) (\(bsd))"
        }
        return names
    }
}
