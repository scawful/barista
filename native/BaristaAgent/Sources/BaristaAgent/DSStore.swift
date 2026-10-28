import Foundation

/// Finder's hidden per-folder `.DS_Store`, read only: a buddy-allocated file
/// holding a B-tree of records, each a file name, a four-letter code, and a
/// typed value. The folder's own view settings are the records named `.`.
/// Barista never writes it; Finder owns the format.
enum DSStore {
  enum Value: Equatable {
    case long(UInt32)
    case bool(Bool)
    case type(String)
    case blob(Data)
    case string(String)
    case date(UInt64)
  }

  /// The records named `name` (the folder itself by default), by code.
  static func records(in data: Data, named name: String = ".") -> [String: Value]? {
    let reader = Reader(data: data)
    guard reader.u32(at: 0) == 1, reader.fourCC(at: 4) == "Bud1",
          let rootOffset = reader.u32(at: 8) else { return nil }
    // Offsets count from byte 4, after the leading 1.
    let root = Int(rootOffset) + 4
    guard let count = reader.u32(at: root) else { return nil }
    var addresses: [UInt32] = []
    for index in 0..<Int(min(count, 4096)) {
      guard let address = reader.u32(at: root + 8 + index * 4) else { return nil }
      addresses.append(address)
    }
    // The address table is padded to a multiple of 256 entries.
    var cursor = root + 8 + ((Int(count) + 255) / 256) * 256 * 4
    guard let entries = reader.u32(at: cursor) else { return nil }
    cursor += 4
    var directory: [String: UInt32] = [:]
    for _ in 0..<min(entries, 64) {
      guard let length = reader.u8(at: cursor), let key = reader.ascii(at: cursor + 1, length: Int(length)),
            let block = reader.u32(at: cursor + 1 + Int(length)) else { return nil }
      directory[key] = block
      cursor += 1 + Int(length) + 4
    }
    func blockStart(_ number: UInt32) -> Int? {
      guard Int(number) < addresses.count else { return nil }
      return Int(addresses[Int(number)] & ~0x1F) + 4
    }
    guard let dsdb = directory["DSDB"].flatMap(blockStart), let rootNode = reader.u32(at: dsdb) else { return nil }
    var found: [String: Value] = [:]
    var visited = 0
    // Real trees are a few levels deep; a node naming itself must not
    // recurse until a background thread's small stack runs out.
    func walk(_ node: UInt32, depth: Int) -> Bool {
      visited += 1
      guard depth < 32, visited < 10_000, var at = blockStart(node), let rightmost = reader.u32(at: at),
            let count = reader.u32(at: at + 4) else { return false }
      at += 8
      for _ in 0..<min(count, 100_000) {
        if rightmost != 0 {
          guard let child = reader.u32(at: at), walk(child, depth: depth + 1) else { return false }
          at += 4
        }
        guard let (record, code, value, next) = reader.record(at: at) else { return false }
        if record == name, let value { found[code] = value }
        at = next
      }
      return rightmost == 0 || walk(rightmost, depth: depth + 1)
    }
    return walk(rootNode, depth: 0) ? found : nil
  }

  /// A blob that holds a binary property list (`lsvp`, `icvp`, `bwsp`).
  static func plist(_ value: Value?) -> [String: Any]? {
    guard case .blob(let data) = value else { return nil }
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
  }

  private struct Reader {
    let data: Data

    func u8(at offset: Int) -> UInt8? {
      offset >= 0 && offset < data.count ? data[data.startIndex + offset] : nil
    }

    func u32(at offset: Int) -> UInt32? {
      guard offset >= 0, offset + 4 <= data.count else { return nil }
      return data[data.startIndex + offset..<data.startIndex + offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    func u64(at offset: Int) -> UInt64? {
      guard let high = u32(at: offset), let low = u32(at: offset + 4) else { return nil }
      return UInt64(high) << 32 | UInt64(low)
    }

    func bytes(at offset: Int, length: Int) -> Data? {
      guard offset >= 0, length >= 0, offset + length <= data.count else { return nil }
      return data[data.startIndex + offset..<data.startIndex + offset + length]
    }

    func ascii(at offset: Int, length: Int) -> String? {
      bytes(at: offset, length: length).flatMap { String(data: $0, encoding: .macOSRoman) }
    }

    func fourCC(at offset: Int) -> String? { ascii(at: offset, length: 4) }

    func utf16(at offset: Int, units: Int) -> String? {
      bytes(at: offset, length: units * 2).flatMap { String(data: $0, encoding: .utf16BigEndian) }
    }

    /// A record and where the next one starts; an unknown type ends the walk,
    /// since its length can't be known.
    func record(at offset: Int) -> (name: String, code: String, value: Value?, next: Int)? {
      guard let units = u32(at: offset), units < 1024, let name = utf16(at: offset + 4, units: Int(units)) else { return nil }
      var at = offset + 4 + Int(units) * 2
      guard let code = fourCC(at: at), let type = fourCC(at: at + 4) else { return nil }
      at += 8
      switch type {
      case "long", "shor":
        guard let value = u32(at: at) else { return nil }
        return (name, code, .long(value), at + 4)
      case "bool":
        guard let value = u8(at: at) else { return nil }
        return (name, code, .bool(value != 0), at + 1)
      case "type":
        guard let value = fourCC(at: at) else { return nil }
        return (name, code, .type(value), at + 4)
      case "blob", "book":
        guard let length = u32(at: at), let value = bytes(at: at + 4, length: Int(length)) else { return nil }
        return (name, code, .blob(Data(value)), at + 4 + Int(length))
      case "ustr":
        guard let length = u32(at: at), let value = utf16(at: at + 4, units: Int(length)) else { return nil }
        return (name, code, .string(value), at + 4 + Int(length) * 2)
      case "comp", "dutc":
        guard let value = u64(at: at) else { return nil }
        return (name, code, .date(value), at + 8)
      default:
        return nil
      }
    }
  }
}
