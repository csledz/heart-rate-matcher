import Foundation

/// Writes a `Ride` as GPX 1.1 with the Garmin TrackPointExtension v2 namespace
/// (heart rate, cadence, atemp) plus the Cluetrust-style `<power>` element
/// inside `<extensions>` which Strava ingests.
public struct GPXExporter {
    public init() {}

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public func export(ride: Ride) -> Data {
        var xml = ""
        xml += #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        xml += #"<gpx version="1.1" creator="HeartRateMatcher""#
        xml += #" xmlns="http://www.topografix.com/GPX/1/1""#
        xml += #" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2""#
        xml += #" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance""#
        xml += #" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">"#
        xml += "\n"

        if let start = ride.startDate {
            xml += "  <metadata>\n"
            xml += "    <time>\(Self.isoFormatter.string(from: start))</time>\n"
            xml += "    <name>\(escape(ride.name))</name>\n"
            xml += "  </metadata>\n"
        }

        xml += "  <trk>\n"
        xml += "    <name>\(escape(ride.name))</name>\n"
        xml += "    <type>cycling</type>\n"
        xml += "    <trkseg>\n"

        for sample in ride.samples {
            xml += renderTrackpoint(sample)
        }

        xml += "    </trkseg>\n"
        xml += "  </trk>\n"
        xml += "</gpx>\n"

        return Data(xml.utf8)
    }

    private func renderTrackpoint(_ s: RideSample) -> String {
        let lat = s.latitude.map { format($0, decimals: 7) } ?? "0"
        let lon = s.longitude.map { format($0, decimals: 7) } ?? "0"
        var out = "      <trkpt lat=\"\(lat)\" lon=\"\(lon)\">\n"
        if let alt = s.altitude {
            out += "        <ele>\(format(alt, decimals: 2))</ele>\n"
        }
        out += "        <time>\(Self.isoFormatter.string(from: s.timestamp))</time>\n"
        if let speed = s.speed {
            out += "        <speed>\(format(speed, decimals: 3))</speed>\n"
        }

        let hasTPX = s.heartRate != nil || s.cadence != nil || s.temperature != nil
        let hasPower = s.power != nil
        if hasTPX || hasPower {
            out += "        <extensions>\n"
            if hasTPX {
                out += "          <gpxtpx:TrackPointExtension>\n"
                if let hr = s.heartRate {
                    out += "            <gpxtpx:hr>\(hr)</gpxtpx:hr>\n"
                }
                if let cad = s.cadence {
                    out += "            <gpxtpx:cad>\(cad)</gpxtpx:cad>\n"
                }
                if let temp = s.temperature {
                    out += "            <gpxtpx:atemp>\(format(temp, decimals: 1))</gpxtpx:atemp>\n"
                }
                out += "          </gpxtpx:TrackPointExtension>\n"
            }
            if let power = s.power {
                out += "          <power>\(power)</power>\n"
            }
            out += "        </extensions>\n"
        }
        out += "      </trkpt>\n"
        return out
    }

    private func format(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
