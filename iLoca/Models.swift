import Foundation
import CoreLocation

// MARK: - The "shapes" of iLoca's data.
// Everything here is built from the four City of Melbourne open datasets listed in
// docs/Iloca To do _data.pdf, fetched live from the Opendatasoft API (see OpenDataClient):
//   1. Blocks for Census of Land Use and Employment (CLUE)      -> block id, area, centroid
//   2. Business establishments per block by CLUE industry      -> category counts per block
//   3. Business establishments with address and industry class -> premises, vacancies, named businesses
//   4. Pedestrian Counting System (sensor locations + counts)  -> hourly foot traffic
//   5. Off-street car parks with capacity and type             -> public / private parking spaces
//   6. On-street parking bay sensors                           -> live bay occupancy

/// The four source datasets (sensor locations and hourly counts are two tables of dataset 4).
enum CityDataset: String, CaseIterable, Codable, Identifiable {
    case blocks = "blocks-for-census-of-land-use-and-employment-clue"
    case industryPerBlock = "business-establishments-per-block-by-clue-industry"
    case establishments = "business-establishments-with-address-and-industry-classification"
    case sensorLocations = "pedestrian-counting-system-sensor-locations"
    case pedestrianCounts = "pedestrian-counting-system-monthly-counts-per-hour"
    case offStreetParking = "off-street-car-parks-with-capacity-and-type"
    case onStreetParking = "on-street-parking-bay-sensors"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blocks: return "CLUE blocks"
        case .industryPerBlock: return "Business establishments per block by CLUE industry"
        case .establishments: return "Business establishments with address and industry classification"
        case .sensorLocations: return "Pedestrian Counting System: sensor locations"
        case .pedestrianCounts: return "Pedestrian Counting System: hourly counts"
        case .offStreetParking: return "Off-street car parks with capacity and type"
        case .onStreetParking: return "On-street parking bay sensors"
        }
    }

    /// Short name for dashboard tiles.
    var shortTitle: String {
        switch self {
        case .blocks: return "City blocks"
        case .industryPerBlock: return "Industry counts"
        case .establishments: return "Businesses & vacancies"
        case .sensorLocations: return "Pedestrian sensors"
        case .pedestrianCounts: return "Foot-traffic counts"
        case .offStreetParking: return "Off-street parking"
        case .onStreetParking: return "Live on-street parking"
        }
    }

    var icon: String {
        switch self {
        case .blocks: return "square.grid.3x3"
        case .industryPerBlock: return "chart.bar"
        case .establishments: return "storefront"
        case .sensorLocations: return "sensor"
        case .pedestrianCounts: return "figure.walk"
        case .offStreetParking: return "parkingsign.circle"
        case .onStreetParking: return "car"
        }
    }

    var usedFor: String {
        switch self {
        case .blocks: return "Block boundaries, centroids and area names. The join key for everything else."
        case .industryPerBlock: return "Competitor counts per block by industry (FnB, Retail, Services)."
        case .establishments: return "Vacant premises, named businesses and their map locations."
        case .sensorLocations: return "Where each pedestrian sensor is, matched to the nearest block."
        case .pedestrianCounts: return "Average hourly foot traffic over the last 28 days, weekday and weekend."
        case .offStreetParking: return "Public (commercial) car parks and private parking spaces near each block."
        case .onStreetParking: return "Live free/occupied status of sensor-fitted kerbside bays, refreshed every 5 minutes."
        }
    }

    var portalURL: URL {
        URL(string: "https://data.melbourne.vic.gov.au/explore/dataset/\(rawValue)/")!
    }
}

/// Catalogue metadata for one dataset, as published on the portal.
struct DatasetInfo: Codable, Identifiable {
    let dataset: CityDataset
    let modified: Date?
    let license: String?
    var id: String { dataset.rawValue }
}

/// One active pedestrian sensor and its average hourly profile.
struct PedestrianSensor: Codable, Identifiable {
    let locationId: Int
    let name: String
    let description: String
    let latitude: Double
    let longitude: Double
    /// Average people per hour, index = hour of day (0...23). nil = no readings for that hour.
    var weekdayHourly: [Double?]
    var weekendHourly: [Double?]

    var id: Int { locationId }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var hasCounts: Bool { weekdayHourly.contains { $0 != nil } || weekendHourly.contains { $0 != nil } }
}

/// One CLUE block, merged from datasets 1-4.
struct CityBlock: Codable, Identifiable {
    let blockId: Int
    let area: String
    let centroidLat: Double
    let centroidLon: Double

