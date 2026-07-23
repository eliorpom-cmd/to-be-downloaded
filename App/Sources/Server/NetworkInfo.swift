import Foundation

enum NetworkInfo {

    /// Adresse IPv4 locale (LAN) de la machine, ex. "192.168.1.42".
    /// Privilégie les interfaces Wi-Fi/Ethernet (en0, en1…).
    static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(name: String, ip: String)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            // Interface active et non-loopback.
            guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0 else { continue }
            guard let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                     &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            let ip = String(cString: host)
            candidates.append((name, ip))
        }

        // Préfère en0/en1… (Wi-Fi/Ethernet) puis n'importe quelle IPv4.
        address = candidates.first(where: { $0.name.hasPrefix("en") })?.ip
            ?? candidates.first?.ip
        return address
    }
}
