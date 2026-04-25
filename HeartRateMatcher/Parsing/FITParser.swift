import Foundation

public enum FITParserError: Error {
    case fileTooShort
    case missingMagic
    case truncatedRecord
    case unknownBaseType(UInt8)
    case undefinedLocalMessage(UInt8)
}

/// Minimal FIT (Flexible and Interoperable Data Transfer) decoder. Parses
/// activity files emitted by Garmin / Wahoo / Strava-export and surfaces the
/// per-second `record` messages (global message number 20) we need for the
/// merger. Other message types are skipped over using their declared length.
///
/// Spec reference: Garmin FIT SDK — see `Profile.xlsx`, "FIT Protocol".
public final class FITParser {
    public init() {}

    public func parse(data: Data, filename: String) throws -> Ride {
        guard data.count >= 12 else { throw FITParserError.fileTooShort }
        let headerSize = Int(data[0])
        guard data.count >= headerSize + 2 else { throw FITParserError.fileTooShort }
        let magic = data.subdata(in: 8..<12)
        guard magic == Data(".FIT".utf8) else { throw FITParserError.missingMagic }

        let dataSize = Int(data.readUInt32LE(at: 4))
        let payloadStart = headerSize
        let payloadEnd = min(payloadStart + dataSize, data.count - 2)

        var reader = ByteReader(data: data, offset: payloadStart, end: payloadEnd)
        var definitions: [UInt8: Definition] = [:]
        var samples: [RideSample] = []
        var lastTimestamp: UInt32 = 0
        var fileStartDate: Date?

        while reader.remaining > 0 {
            let header = try reader.readUInt8()

            if header & 0x80 != 0 {
                // Compressed timestamp header — bits 5-6 = local mtype, bits 0-4 = time offset.
                let localType = (header >> 5) & 0x03
                let offset = UInt32(header & 0x1F)
                guard let def = definitions[localType] else {
                    throw FITParserError.undefinedLocalMessage(localType)
                }
                let prev = lastTimestamp
                var ts = (prev & 0xFFFFFFE0) | offset
                if offset < (prev & 0x1F) { ts &+= 0x20 }
                lastTimestamp = ts
                let fields = try readDataFields(definition: def, reader: &reader)
                if def.globalMessageNumber == 20 {
                    if let sample = makeSample(
                        from: fields,
                        explicitTimestamp: ts,
                        fileStart: &fileStartDate
                    ) {
                        samples.append(sample)
                    }
                }
                continue
            }

            let isDefinition = (header & 0x40) != 0
            let hasDevData = (header & 0x20) != 0
            let localType = header & 0x0F

            if isDefinition {
                let def = try readDefinition(reader: &reader, hasDevData: hasDevData)
                definitions[localType] = def
            } else {
                guard let def = definitions[localType] else {
                    throw FITParserError.undefinedLocalMessage(localType)
                }
                let fields = try readDataFields(definition: def, reader: &reader)
                if def.globalMessageNumber == 20 {
                    if let tsRaw = fields[253]?.asUInt32 { lastTimestamp = tsRaw }
                    if let sample = makeSample(
                        from: fields,
                        explicitTimestamp: nil,
                        fileStart: &fileStartDate
                    ) {
                        samples.append(sample)
                    }
                }
            }
        }

        let baseName = (filename as NSString).deletingPathExtension
        return Ride(
            name: baseName,
            sourceFormat: .fit,
            sourceFilename: filename,
            samples: samples
        )
    }

    public func parse(url: URL) throws -> Ride {
        let data = try Data(contentsOf: url)
        return try parse(data: data, filename: url.lastPathComponent)
    }

    // MARK: - Definitions

    private struct FieldDefinition {
        let fieldNumber: UInt8
        let size: Int
        let baseType: UInt8
    }

    private struct Definition {
        let globalMessageNumber: UInt16
        let bigEndian: Bool
        let fields: [FieldDefinition]
        let devFieldTotalSize: Int
    }

