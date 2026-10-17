import Foundation
import CoreLocation

enum FootfallLevel: String, CaseIterable, Identifiable {
    case any = "Any level"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case veryHigh = "Very high"
    var id: String { rawValue }
}

enum TimeOfDay: String, CaseIterable, Identifiable {
    case morning = "Morning", lunch = "Lunch", afternoon = "Afternoon", evening = "Evening"
    var id: String { rawValue }

    /// Hours of the day (24h clock) averaged for this window.
    var hours: ClosedRange<Int> {
        switch self {
        case .morning: return 7...10
        case .lunch: return 11...13
        case .afternoon: return 14...16
        case .evening: return 17...20
        }
    }

    var label: String {
        switch self {
        case .morning: return "7–11am"
        case .lunch: return "11am–2pm"
        case .afternoon: return "2–5pm"
        case .evening: return "5–9pm"
        }
    }
}

enum DayType: String, CaseIterable, Identifiable {
    case weekday = "Weekday", weekend = "Weekend"
    var id: String { rawValue }
}

enum CompetitorType: String, CaseIterable, Identifiable {
    case direct = "Direct competitors"
    case indirect = "Indirect competitors"
    case all = "All businesses"
    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .direct: return "Businesses of the same type as yours."
        case .indirect: return "Businesses of other types competing for the same customers' time and spend."
        case .all: return "Every active business."
        }
    }
}

enum SearchRadius: Int, CaseIterable, Identifiable {
    case m250 = 250, m500 = 500, km1 = 1000, km2 = 2000
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .m250: return "250 m"
        case .m500: return "500 m"
        case .km1: return "1 km"
        case .km2: return "2 km"
        }
    }
}

enum CompetitionPreference: String, CaseIterable, Identifiable {
    case low = "Low competition"
    case balanced = "Balanced"
    case established = "Established area"
    case any = "Any level"
    var id: String { rawValue }
}

/// Approximate distance between two points, in metres (Haversine).
func haversineMetres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    let earthRadius = 6_371_000.0
    let lat1 = a.latitude * .pi / 180
    let lat2 = b.latitude * .pi / 180
    let dLat = (b.latitude - a.latitude) * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180
    let h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * earthRadius * asin(min(1, sqrt(h)))
}

@Observable
final class MapFilterState {
    var businessCategory: BusinessCategory? = nil
    var area: String? = nil
    var footfallLevel: FootfallLevel = .any
    var timesOfDay: Set<TimeOfDay> = []
    var dayTypes: Set<DayType> = []
    var competitorType: CompetitorType = .direct
    var searchRadius: SearchRadius = .m500
    var competitionPreference: CompetitionPreference = .any

    var showCompetitorMarkers: Bool = true
    var showBusinessDots: Bool = true
    var showFootfallZones: Bool = false
    var showVacancyZones: Bool = false
    var showCarParks: Bool = false
    var showOnStreetParking: Bool = false

    /// Hours selected by Time of Day. Empty selection = the trading day, 7am-9pm.
    var selectedHours: [Int] {
        let hours = timesOfDay.flatMap { Array($0.hours) }
        return hours.isEmpty ? Array(7...20) : Array(Set(hours)).sorted()
    }

    var timeWindowLabel: String {
        let times = timesOfDay.isEmpty
            ? "7am–9pm"
            : TimeOfDay.allCases.filter(timesOfDay.contains).map(\.rawValue.localizedLowercase).joined(separator: " + ")
        let days: String
        switch (dayTypes.contains(.weekday), dayTypes.contains(.weekend)) {
        case (true, false): days = "weekdays"
        case (false, true): days = "weekends"
        default: days = "all week"
        }
        return "\(times), \(days)"
    }

    var isFiltering: Bool {
        area != nil || footfallLevel != .any || competitionPreference != .any
    }

    func resetAll() {
        businessCategory = nil
        area = nil
        footfallLevel = .any
        timesOfDay = []
        dayTypes = []
        competitorType = .direct
        searchRadius = .m500
        competitionPreference = .any
    }
}
