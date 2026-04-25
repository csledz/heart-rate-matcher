import Foundation

/// Writes a `Ride` as a minimal but spec-conformant FIT activity file:
/// `file_id` → `activity` → `session` → `lap` → many `record` messages.
/// Fields the ride doesn't carry are emitted as the FIT-defined invalid
/// sentinels so Garmin Connect / Strava parse the file cleanly.
public struct FITExporter {
    public init() {}

    public func export(ride: Ride) -> Data {
        let payload = buildPayload(ride: ride)
        var file = Data()
        file.append(makeHeader(dataSize: payload.count))
        file.append(payload)
        let crc = FITCRC.compute(file)
        file.append(UInt8(crc & 0xFF))
        file.append(UInt8((crc >> 8) & 0xFF))
        return file
    }

    // MARK: - Header

    private func makeHeader(dataSize: Int) -> Data {
        var header = Data(count: 12)
        header[0] = 12                            // header size
        header[1] = 0x20                          // protocol version 2.0
        header[2] = 0x6C; header[3] = 0x08        // profile version 21.40 LE
        let size = UInt32(dataSize)
        header[4] = UInt8(size & 0xFF)
        header[5] = UInt8((size >> 8) & 0xFF)
        header[6] = UInt8((size >> 16) & 0xFF)
        header[7] = UInt8((size >> 24) & 0xFF)
        header[8] = 0x2E                          // '.'
        header[9] = 0x46                          // 'F'
        header[10] = 0x49                         // 'I'
        header[11] = 0x54                         // 'T'
        return header
    }

    // MARK: - Payload

    /// FIT timestamps count seconds since 1989-12-31T00:00:00Z UTC.
    private static let fitEpoch = Date(timeIntervalSince1970: 631_065_600)
    private static let degreeToSemicircle = 2_147_483_648.0 / 180.0

    private func fitTimestamp(_ date: Date) -> UInt32 {
        let secs = date.timeIntervalSince(Self.fitEpoch)
        return UInt32(max(0, secs.rounded()))
    }

