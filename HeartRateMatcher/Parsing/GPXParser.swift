import Foundation

public enum GPXParserError: Error {
    case invalidXML(underlying: Error?)
    case noTrackPoints
}

/// Streaming GPX 1.1 parser. Reads `<trkpt>` elements plus the common
/// extensions emitted by Garmin (`gpxtpx:hr`, `gpxtpx:cad`, `gpxtpx:atemp`)
/// and Strava (`<power>`).
public final class GPXParser: NSObject {
    public override init() {}

    public func parse(data: Data, filename: String) throws -> Ride {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw GPXParserError.invalidXML(underlying: parser.parserError)
        }
        guard !delegate.samples.isEmpty else {
            throw GPXParserError.noTrackPoints
        }
        let baseName = (filename as NSString).deletingPathExtension
        return Ride(
            name: delegate.trackName ?? baseName,
            sourceFormat: .gpx,
            sourceFilename: filename,
            samples: delegate.samples
        )
    }

    public func parse(url: URL) throws -> Ride {
        let data = try Data(contentsOf: url)
        return try parse(data: data, filename: url.lastPathComponent)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var samples: [RideSample] = []
        var trackName: String?

        private var inTrk = false
        private var inTrkpt = false
        private var current: RideSample?
        private var elementStack: [String] = []
        private var text = ""

        private static let isoFormatter: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        private static let isoFormatterNoFraction: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            elementStack.append(elementName)
            text = ""
            switch elementName {
            case "trk":
                inTrk = true
            case "trkpt":
                inTrkpt = true
                let lat = attributeDict["lat"].flatMap(Double.init)
                let lon = attributeDict["lon"].flatMap(Double.init)
                current = RideSample(timestamp: .distantPast, latitude: lat, longitude: lon)
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            defer {
                if !elementStack.isEmpty { elementStack.removeLast() }
                text = ""
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if elementName == "name", inTrk, !inTrkpt, trackName == nil {
                trackName = trimmed.isEmpty ? nil : trimmed
                return
            }

            guard inTrkpt, var sample = current else {
                if elementName == "trk" { inTrk = false }
                return
            }

            switch elementName {
            case "ele":
                sample.altitude = Double(trimmed)
            case "time":
                sample.timestamp = Self.parseDate(trimmed) ?? sample.timestamp
            case "hr", "gpxtpx:hr", "ns3:hr":
                sample.heartRate = Int(trimmed)
            case "cad", "gpxtpx:cad", "ns3:cad":
                sample.cadence = Int(trimmed)
            case "atemp", "gpxtpx:atemp", "ns3:atemp":
                sample.temperature = Double(trimmed)
            case "power", "gpxpx:PowerInWatts", "ns3:power":
                sample.power = Int(trimmed)
            case "speed":
                sample.speed = Double(trimmed)
            case "trkpt":
                if sample.timestamp != .distantPast {
                    samples.append(sample)
                }
                current = nil
                inTrkpt = false
                return
            default:
                break
            }
            current = sample
        }

        private static func parseDate(_ string: String) -> Date? {
            if let d = isoFormatter.date(from: string) { return d }
            return isoFormatterNoFraction.date(from: string)
        }
    }
}
