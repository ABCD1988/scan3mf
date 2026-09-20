import Foundation

/// 纯 Swift 的最小 ZIP 写出器（stored 无压缩模式）
/// 3MF 是 OPC 包（本质是 zip），必须能打包；不依赖任何三方库
enum ZIPWriter {

    struct Entry {
        let name: String
        let data: Data
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            table[i] = c
        }
        return table
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data {
            c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFF_FFFF
    }

    // MARK: - 小端写入辅助

    private static func u16(_ v: UInt16, into d: inout Data) {
        d.append(UInt8(v & 0xFF))
        d.append(UInt8((v >> 8) & 0xFF))
    }

    private static func u32(_ v: UInt32, into d: inout Data) {
        d.append(UInt8(v & 0xFF))
        d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8((v >> 16) & 0xFF))
        d.append(UInt8((v >> 24) & 0xFF))
    }

    // MARK: - 打包

    @discardableResult
    static func write(files: [Entry], to url: URL) -> Bool {
        var out = Data()
        var central = Data()
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let compYear: Int = comps.year ?? 2026
        let compMonth: Int = comps.month ?? 1
        let compDay: Int = comps.day ?? 1
        let compHour: Int = comps.hour ?? 0
        let compMinute: Int = comps.minute ?? 0
        let compSecond: Int = comps.second ?? 0
        let dosYear: Int = max(1980, compYear) - 1980
        let dosTime: UInt16 = UInt16(compHour << 11 | compMinute << 5 | (compSecond / 2))
        let dosDate: UInt16 = UInt16(dosYear << 9 | compMonth << 5 | compDay)

        for entry in files {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(out.count)

            // ---- Local file header ----
            var local = Data()
            u32(0x0403_4B50, into: &local)
            u16(20, into: &local)                 // version needed
            u16(0, into: &local)                  // flags
            u16(0, into: &local)                  // method: stored
            u16(dosTime, into: &local)
            u16(dosDate, into: &local)
            u32(crc, into: &local)
            u32(size, into: &local)
            u32(size, into: &local)
            u16(UInt16(nameData.count), into: &local)
            u16(0, into: &local)                  // extra length
            local.append(nameData)
            local.append(entry.data)
            out.append(local)

            // ---- Central directory record ----
            u32(0x0201_4B50, into: &central)
            u16(20, into: &central)               // version made by
            u16(20, into: &central)               // version needed
            u16(0, into: &central)
            u16(0, into: &central)
            u16(dosTime, into: &central)
            u16(dosDate, into: &central)
            u32(crc, into: &central)
            u32(size, into: &central)
            u32(size, into: &central)
            u16(UInt16(nameData.count), into: &central)
            u16(0, into: &central)
            u16(0, into: &central)
            u16(0, into: &central)
            u16(0, into: &central)
            u32(0, into: &central)
            u32(offset, into: &central)
            central.append(nameData)
        }

        let centralOffset = UInt32(out.count)
        out.append(central)

        // ---- End of central directory ----
        var eocd = Data()
        u32(0x0605_4B50, into: &eocd)
        u16(0, into: &eocd)
        u16(0, into: &eocd)
        u16(UInt16(files.count), into: &eocd)
        u16(UInt16(files.count), into: &eocd)
        u32(UInt32(central.count), into: &eocd)
        u32(centralOffset, into: &eocd)
        u16(0, into: &eocd)
        out.append(eocd)

        do {
            try out.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
