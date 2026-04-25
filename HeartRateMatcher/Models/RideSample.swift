import Foundation
import CoreLocation

public struct RideSample: Hashable, Codable, Sendable {
    public var timestamp: Date
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: Double?
    public var heartRate: Int?
    public var cadence: Int?
    public var power: Int?
    /// metres per second
    public var speed: Double?
    /// metres from ride start
    public var distance: Double?
    /// degrees Celsius
    public var temperature: Double?

    public init(
        timestamp: Date,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        heartRate: Int? = nil,
        cadence: Int? = nil,
        power: Int? = nil,
        speed: Double? = nil,
        distance: Double? = nil,
        temperature: Double? = nil
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.heartRate = heartRate
        self.cadence = cadence
        self.power = power
        self.speed = speed
        self.distance = distance
        self.temperature = temperature
    }

    public var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public func value(for channel: RideChannel) -> Double? {
        switch channel {
        case .coordinate:  return latitude
        case .altitude:    return altitude
        case .heartRate:   return heartRate.map(Double.init)
        case .cadence:     return cadence.map(Double.init)
        case .power:       return power.map(Double.init)
        case .speed:       return speed
        case .distance:    return distance
        case .temperature: return temperature
        }
    }

    public func has(_ channel: RideChannel) -> Bool {
        switch channel {
        case .coordinate:  return latitude != nil && longitude != nil
        case .altitude:    return altitude != nil
        case .heartRate:   return heartRate != nil
        case .cadence:     return cadence != nil
        case .power:       return power != nil
        case .speed:       return speed != nil
        case .distance:    return distance != nil
        case .temperature: return temperature != nil
        }
    }
}