    private func buildPayload(ride: Ride) -> Data {
        var out = Data()

        let start = ride.startDate ?? Date()
        let end = ride.endDate ?? start
        let elapsed = max(0, end.timeIntervalSince(start))
        let totalDistance = ride.samples.last?.distance ?? 0
        let presentChannels = ride.availableChannels

        // ---- file_id (global 0) — local type 0 -------------------------------
        out.append(definition(
            localType: 0,
            globalNum: 0,
            fields: [
                FieldDef(num: 0, size: 1, baseType: 0x00),  // type (enum)
                FieldDef(num: 1, size: 2, baseType: 0x84),  // manufacturer (uint16)
                FieldDef(num: 2, size: 2, baseType: 0x84),  // product (uint16)
                FieldDef(num: 3, size: 4, baseType: 0x8C),  // serial_number (uint32z)
                FieldDef(num: 4, size: 4, baseType: 0x86),  // time_created (uint32)
            ]
        ))
        out.append(dataHeader(localType: 0))
        out.append(uint8(4))                 // type = activity
        out.append(uint16(255))              // manufacturer = development
        out.append(uint16(0))                // product
        out.append(uint32(0xCAFEBABE))       // serial_number
        out.append(uint32(fitTimestamp(start)))

        // ---- record (global 20) — local type 1 -------------------------------
        let recordFields = recordFieldDefinitions(for: presentChannels)
        out.append(definition(localType: 1, globalNum: 20, fields: recordFields))

        for sample in ride.samples {
            out.append(dataHeader(localType: 1))
            for f in recordFields {
                out.append(encodeRecordField(f, sample: sample))
            }
        }

        // ---- lap (global 19) — local type 2 ----------------------------------
        out.append(definition(
            localType: 2,
            globalNum: 19,
            fields: [
                FieldDef(num: 253, size: 4, baseType: 0x86), // timestamp
                FieldDef(num: 2,   size: 4, baseType: 0x86), // start_time
                FieldDef(num: 7,   size: 4, baseType: 0x86), // total_elapsed_time (s * 1000)
                FieldDef(num: 8,   size: 4, baseType: 0x86), // total_timer_time
                FieldDef(num: 9,   size: 4, baseType: 0x86), // total_distance (m * 100)
                FieldDef(num: 0,   size: 1, baseType: 0x00), // event
                FieldDef(num: 1,   size: 1, baseType: 0x00), // event_type
            ]
        ))
        out.append(dataHeader(localType: 2))
        out.append(uint32(fitTimestamp(end)))
        out.append(uint32(fitTimestamp(start)))
        out.append(uint32(UInt32((elapsed * 1000).rounded())))
        out.append(uint32(UInt32((elapsed * 1000).rounded())))
        out.append(uint32(UInt32((totalDistance * 100).rounded())))
        out.append(uint8(9))   // event = lap
        out.append(uint8(1))   // event_type = stop

        // ---- session (global 18) — local type 3 ------------------------------
        out.append(definition(
            localType: 3,
            globalNum: 18,
            fields: [
                FieldDef(num: 253, size: 4, baseType: 0x86), // timestamp
                FieldDef(num: 2,   size: 4, baseType: 0x86), // start_time
                FieldDef(num: 7,   size: 4, baseType: 0x86), // total_elapsed_time
                FieldDef(num: 8,   size: 4, baseType: 0x86), // total_timer_time
                FieldDef(num: 9,   size: 4, baseType: 0x86), // total_distance
                FieldDef(num: 5,   size: 1, baseType: 0x00), // sport
                FieldDef(num: 6,   size: 1, baseType: 0x00), // sub_sport
                FieldDef(num: 0,   size: 1, baseType: 0x00), // event
                FieldDef(num: 1,   size: 1, baseType: 0x00), // event_type
            ]
        ))
        out.append(dataHeader(localType: 3))
        out.append(uint32(fitTimestamp(end)))
        out.append(uint32(fitTimestamp(start)))
        out.append(uint32(UInt32((elapsed * 1000).rounded())))
        out.append(uint32(UInt32((elapsed * 1000).rounded())))
        out.append(uint32(UInt32((totalDistance * 100).rounded())))
        out.append(uint8(2))   // sport = cycling
        out.append(uint8(0))   // sub_sport = generic
        out.append(uint8(8))   // event = session
        out.append(uint8(1))   // event_type = stop

        // ---- activity (global 34) — local type 4 -----------------------------
        out.append(definition(
            localType: 4,
            globalNum: 34,
            fields: [
                FieldDef(num: 253, size: 4, baseType: 0x86), // timestamp
                FieldDef(num: 0,   size: 4, baseType: 0x86), // total_timer_time
                FieldDef(num: 1,   size: 2, baseType: 0x84), // num_sessions
                FieldDef(num: 2,   size: 1, baseType: 0x00), // type
                FieldDef(num: 3,   size: 1, baseType: 0x00), // event
                FieldDef(num: 4,   size: 1, baseType: 0x00), // event_type
            ]
        ))
        out.append(dataHeader(localType: 4))
        out.append(uint32(fitTimestamp(end)))
        out.append(uint32(UInt32((elapsed * 1000).rounded())))
        out.append(uint16(1))  // num_sessions
        out.append(uint8(0))   // type = manual
        out.append(uint8(26))  // event = activity
        out.append(uint8(1))   // event_type = stop

        return out
    }

    // MARK: - Record field selection

    private func recordFieldDefinitions(for channels: Set<RideChannel>) -> [FieldDef] {
        var fields: [FieldDef] = [
            FieldDef(num: 253, size: 4, baseType: 0x86), // timestamp (always)
        ]
        if channels.contains(.coordinate) {
            fields.append(FieldDef(num: 0, size: 4, baseType: 0x85)) // position_lat (sint32)
            fields.append(FieldDef(num: 1, size: 4, baseType: 0x85)) // position_long (sint32)
        }
        if channels.contains(.altitude) {
            fields.append(FieldDef(num: 2, size: 2, baseType: 0x84)) // altitude (uint16)
        }
        if channels.contains(.heartRate) {
            fields.append(FieldDef(num: 3, size: 1, baseType: 0x02)) // heart_rate (uint8)
        }
        if channels.contains(.cadence) {
            fields.append(FieldDef(num: 4, size: 1, baseType: 0x02)) // cadence (uint8)
        }
        if channels.contains(.distance) {
            fields.append(FieldDef(num: 5, size: 4, baseType: 0x86)) // distance (uint32)
        }
        if channels.contains(.speed) {
            fields.append(FieldDef(num: 6, size: 2, baseType: 0x84)) // speed (uint16)
        }
        if channels.contains(.power) {
            fields.append(FieldDef(num: 7, size: 2, baseType: 0x84)) // power (uint16)
        }
        if channels.contains(.temperature) {
            fields.append(FieldDef(num: 13, size: 1, baseType: 0x01)) // temperature (sint8)
        }
        return fields
    }

