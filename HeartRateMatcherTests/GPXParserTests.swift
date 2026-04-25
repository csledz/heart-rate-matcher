import XCTest
@testable import HeartRateMatcher

final class GPXParserTests: XCTestCase {
    func testParsesGarminTrackpointExtensions() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Garmin"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2">
          <trk>
            <name>Morning Ride</name>
            <trkseg>
              <trkpt lat="48.1" lon="11.5">
                <ele>520.0</ele>
                <time>2024-06-01T07:00:00Z</time>
                <extensions>
                  <gpxtpx:TrackPointExtension>
                    <gpxtpx:hr>132</gpxtpx:hr>
                    <gpxtpx:cad>85</gpxtpx:cad>
                    <gpxtpx:atemp>18.5</gpxtpx:atemp>
                  </gpxtpx:TrackPointExtension>
                  <power>240</power>
                </extensions>
              </trkpt>
              <trkpt lat="48.11" lon="11.51">
                <ele>522.0</ele>
                <time>2024-06-01T07:00:01Z</time>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let ride = try GPXParser().parse(data: Data(gpx.utf8), filename: "test.gpx")
        XCTAssertEqual(ride.name, "Morning Ride")
        XCTAssertEqual(ride.samples.count, 2)
        XCTAssertEqual(ride.samples[0].heartRate, 132)
        XCTAssertEqual(ride.samples[0].cadence, 85)
        XCTAssertEqual(ride.samples[0].temperature, 18.5)
        XCTAssertEqual(ride.samples[0].power, 240)
        XCTAssertEqual(ride.samples[0].latitude!, 48.1, accuracy: 1e-6)
    }

    func testEmptyGPXThrows() {
        let gpx = """
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg></trkseg></trk></gpx>
        """
        XCTAssertThrowsError(try GPXParser().parse(data: Data(gpx.utf8), filename: "x.gpx"))
    }
}
