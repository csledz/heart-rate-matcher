import Foundation

public enum RideImportError: Error, LocalizedError {
    case unsupportedFormat(String)
    case underlying(Error)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported file type: .\(ext). Expected .fit or .gpx."
        case .underlying(let err):
            return (err as? LocalizedError)?.errorDescription ?? String(describing: err)
        }
    }
}

public struct RideImporter {
    public init() {}

    public func importRide(from url: URL) throws -> Ride {
        let ext = url.pathExtension.lowercased()
        do {
            switch ext {
            case "gpx":
                return try GPXParser().parse(url: url)
            case "fit":
                return try FITParser().parse(url: url)
            default:
                throw RideImportError.unsupportedFormat(ext)
            }
        } catch let error as RideImportError {
            throw error
        } catch {
            throw RideImportError.underlying(error)
        }
    }
}