    private func readDefinition(reader: inout ByteReader, hasDevData: Bool) throws -> Definition {
        _ = try reader.readUInt8() // reserved
        let arch = try reader.readUInt8()
        let bigEndian = arch == 1
        let globalNum = try reader.readUInt16(bigEndian: bigEndian)
        let numFields = Int(try reader.readUInt8())
        var fields: [FieldDefinition] = []
        fields.reserveCapacity(numFields)
        for _ in 0..<numFields {
            let n = try reader.readUInt8()
            let size = Int(try reader.readUInt8())
            let baseType = try reader.readUInt8()
            fields.append(FieldDefinition(fieldNumber: n, size: size, baseType: baseType))
        }
        var devTotal = 0
        if hasDevData {
            let numDev = Int(try reader.readUInt8())
            for _ in 0..<numDev {
                _ = try reader.readUInt8() // field num
                let size = Int(try reader.readUInt8())
                _ = try reader.readUInt8() // dev data index
                devTotal += size
            }
        }
        return Definition(
            globalMessageNumber: globalNum,
            bigEndian: bigEndian,
            fields: fields,
            devFieldTotalSize: devTotal
        )
    }

    // MARK: - Data fields

    enum FieldValue {
        case uint(UInt64)
        case int(Int64)
        case float(Double)
        case string(String)
        case bytes(Data)

        var asUInt32: UInt32? {
            if case .uint(let v) = self { return UInt32(truncatingIfNeeded: v) }
            return nil
        }
        var asUInt64: UInt64? {
            if case .uint(let v) = self { return v }
            return nil
        }
        var asInt32: Int32? {
            if case .int(let v) = self { return Int32(truncatingIfNeeded: v) }
            return nil
        }
        var asInt8: Int8? {
            if case .int(let v) = self { return Int8(truncatingIfNeeded: v) }
            return nil
        }
        var asDouble: Double? {
            switch self {
            case .float(let v): return v
            case .uint(let v):  return Double(v)
            case .int(let v):   return Double(v)
            default:            return nil
            }
        }
    }

    private func readDataFields(
        definition: Definition,
        reader: inout ByteReader
    ) throws -> [UInt8: FieldValue] {
        var values: [UInt8: FieldValue] = [:]
        for field in definition.fields {
            let raw = try reader.readBytes(count: field.size)
            if let v = decode(raw: raw, baseType: field.baseType, bigEndian: definition.bigEndian) {
                values[field.fieldNumber] = v
            }
        }
        if definition.devFieldTotalSize > 0 {
            _ = try reader.readBytes(count: definition.devFieldTotalSize)
        }
        return values
    }

    private func decode(raw: Data, baseType: UInt8, bigEndian: Bool) -> FieldValue? {
        switch baseType {
        case 0x00, 0x02: // enum, uint8
            let v = raw.first ?? 0xFF
            return v == 0xFF ? nil : .uint(UInt64(v))
        case 0x01: // sint8
            let v = Int8(bitPattern: raw.first ?? 0x7F)
            return v == 0x7F ? nil : .int(Int64(v))
        case 0x83: // sint16
            let v = Int16(bitPattern: raw.readUInt16(at: 0, bigEndian: bigEndian))
            return v == 0x7FFF ? nil : .int(Int64(v))
        case 0x84: // uint16
            let v = raw.readUInt16(at: 0, bigEndian: bigEndian)
            return v == 0xFFFF ? nil : .uint(UInt64(v))
        case 0x85: // sint32
            let v = Int32(bitPattern: raw.readUInt32(at: 0, bigEndian: bigEndian))
            return v == 0x7FFFFFFF ? nil : .int(Int64(v))
        case 0x86: // uint32
            let v = raw.readUInt32(at: 0, bigEndian: bigEndian)
            return v == 0xFFFFFFFF ? nil : .uint(UInt64(v))
        case 0x07: // string
            let trimmed = raw.prefix(while: { $0 != 0 })
            return String(data: Data(trimmed), encoding: .utf8).map(FieldValue.string)
        case 0x88: // float32
            let bits = raw.readUInt32(at: 0, bigEndian: bigEndian)
            let f = Float(bitPattern: bits)
            return f.isNaN ? nil : .float(Double(f))
        case 0x89: // float64
            let bits = raw.readUInt64(at: 0, bigEndian: bigEndian)
            let d = Double(bitPattern: bits)
            return d.isNaN ? nil : .float(d)
        case 0x0A: // uint8z
            let v = raw.first ?? 0
            return v == 0 ? nil : .uint(UInt64(v))
        case 0x8B: // uint16z
            let v = raw.readUInt16(at: 0, bigEndian: bigEndian)
            return v == 0 ? nil : .uint(UInt64(v))
        case 0x8C: // uint32z
            let v = raw.readUInt32(at: 0, bigEndian: bigEndian)
            return v == 0 ? nil : .uint(UInt64(v))
        case 0x0D: // byte
            return .bytes(raw)
        case 0x8E: // sint64
            let v = Int64(bitPattern: raw.readUInt64(at: 0, bigEndian: bigEndian))
            return .int(v)
        case 0x8F: // uint64
            return .uint(raw.readUInt64(at: 0, bigEndian: bigEndian))
        case 0x90: // uint64z
            let v = raw.readUInt64(at: 0, bigEndian: bigEndian)
            return v == 0 ? nil : .uint(v)
        default:
            return nil
        }
    }