    /// Dataset 2: active establishments by broad category.
    let fnbCount: Int
    let retailCount: Int
    let activeEstablishments: Int

    /// Dataset 3: all premises recorded in the block, and how many are vacant.
    let totalPremises: Int
    let vacantPremises: Int

    /// Dataset 2: the block's industry mix (CLUE industry name -> count), non-zero only.
    let industryMix: [String: Int]

    /// Dataset 4: nearest active sensor within range of the centroid, if any.
    let sensorId: Int?
    let sensorDistanceMetres: Double?

    var id: Int { blockId }
    var coordinate: CLLocationCoordinate2D { .init(latitude: centroidLat, longitude: centroidLon) }
    var servicesCount: Int { max(0, activeEstablishments - fnbCount - retailCount) }

    var vacancyRatePct: Double {
        guard totalPremises > 0 else { return 0 }
        return Double(vacantPremises) / Double(totalPremises) * 100
    }

    func count(for category: BusinessCategory?) -> Int {
        switch category {
        case .cafe: return fnbCount
        case .retail: return retailCount
        case .services: return servicesCount
        case nil: return activeEstablishments
        }
    }
}

/// A single real premises record from dataset 3 (business or vacant space).
struct BusinessRecord: Codable, Identifiable, Hashable {
    let name: String
    let address: String
    let anzsicCode: String
    let industry: String
    let latitude: Double?
    let longitude: Double?

    var id: String { "\(name)|\(address)|\(anzsicCode)" }
    var isVacant: Bool { anzsicCode == "0000" }
    var category: BusinessCategory? { isVacant ? nil : BusinessCategory.categorize(anzsicCode: anzsicCode) }
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }
}

/// A public (commercial) off-street car park from dataset 5.
struct CarPark: Codable, Identifiable {
    let address: String
    let spaces: Int
    let latitude: Double
    let longitude: Double
    let blockId: Int?

    var id: String { "\(address)|\(latitude)|\(longitude)" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// One sensor-fitted kerbside bay from dataset 6, as of its last report.
struct ParkingBay: Codable, Identifiable {
    let kerbsideId: Int
    let latitude: Double
    let longitude: Double
    let isOccupied: Bool
    /// When the bay's state last changed.
    let since: Date?

    var id: Int { kerbsideId }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// Live on-street parking, fetched separately from the snapshot (it changes by the minute).
struct OnStreetParking: Codable {
    let bays: [ParkingBay]
    let fetchedAt: Date
    /// Most recent sensor report in the feed.
    let latestReport: Date?
}

/// Off-street parking (dataset 5), latest census year.
struct OffStreetParking: Codable {
    let censusYear: Int
    let carParks: [CarPark]
    /// Private (non-public) off-street spaces per block.
    let privateSpacesByBlock: [Int: Int]
}

/// Everything iLoca needs at launch, cached to disk as an offline fallback.
struct CitySnapshot: Codable {
    let censusYear: Int
    let blocks: [CityBlock]
    let sensors: [PedestrianSensor]
    let datasets: [DatasetInfo]
    /// First and last day of the pedestrian averaging window.
    let footfallWindowStart: Date?
    let footfallWindowEnd: Date?
    let offStreet: OffStreetParking?
    let fetchedAt: Date
}

/// Where the data on screen came from, shown in the freshness line and Info tab.
enum DataSourceState: Equatable {
    case loading
    case live(Date)
    case cached(Date, reason: String)
    case unavailable(String)

    var isUsable: Bool {
        switch self {
        case .live, .cached: return true
        default: return false
        }
    }
}

/// City data dates and times are Melbourne-local. Format them in Melbourne time so
/// they read correctly wherever the Mac is (e.g. a day-only date parsed as
/// Melbourne midnight would otherwise show as the previous day west of Melbourne).
enum MelbourneTime {
    static let zone = TimeZone(identifier: "Australia/Melbourne")!

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate(format)
        return f
    }
    private static let dayFormatter = formatter("d MMM yyyy")
    private static let shortDayFormatter = formatter("d MMM")
    private static let timeFormatter = formatter("h:mm a")

    /// "15 Oct 2026"
    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    /// "15 Oct"
    static func shortDay(_ date: Date) -> String { shortDayFormatter.string(from: date) }
    /// "5:54 am Melbourne time"
    static func time(_ date: Date) -> String {
        // DateFormatter puts a narrow no-break space before am/pm; use a plain space.
        "\(timeFormatter.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ").lowercased()) Melbourne time"
    }
    /// "17 Oct 2026, 5:54 am Melbourne time"
    static func dayTime(_ date: Date) -> String { "\(day(date)), \(time(date))" }
}