    private func encodeRecordField(_ field: FieldDef, sample: RideSample) -> Data {
        switch field.num {
        case 253:
            return uint32(fitTimestamp(sample.timestamp))
        case 0 where field.size == 4:
            guard let lat = sample.latitude else { return sint32(.max) }
            return sint32(Int32(clamping: Int(lat * Self.degreeToSemicircle)))
        case 1 where field.size == 4:
            guard let lon = sample.longitude else { return sint32(.max) }
            return sint32(Int32(clamping: Int(lon * Self.degreeToSemicircle)))
        case 2:
            guard let alt = sample.altitude else { return uint16(0xFFFF) }
            let raw = (alt + 500.0) * 5.0
            return uint16(UInt16(clamping: Int(raw.rounded())))
        case 3:
            return uint8(sample.heartRate.map { UInt8(clamping: $0) } ?? 0xFF)
        case 4:
            return uint8(sample.cadence.map { UInt8(clamping: $0) } ?? 0xFF)
        case 5:
            guard let d = sample.distance else { return uint32(0xFFFFFFFF) }
            return uint32(UInt32(clamping: Int((d * 100).rounded())))
        case 6:
            guard let s = sample.speed else { return uint16(0xFFFF) }
            return uint16(UInt16(clamping: Int((s * 1000).rounded())))
        case 7:
            return uint16(sample.power.map { UInt16(clamping: $0) } ?? 0xFFFF)
        case 13:
            return sint8(sample.temperature.map { Int8(clamping: Int($0.rounded())) } ?? 0x7F)
        default:
            return Data(repeating: 0xFF, count: field.size)
        }
    }

    // MARK: - Record headers / definitions

    private struct FieldDef {
        let num: UInt8
        let size: Int
        let baseType: UInt8
    }

    private func definition(localType: UInt8, globalNum: UInt16, fields: [FieldDef]) -> Data {
        var d = Data()
        d.append(0x40 | (localType & 0x0F))   // definition header
        d.append(0x00)                         // reserved
        d.append(0x00)                         // architecture: little-endian
        d.append(uint16(globalNum))
        d.append(UInt8(fields.count))
        for f in fields {
            d.append(f.num)
            d.append(UInt8(f.size))
            d.append(f.baseType)
        }
        return d
    }

    private func dataHeader(localType: UInt8) -> Data {
        Data([localType & 0x0F])
    }

    // MARK: - LE encoders

    private func uint8(_ v: UInt8) -> Data { Data([v]) }
    private func sint8(_ v: Int8) -> Data { Data([UInt8(bitPattern: v)]) }
    private func uint16(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }
    private func uint32(_ v: UInt32) -> Data {
        Data([
            UInt8(v & 0xFF),
            UInt8((v >> 8) & 0xFF),
            UInt8((v >> 16) & 0xFF),
            UInt8((v >> 24) & 0xFF),
        ])
    }
    private func sint32(_ v: Int32) -> Data { uint32(UInt32(bitPattern: v)) }
}

// MARK: - Garmin FIT 16-bit CRC

enum FITCRC {
    private static let table: [UInt16] = [
        0x0000, 0xCC01, 0xD801, 0x1400,
        0xF001, 0x3C00, 0x2800, 0xE401,
        0xA001, 0x6C00, 0x7800, 0xB401,
        0x5000, 0x9C01, 0x8801, 0x4400,
    ]

    static func compute(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0
        for byte in data {
            var tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int(byte & 0xF)]
            tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int((byte >> 4) & 0xF)]
        }
        return crc
    }
}
