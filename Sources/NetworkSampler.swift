import Foundation
import Darwin
import SystemConfiguration

struct InterfaceCounters: Equatable {
    let name: String
    let down: UInt64
    let up: UInt64
    let isUp: Bool
}

struct NetworkSnapshot: Equatable {
    let timestamp: TimeInterval
    let interfaces: [InterfaceCounters]
    let primaryName: String?
    let primaryDown: UInt64
    let primaryUp: UInt64
}

final class NetworkSampler {
    private var labelCache: [String: String] = [:]
    private var cachedPrimary: (name: String?, fetchedAt: TimeInterval) = (nil, 0)

    func snapshot() -> NetworkSnapshot {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let counters = readCounters()
        let primary = primaryInterface(now: timestamp)
        let primaryCounters = counters.first { $0.name == primary }
        return NetworkSnapshot(
            timestamp: timestamp,
            interfaces: counters,
            primaryName: primary,
            primaryDown: primaryCounters?.down ?? 0,
            primaryUp: primaryCounters?.up ?? 0
        )
    }

    func displayName(for interface: String) -> String {
        if interface.hasPrefix("utun") || interface.hasPrefix("ipsec") || interface.hasPrefix("ppp") {
            return "VPN"
        }
        if let cached = labelCache[interface] {
            return cached
        }
        if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for candidate in all {
                guard let bsdName = SCNetworkInterfaceGetBSDName(candidate) as String?,
                      bsdName == interface,
                      let label = SCNetworkInterfaceGetLocalizedDisplayName(candidate) as String? else {
                    continue
                }
                labelCache[interface] = label
                return label
            }
        }
        let fallback = interface.hasPrefix("en") ? "Ethernet" : interface
        labelCache[interface] = fallback
        return fallback
    }

    private func readCounters() -> [InterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [] }

        var counters: [InterfaceCounters] = []
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr2>.size <= length {
                let header = base.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }
                if header.ifm_type == RTM_IFINFO2,
                   let name = interfaceName(in: base, messageOffset: offset, messageLength: messageLength) {
                    let flags = header.ifm_flags
                    if flags & IFF_LOOPBACK == 0 {
                        counters.append(InterfaceCounters(
                            name: name,
                            down: header.ifm_data.ifi_ibytes,
                            up: header.ifm_data.ifi_obytes,
                            isUp: flags & IFF_UP != 0
                        ))
                    }
                }
                offset += messageLength
            }
        }
        return counters
    }

    private func interfaceName(
        in base: UnsafeRawPointer,
        messageOffset: Int,
        messageLength: Int
    ) -> String? {
        let linkOffset = messageOffset + MemoryLayout<if_msghdr2>.size
        guard linkOffset + MemoryLayout<sockaddr_dl>.size <= messageOffset + messageLength else {
            return nil
        }
        let link = base.loadUnaligned(fromByteOffset: linkOffset, as: sockaddr_dl.self)
        let nameLength = Int(link.sdl_nlen)
        guard nameLength > 0, nameLength <= Int(IFNAMSIZ) - 1,
              linkOffset + 8 + nameLength <= messageOffset + messageLength else {
            return nil
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(nameLength)
        for index in 0..<nameLength {
            bytes.append(base.loadUnaligned(fromByteOffset: linkOffset + 8 + index, as: UInt8.self))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func primaryInterface(now: TimeInterval) -> String? {
        if now - cachedPrimary.fetchedAt < 2 {
            return cachedPrimary.name
        }
        var name: String?
        if let store = SCDynamicStoreCreate(nil, "Flow" as CFString, nil, nil),
           let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            name = value["PrimaryInterface"] as? String
        }
        cachedPrimary = (name, now)
        return name
    }
}
