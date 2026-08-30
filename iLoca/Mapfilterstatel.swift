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
}

enum DayType: String, CaseIterable, Identifiable {
    case weekday = "Weekday", weekend = "Weekend"
    var id: String { rawValue }
}

enum CompetitorType: String, CaseIterable, Identifiable {
    case direct = "Direct competitors"
    case indirect = "Indirect competitors"
    case all = "All similar"
    var id: String { rawValue }
}

enum SearchRadius: Int, CaseIterable, Identifiable {
    case m250 = 250, m500 = 500, km1 = 1000, km2 = 2000
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .m250: return "250 metres"
        case .m500: return "500 metres"
        case .km1: return "1 kilometre"
        case .km2: return "2 kilometres"
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

/// Approximate distance between two block centroids, in metres (Haversine).
/// Used for the Competition radius filter since we only have block-level
/// centroids, not per-business coordinates — an honest approximation, not
/// pinpoint-accurate at 250m, but consistent at the block level.
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
    var footfallLevel: FootfallLevel = .any
    var timesOfDay: Set<TimeOfDay> = []
    var dayTypes: Set<DayType> = []
    var competitorType: CompetitorType = .all
    var searchRadius: SearchRadius = .m500
    var competitionPreference: CompetitionPreference = .any

    var showCompetitorMarkers: Bool = true
    var showDevelopmentSites: Bool = true   // dummy toggle, no backing data
    var showTransitStops: Bool = true       // dummy toggle, no backing data
    var showFootfallZones: Bool = false
    var showVacancyZones: Bool = false
}
