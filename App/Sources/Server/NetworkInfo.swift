// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

enum NetworkInfo {

    /// Local IPv4 address (LAN) of the machine, e.g. "192.168.1.42".
    /// Prefers Wi-Fi/Ethernet interfaces (en0, en1…).
    static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(name: String, ip: String)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            // Active and non-loopback interface.
            guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0 else { continue }
            guard let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                     &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            // `String(cString:)` over an ARRAY is deprecated in Swift 6 (the
            // pointer overload on the line above is not). getnameinfo leaves a
            // C string in a buffer sized for the longest possible one, so the
            // null terminator is where the address ends.
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                            as: UTF8.self)
            candidates.append((name, ip))
        }

        // Prefer en0/en1… (Wi-Fi/Ethernet) then any IPv4.
        address = candidates.first(where: { $0.name.hasPrefix("en") })?.ip
            ?? candidates.first?.ip
        return address
    }
}
