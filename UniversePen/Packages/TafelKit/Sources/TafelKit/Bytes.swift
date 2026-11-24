import Foundation

/// Little-endian binary writer used for the high-frequency wire messages.
public struct ByteWriter {
    public private(set) var data = Data()

    public init(capacity: Int = 64) { data.reserveCapacity(capacity) }

    public mutating func u8(_ v: UInt8) { data.append(v) }
    public mutating func u16(_ v: UInt16) { append(v.littleEndian) }
    public mutating func u32(_ v: UInt32) { append(v.littleEndian) }
    public mutating func f32(_ v: Float) { u32(v.bitPattern) }
    public mutating func f64(_ v: Double) { append(v.bitPattern.littleEndian) }
    public mutating func bool(_ v: Bool) { u8(v ? 1 : 0) }

    /// Length-prefixed (u32) blob.
    public mutating func blob(_ d: Data) {
        u32(UInt32(d.count))
        data.append(d)
    }

    /// Length-prefixed (u16) UTF-8 string.
    public mutating func string(_ s: String) {
        let d = Data(s.utf8)
        u16(UInt16(min(d.count, Int(UInt16.max))))
        data.append(d.prefix(Int(UInt16.max)))
    }

    /// Raw bytes with no length prefix (must be last field).
    public mutating func rest(_ d: Data) { data.append(d) }

    private mutating func append<T: FixedWidthInteger>(_ v: T) {
        withUnsafeBytes(of: v) { data.append(contentsOf: $0) }
    }
}

public enum WireError: Error, Equatable {
    case truncated
    case unknownValue(String)
    case tooLarge
}

/// Little-endian binary reader, bounds-checked.
public struct ByteReader {
    private let data: Data
    private var offset: Int

    public init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    public var remaining: Int { data.endIndex - offset }

    public mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw WireError.truncated }
        defer { offset += 1 }
        return data[offset]
    }

    public mutating func u16() throws -> UInt16 { UInt16(littleEndian: try fixed()) }
    public mutating func u32() throws -> UInt32 { UInt32(littleEndian: try fixed()) }
    public mutating func f32() throws -> Float { Float(bitPattern: try u32()) }
    public mutating func f64() throws -> Double { Double(bitPattern: UInt64(littleEndian: try fixed())) }
    public mutating func bool() throws -> Bool { try u8() != 0 }

    public mutating func blob() throws -> Data {
        let n = Int(try u32())
        return try bytes(n)
    }

    public mutating func string() throws -> String {
        let n = Int(try u16())
        return String(decoding: try bytes(n), as: UTF8.self)
    }

    public mutating func rest() -> Data {
        defer { offset = data.endIndex }
        return Data(data[offset..<data.endIndex])
    }

    public mutating func bytes(_ n: Int) throws -> Data {
        guard n >= 0, remaining >= n else { throw WireError.truncated }
        defer { offset += n }
        return Data(data[offset..<(offset + n)])
    }

    private mutating func fixed<T: FixedWidthInteger>() throws -> T {
        let size = MemoryLayout<T>.size
        guard remaining >= size else { throw WireError.truncated }
        var v: T = 0
        withUnsafeMutableBytes(of: &v) { buf in
            data.copyBytes(to: buf.bindMemory(to: UInt8.self), from: offset..<(offset + size))
        }
        offset += size
        return v
    }
}
