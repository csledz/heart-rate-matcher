import Foundation

/// A measurable signal recorded during a ride. Each ride sample carries a
/// subset of these channels — the merger lets you pick which source wins
/// per channel.
public enum RideChannel: String, CaseIterable, Identifiable, Codable, Sendable {
    case coordinate
    case altitude
    case heartRate
    case cadence
    case power
    case speed
    case distance
    case temperature

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .coordinate:  return "GPS Position"
        case .altitude:    return "Altitude"
        case .heartRate:   return "Heart Rate"
        case .cadence:     return "Cadence"
        case .power:       return "Power"
        case .speed:       return "Speed"
        case .distance:    return "Distance"
        case .temperature: return "Temperature"
        }
    }

    public var unit: String {
        switch self {
        case .coordinate:  return "lat/lon"
        case .altitude:    return "m"
        case .heartRate:   return "bpm"
        case .cadence:     return "rpm"
        case .power:       return "W"
        case .speed:       return "m/s"
        case .distance:    return "m"
        case .temperature: return "°C"
        }
    }
}