    // MARK: - Mapping record fields → RideSample

    /// FIT timestamps are seconds since 1989-12-31T00:00:00Z (UTC).
    private static let fitEpoch = Date(timeIntervalSince1970: 631_065_600)
    private static let semicircleToDegree = 180.0 / 2_147_483_648.0

    private func makeSample(
        from fields: [UInt8: FieldValue],
        explicitTimestamp: UInt32?,
        fileStart: inout Date?
    ) -> RideSample? {
        let tsRaw = explicitTimestamp ?? fields[253]?.asUInt32
        guard let tsRaw else { return nil }
        let timestamp = Self.fitEpoch.addingTimeInterval(TimeInterval(tsRaw))
        if fileStart == nil { fileStart = timestamp }

        var sample = RideSample(timestamp: timestamp)

        if let lat = fields[0]?.asInt32 {
            sample.latitude = Double(lat) * Self.semicircleToDegree
        }
        if let lon = fields[1]?.asInt32 {
            sample.longitude = Double(lon) * Self.semicircleToDegree
        }
        if let enhAlt = fields[78]?.asDouble {
            sample.altitude = enhAlt / 5.0 - 500.0
        } else if let alt = fields[2]?.asDouble {
            sample.altitude = alt / 5.0 - 500.0
        }
        if let hr = fields[3]?.asUInt64 { sample.heartRate = Int(hr) }
        if let cad = fields[4]?.asUInt64 { sample.cadence = Int(cad) }
        if let dist = fields[5]?.asDouble { sample.distance = dist / 100.0 }
        if let enhSpeed = fields[73]?.asDouble {
            sample.speed = enhSpeed / 1000.0
        } else if let speed = fields[6]?.asDouble {
            sample.speed = speed / 1000.0
        }
        if let power = fields[7]?.asUInt64 { sample.power = Int(power) }
        if let temp = fields[13]?.asInt8 { sample.temperature = Double(temp) }

        return sample
    }
}

// MARK: - ByteReader

private struct ByteReader {
    let data: Data
    var offset: Int
    let end: Int

    var remaining: Int { max(0, end - offset) }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < end else { throw FITParserError.truncatedRecord }
        let v = data[offset]
        offset += 1
        return v
    }

    mutating func readUInt16(bigEndian: Bool) throws -> UInt16 {
        let bytes = try readBytes(count: 2)
        return bytes.readUInt16(at: 0, bigEndian: bigEndian)
    }

    mutating func readBytes(count: Int) throws -> Data {
        guard offset + count <= end else { throw FITParserError.truncatedRecord }
        let slice = data.subdata(in: offset..<(offset + count))
        offset += count
        return slice
    }
}

private extension Data {
    func readUInt16(at index: Int, bigEndian: Bool) -> UInt16 {
        let lo = UInt16(self[self.startIndex + index])
        let hi = UInt16(self[self.startIndex + index + 1])
        return bigEndian ? (lo << 8) | hi : (hi << 8) | lo
    }

    func readUInt32(at index: Int, bigEndian: Bool) -> UInt32 {
        let b0 = UInt32(self[self.startIndex + index])
        let b1 = UInt32(self[self.startIndex + index + 1])
        let b2 = UInt32(self[self.startIndex + index + 2])
        let b3 = UInt32(self[self.startIndex + index + 3])
        return bigEndian
            ? (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
            : (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
    }

    func readUInt64(at index: Int, bigEndian: Bool) -> UInt64 {
        var v: UInt64 = 0
        if bigEndian {
            for i in 0..<8 {
                v = (v << 8) | UInt64(self[self.startIndex + index + i])
            }
        } else {
            for i in 0..<8 {
                v |= UInt64(self[self.startIndex + index + i]) << (8 * i)
            }
        }
        return v
    }

    func readUInt32LE(at index: Int) -> UInt32 {
        readUInt32(at: index, bigEndian: false)
    }
}
