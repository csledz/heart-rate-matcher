import XCTest
@testable import HeartRateMatcher

final class FITExporterTests: XCTestCase {
    func testHeaderHasFITMagic() {
        let ride = makeRide(samples: 5)
        let data = FITExporter().export(ride: ride)
        XCTAssertGreaterThanOrEqual(data.count, 14)
        XCTAssertEqual(data[0], 12)                           // header size
        XCTAssertEqual(Array(data[8..<12]), Array(".FIT".utf8))
    }

    func testFITRoundTripsThroughOurParser() throws {
        let ride = makeRide(samples: 10)
        let data = FITExporter().export(ride: ride)
        let parsed = try FITParser().parse(data: data, filename: "out.fit")
        XCTAssertEqual(parsed.samples.count, ride.samples.count)
        XCTAssertEqual(parsed.samples[3].heartRate, ride.samples[3].heartRate)
        XCTAssertEqual(parsed.samples[3].power, ride.samples[3].power)
        XCTAssertEqual(parsed.samples[3].cadence, ride.samples[3].cadence)
        XCTAssertEqual(parsed.samples[3].latitude!, ride.samples[3].latitude!, accuracy: 1e-5)
        XCTAssertEqual(parsed.samples[3].altitude!, ride.samples[3].altitude!, accuracy: 0.5)
    }

    func testCRCFooterIsValid() {
        let ride = makeRide(samples: 3)
        let data = FITExporter().export(ride: ride)
        let body = data.subdata(in: 0..<(data.count - 2))
        let footer = UInt16(data[data.count - 2]) | (UInt16(data[data.count - 1]) << 8)
        XCTAssertEqual(footer, FITCRC.compute(body))
    }

    func testRideWithoutChannelsStillProducesValidFile() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let ride = Ride(
            name: "Bare",
            sourceFormat: .fit,
            sourceFilename: "bare.fit",
            samples: (0..<3).map { i in
                RideSample(timestamp: start.addingTimeInterval(Double(i)))
            }
        )
        let data = FITExporter().export(ride: ride)
        let parsed = try FITParser().parse(data: data, filename: "out.fit")
        XCTAssertEqual(parsed.samples.count, 3)
    }

    private func makeRide(samples: Int) -> Ride {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return Ride(
            name: "Test",
            sourceFormat: .fit,
            sourceFilename: "test.fit",
            samples: (0..<samples).map { i in
                RideSample(
                    timestamp: start.addingTimeInterval(Double(i)),
                    latitude: 48.0 + 0.001 * Double(i),
                    longitude: 11.5 + 0.001 * Double(i),
                    altitude: 500 + Double(i),
                    heartRate: 130 + i,
                    cadence: 80 + i,
                    power: 200 + i,
                    speed: 5.0 + 0.1 * Double(i),
                    distance: Double(i) * 5.0,
                    temperature: 19.0
                )
            }
        )
    }
}
