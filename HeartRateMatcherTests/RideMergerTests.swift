import XCTest
@testable import HeartRateMatcher

final class RideMergerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRide(
        name: String,
        format: RideSourceFormat = .gpx,
        builder: (Int) -> RideSample
    ) -> Ride {
        Ride(
            name: name,
            sourceFormat: format,
            sourceFilename: "\(name).gpx",
            samples: (0..<10).map(builder)
        )
    }

    func testChannelSelectionMergesAcrossSources() {
        let rideA = makeRide(name: "A") { i in
            RideSample(
                timestamp: start.addingTimeInterval(Double(i)),
                latitude: 48.0 + Double(i) * 0.001,
                longitude: 11.0,
                heartRate: 100 + i,
                power: nil
            )
        }
        let rideB = makeRide(name: "B") { i in
            RideSample(
                timestamp: start.addingTimeInterval(Double(i)),
                heartRate: 150 + i,
                power: 200 + i
            )
        }
        var config = MergeConfiguration.defaultConfiguration(for: rideA, rideB: rideB)
        config.alignment = .absoluteTimestamp
        config.setSource(.rideB, for: .heartRate)
        config.setSource(.rideB, for: .power)

        let merged = RideMerger().merge(rideA: rideA, rideB: rideB, configuration: config)
        XCTAssertEqual(merged.samples.count, 10)
        XCTAssertEqual(merged.samples[0].latitude, 48.0)        // from A
        XCTAssertEqual(merged.samples[0].heartRate, 150)        // from B
        XCTAssertEqual(merged.samples[0].power, 200)            // from B
        XCTAssertEqual(merged.samples[5].heartRate, 155)
    }

    func testSpeedMultiplierCompressesTimeAxisAndScalesSpeed() {
        let rideA = makeRide(name: "A") { i in
            RideSample(
                timestamp: start.addingTimeInterval(Double(i) * 10),
                speed: 5.0
            )
        }
        let rideB = rideA
        var config = MergeConfiguration.defaultConfiguration(for: rideA, rideB: rideB)
        config.transformA = RideTransform(speedMultiplier: 1.10) // +10% faster
        config.alignment = .offsetFromStart

        let merger = RideMerger()
        let scaled = merger.applyTransform(config.transformA, to: rideA)
        XCTAssertEqual(scaled.samples.count, rideA.samples.count)

        let originalDuration = rideA.duration
        let newDuration = scaled.duration
        XCTAssertEqual(newDuration, originalDuration / 1.10, accuracy: 1e-6)

        for sample in scaled.samples {
            XCTAssertEqual(sample.speed!, 5.5, accuracy: 1e-6)
        }
    }

    func testIdentityTransformIsNoOp() {
        let ride = makeRide(name: "A") { i in
            RideSample(timestamp: start.addingTimeInterval(Double(i)), speed: 4.0)
        }
        let merger = RideMerger()
        let result = merger.applyTransform(.identity, to: ride)
        XCTAssertEqual(result.duration, ride.duration)
        XCTAssertEqual(result.samples.first?.speed, 4.0)
    }

    func testInterpolationProducesValueBetweenSamples() {
        let ride = makeRide(name: "A") { i in
            RideSample(
                timestamp: start.addingTimeInterval(Double(i) * 10),
                heartRate: 100 + i * 10
            )
        }
        let merger = RideMerger()
        let mid = merger.interpolatedSample(in: ride, at: start.addingTimeInterval(15))
        XCTAssertNotNil(mid)
        // Halfway between hr=100 and hr=110 → 105.
        XCTAssertEqual(mid?.heartRate, 105)
    }

    func testPercentDeltaRoundtrip() {
        var t = RideTransform()
        t.percentDelta = 12.5
        XCTAssertEqual(t.speedMultiplier, 1.125, accuracy: 1e-9)
        t.percentDelta = -25
        XCTAssertEqual(t.speedMultiplier, 0.75, accuracy: 1e-9)
    }
}
