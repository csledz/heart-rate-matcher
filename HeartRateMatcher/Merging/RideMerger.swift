import Foundation

public struct RideMerger {
    public init() {}

    /// Apply the configuration's per-ride transforms, then for each sample on
    /// the primary ride's (transformed) timeline pull each channel from its
    /// configured source — interpolating when the source is the secondary ride.
    public func merge(rideA: Ride, rideB: Ride, configuration: MergeConfiguration) -> Ride {
        let transformedA = applyTransform(configuration.transformA, to: rideA)
        let transformedB = applyTransform(configuration.transformB, to: rideB)

        let primary = configuration.primary == .rideA ? transformedA : transformedB
        let secondary = configuration.primary == .rideA ? transformedB : transformedA
        let primarySource: RideSource = configuration.primary
        let secondarySource: RideSource = configuration.primary == .rideA ? .rideB : .rideA

        let timeOffset = computeTimeOffset(
            primary: primary,
            secondary: secondary,
            alignment: configuration.alignment
        )

        var merged: [RideSample] = []
        merged.reserveCapacity(primary.samples.count)

        for primarySample in primary.samples {
            var out = RideSample(timestamp: primarySample.timestamp)
            let secondaryAt = primarySample.timestamp.addingTimeInterval(timeOffset)
            let secondarySample = interpolatedSample(in: secondary, at: secondaryAt)

            for channel in RideChannel.allCases {
                let chosen = configuration.source(for: channel)
                let sample = (chosen == primarySource) ? primarySample : secondarySample
                guard let sample else { continue }
                copy(channel: channel, from: sample, to: &out)
            }
            merged.append(out)
        }

        let suffix = "merged"
        let baseName = primary.name
        return Ride(
            name: "\(baseName) (\(suffix))",
            sourceFormat: primary.sourceFormat,
            sourceFilename: primary.sourceFilename,
            samples: merged
        )
    }

    // MARK: - Transforms

    /// Compresses or stretches the time axis. multiplier = 1.10 → ride is
    /// played back 10% faster, so each sample's offset from start is divided
    /// by 1.10 and the speed channel is multiplied by 1.10.
    func applyTransform(_ transform: RideTransform, to ride: Ride) -> Ride {
        if transform.isIdentity { return ride }
        let multiplier = max(0.01, transform.speedMultiplier)
        guard let start = ride.startDate else { return ride }
        let scaled = ride.samples.map { sample -> RideSample in
            let originalOffset = sample.timestamp.timeIntervalSince(start)
            let newTimestamp = start.addingTimeInterval(originalOffset / multiplier)
            var copy = sample
            copy.timestamp = newTimestamp
            if let speed = copy.speed { copy.speed = speed * multiplier }
            return copy
        }
        return Ride(
            id: ride.id,
            name: ride.name,
            sourceFormat: ride.sourceFormat,
            sourceFilename: ride.sourceFilename,
            samples: scaled
        )
    }

    // MARK: - Alignment

    private func computeTimeOffset(
        primary: Ride,
        secondary: Ride,
        alignment: AlignmentStrategy
    ) -> TimeInterval {
        switch alignment {
        case .absoluteTimestamp:
            return 0
        case .offsetFromStart:
            guard let pStart = primary.startDate, let sStart = secondary.startDate else {
                return 0
            }
            return sStart.timeIntervalSince(pStart)
        }
    }

    // MARK: - Interpolation

    func interpolatedSample(in ride: Ride, at date: Date) -> RideSample? {
        let samples = ride.samples
        guard !samples.isEmpty else { return nil }
        if date <= samples.first!.timestamp { return samples.first }
        if date >= samples.last!.timestamp { return samples.last }

        // Binary search for the upper bound.
        var lo = 0
        var hi = samples.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if samples[mid].timestamp <= date {
                lo = mid
            } else {
                hi = mid
            }
        }
        let a = samples[lo]
        let b = samples[hi]
        let span = b.timestamp.timeIntervalSince(a.timestamp)
        let t = span <= 0 ? 0 : date.timeIntervalSince(a.timestamp) / span
        return interpolate(a: a, b: b, t: t, at: date)
    }

    private func interpolate(a: RideSample, b: RideSample, t: Double, at date: Date) -> RideSample {
        func lerp(_ x: Double?, _ y: Double?) -> Double? {
            guard let x, let y else { return x ?? y }
            return x + (y - x) * t
        }
        func lerpInt(_ x: Int?, _ y: Int?) -> Int? {
            guard let x, let y else { return x ?? y }
            return Int((Double(x) + (Double(y) - Double(x)) * t).rounded())
        }
        return RideSample(
            timestamp: date,
            latitude: lerp(a.latitude, b.latitude),
            longitude: lerp(a.longitude, b.longitude),
            altitude: lerp(a.altitude, b.altitude),
            heartRate: lerpInt(a.heartRate, b.heartRate),
            cadence: lerpInt(a.cadence, b.cadence),
            power: lerpInt(a.power, b.power),
            speed: lerp(a.speed, b.speed),
            distance: lerp(a.distance, b.distance),
            temperature: lerp(a.temperature, b.temperature)
        )
    }

    private func copy(channel: RideChannel, from src: RideSample, to dst: inout RideSample) {
        switch channel {
        case .coordinate:
            dst.latitude = src.latitude
            dst.longitude = src.longitude
        case .altitude:    dst.altitude = src.altitude
        case .heartRate:   dst.heartRate = src.heartRate
        case .cadence:     dst.cadence = src.cadence
        case .power:       dst.power = src.power
        case .speed:       dst.speed = src.speed
        case .distance:    dst.distance = src.distance
        case .temperature: dst.temperature = src.temperature
        }
    }
}
