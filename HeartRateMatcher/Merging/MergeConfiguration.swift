import Foundation

public enum RideSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case rideA
    case rideB

    public var id: String { rawValue }
    public var label: String { self == .rideA ? "Ride A" : "Ride B" }
}

/// Time-axis transform applied to a ride before merging. `speedMultiplier`
/// of 1.10 means "make this ride 10% faster" — the time axis is compressed
/// by 10% and the speed channel is scaled up by 10%. Distance, GPS,
/// HR/cadence/power, etc. are unchanged in value.
public struct RideTransform: Codable, Equatable, Sendable {
    public var speedMultiplier: Double

    public init(speedMultiplier: Double = 1.0) {
        self.speedMultiplier = speedMultiplier
    }

    public static let identity = RideTransform(speedMultiplier: 1.0)

    public var isIdentity: Bool { abs(speedMultiplier - 1.0) < .ulpOfOne }

    /// Convenience: percentage delta from 100% (e.g. +10% → multiplier 1.10).
    public var percentDelta: Double {
        get { (speedMultiplier - 1.0) * 100 }
        set { speedMultiplier = 1.0 + newValue / 100.0 }
    }
}

public enum AlignmentStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Align by absolute timestamp — assumes both rides were recorded at
    /// the same wall-clock time (e.g. two devices on one ride).
    case absoluteTimestamp
    /// Align by offset from each ride's start — appropriate for two
    /// recordings of the same route on different days.
    case offsetFromStart

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .absoluteTimestamp: return "Absolute timestamp"
        case .offsetFromStart:   return "Offset from start"
        }
    }
}

public struct MergeConfiguration: Codable, Sendable {
    public var primary: RideSource
    public var alignment: AlignmentStrategy
    public var channelSources: [RideChannel: RideSource]
    public var transformA: RideTransform
    public var transformB: RideTransform

    public init(
        primary: RideSource = .rideA,
        alignment: AlignmentStrategy = .offsetFromStart,
        channelSources: [RideChannel: RideSource] = [:],
        transformA: RideTransform = .identity,
        transformB: RideTransform = .identity
    ) {
        self.primary = primary
        self.alignment = alignment
        self.channelSources = channelSources
        self.transformA = transformA
        self.transformB = transformB
    }

    public func source(for channel: RideChannel) -> RideSource {
        channelSources[channel] ?? primary
    }

    public mutating func setSource(_ source: RideSource, for channel: RideChannel) {
        channelSources[channel] = source
    }

    public func transform(for source: RideSource) -> RideTransform {
        switch source {
        case .rideA: return transformA
        case .rideB: return transformB
        }
    }

    /// Default mapping: every channel comes from the primary ride.
    public static func defaultConfiguration(for rideA: Ride, rideB: Ride) -> MergeConfiguration {
        var sources: [RideChannel: RideSource] = [:]
        for channel in RideChannel.allCases {
            sources[channel] = .rideA
        }
        return MergeConfiguration(
            primary: .rideA,
            alignment: .offsetFromStart,
            channelSources: sources
        )
    }
}
