import Foundation

public enum RideSourceFormat: String, Codable, Sendable {
    case fit
    case gpx
}

public struct Ride: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var sourceFormat: RideSourceFormat
    public var sourceFilename: String
    public var samples: [RideSample]

    public init(
        id: UUID = UUID(),
        name: String,
        sourceFormat: RideSourceFormat,
        sourceFilename: String,
        samples: [RideSample]
    ) {
        self.id = id
        self.name = name
        self.sourceFormat = sourceFormat
        self.sourceFilename = sourceFilename
        self.samples = samples.sorted { $0.timestamp < $1.timestamp }
    }

    public var startDate: Date? { samples.first?.timestamp }
    public var endDate: Date? { samples.last?.timestamp }

    public var duration: TimeInterval {
        guard let s = startDate, let e = endDate else { return 0 }
        return e.timeIntervalSince(s)
    }

    public var availableChannels: Set<RideChannel> {
        var found: Set<RideChannel> = []
        for sample in samples {
            for channel in RideChannel.allCases where sample.has(channel) {
                found.insert(channel)
            }
            if found.count == RideChannel.allCases.count { break }
        }
        return found
    }
}
