import XCTest
@testable import HeartRateMatcher

final class GPXExporterTests: XCTestCase {
    func testExportRoundTripsThroughParser() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let ride = Ride(
            name: "Round Trip",
            sourceFormat: .gpx,
            sourceFilename: "rt.gpx",
            samples: (0..<5).map { i in
                RideSample(
                    timestamp: start.addingTimeInterval(Double(i)),
                    latitude: 48.0 + 0.001 * Double(i),
                    longitude: 11.5,
                    altitude: 500.0 + Double(i),
                    heartRate: 130 + i,
                    cadence: 80,
                    power: 220 + i,
                    speed: 5.5,
                    temperature: 19.0
                )
            }
        )

        let data = GPXExporter().export(ride: ride)
        let parsed = try GPXParser().parse(data: data, filename: "rt.gpx")
        XCTAssertEqual(parsed.samples.count, ride.samples.count)
        XCTAssertEqual(parsed.samples[2].heartRate, 132)
        XCTAssertEqual(parsed.samples[2].power, 222)
        XCTAssertEqual(parsed.samples[2].cadence, 80)
        XCTAssertEqual(parsed.samples[2].latitude!, 48.002, accuracy: 1e-6)
    }
}
