import Foundation
import CoreLocation

// MARK: - OpendatasoftClient
// Talks to the City of Melbourne open data portal (Opendatasoft Explore API v2.1).
// Aggregation (counts per block, hourly averages per sensor) runs server-side, so
// the app downloads a few hundred KB instead of the full 400k-row datasets.

enum OpenDataError: LocalizedError {
    case badResponse(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code, let body): return "City of Melbourne API returned \(code): \(body.prefix(200))"
        case .decoding(let what): return "Couldn't read \(what) from the City of Melbourne API."
        }
    }
}

struct OpenDataClient {
    static let base = URL(string: "https://data.melbourne.vic.gov.au/api/explore/v2.1/catalog/datasets")!

    var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Full result set for a query (no 100-row page limit).
    func export(_ dataset: CityDataset, _ params: [String: String]) async throws -> [[String: Any]] {
        let json = try await get(path: "\(dataset.rawValue)/exports/json", params)
        guard let rows = json as? [[String: Any]] else { throw OpenDataError.decoding(dataset.title) }
        return rows
    }

    /// Up to 100 rows, for small lookups.
    func records(_ dataset: CityDataset, _ params: [String: String]) async throws -> [[String: Any]] {
        let json = try await get(path: "\(dataset.rawValue)/records", params)
        guard let dict = json as? [String: Any], let rows = dict["results"] as? [[String: Any]] else {
            throw OpenDataError.decoding(dataset.title)
        }
        return rows
    }

    /// Catalogue metadata: last modified date and licence.
    func info(_ dataset: CityDataset) async throws -> DatasetInfo {
        let json = try await get(path: dataset.rawValue, [:])
        let metas = ((json as? [String: Any])?["metas"] as? [String: Any])?["default"] as? [String: Any]
        let modified = (metas?["modified"] as? String).flatMap(Self.parseDate)
        return DatasetInfo(dataset: dataset, modified: modified, license: metas?["license"] as? String)
    }

    private func get(path: String, _ params: [String: String]) async throws -> Any {
        var components = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        // ODSQL strings contain = ' ( ) which URLComponents leaves unescaped; encode strictly.
        components.percentEncodedQuery = params
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(Self.encode($0.value))" }
            .joined(separator: "&")
        let (data, response) = try await session.data(from: components.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw OpenDataError.badResponse(status, String(decoding: data, as: UTF8.self))
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "Australia/Melbourne")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: String(string.prefix(10)))
    }

    /// ODSQL date literal, e.g. date'2026-10-15'.
    static func odsqlDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Australia/Melbourne")
        f.dateFormat = "yyyy-MM-dd"
        return "date'\(f.string(from: date))'"
    }
}

// MARK: - Building the city snapshot

extension OpenDataClient {

    /// Nearest-sensor match radius. Beyond this a block has no footfall reading.
    static let sensorMatchRadius: Double = 200
    /// Days of pedestrian counts averaged into each hourly profile.
    static let footfallWindowDays = 28

    func fetchSnapshot() async throws -> CitySnapshot {
        async let yearTask = latestCensusYear()
        async let blocksTask = export(.blocks, ["select": "block_id,area_name,geo_point_2d"])
        async let sensorsTask = fetchSensors()
        async let infoTask = fetchDatasetInfo()
        async let offStreetTask = fetchOffStreetParking()

        let year = try await yearTask
        let yearFilter = "census_year=date'\(year)'"

        async let industryTask = export(.industryPerBlock, ["where": yearFilter])
        async let premisesTask = export(.establishments, [
            "select": "block_id,count(*) as n",
            "where": yearFilter,
            "group_by": "block_id"
        ])
        async let vacantTask = export(.establishments, [
            "select": "block_id,count(*) as n",
            "where": "\(yearFilter) and industry_anzsic4_code='0000'",
            "group_by": "block_id"
        ])

        let (blockRows, industryRows, premisesRows, vacantRows) = try await (blocksTask, industryTask, premisesTask, vacantTask)
        let (sensors, windowStart, windowEnd) = try await sensorsTask
        let datasets = await infoTask
        // Parking is supplementary: if it fails, the rest of the app still works.
        let offStreet = try? await offStreetTask

        let premises = Self.countsByBlock(premisesRows)
        let vacant = Self.countsByBlock(vacantRows)
        var industryByBlock: [Int: [String: Any]] = [:]
        for row in industryRows {
            if let id = Self.int(row["block_id"]) { industryByBlock[id] = row }
        }

        let countedSensors = sensors.filter(\.hasCounts)
        var blocks: [CityBlock] = []
        for row in blockRows {
            guard let id = Self.int(row["block_id"]),
                  let point = row["geo_point_2d"] as? [String: Any],
                  let lat = point["lat"] as? Double, let lon = point["lon"] as? Double else { continue }

            let industry = industryByBlock[id] ?? [:]
            let total = premises[id] ?? 0
            let active = Self.int(industry["total_establishments_in_block"]) ?? max(0, total - (vacant[id] ?? 0))
            // Skip parks, roads and other blocks with no commercial premises at all.
            guard total > 0 || active > 0 else { continue }

            var mix: [String: Int] = [:]
            for (key, value) in industry {
                guard !Self.nonIndustryKeys.contains(key), let n = Self.int(value), n > 0 else { continue }
                mix[Self.prettyIndustry(key)] = n
            }

            let centroid = (lat: lat, lon: lon)
            let nearest = countedSensors
                .map { ($0, haversineMetres(.init(latitude: centroid.lat, longitude: centroid.lon), $0.coordinate)) }
                .min { $0.1 < $1.1 }
            let matched = nearest.flatMap { $0.1 <= Self.sensorMatchRadius ? $0 : nil }

            blocks.append(CityBlock(
                blockId: id,
                area: (row["area_name"] as? String) ?? (industry["clue_small_area"] as? String) ?? "Melbourne",
                centroidLat: lat,
                centroidLon: lon,
                fnbCount: Self.int(industry["food_and_beverage_services"]) ?? 0,
                retailCount: Self.int(industry["retail_trade"]) ?? 0,
                activeEstablishments: active,
                totalPremises: max(total, active),
                vacantPremises: vacant[id] ?? 0,
                industryMix: mix,
                sensorId: matched?.0.locationId,
                sensorDistanceMetres: matched?.1
            ))
        }

        return CitySnapshot(
            censusYear: year,
            blocks: blocks.sorted { $0.blockId < $1.blockId },
            sensors: sensors,
            datasets: datasets,
            footfallWindowStart: windowStart,
            footfallWindowEnd: windowEnd,
            offStreet: offStreet,
            fetchedAt: Date()
        )
    }

    /// Every premises record (businesses and vacancies) in one block, for the detail panel.
    func fetchPremises(blockId: Int, censusYear: Int) async throws -> [BusinessRecord] {
        let rows = try await export(.establishments, [
            "select": "trading_name,business_address,industry_anzsic4_code,industry_anzsic4_description,latitude,longitude",
            "where": "census_year=date'\(censusYear)' and block_id=\(blockId)",
            "order_by": "trading_name"
        ])
        return rows.map { row in
            BusinessRecord(
                name: (row["trading_name"] as? String) ?? "Unnamed",
                address: (row["business_address"] as? String) ?? "",
                anzsicCode: (row["industry_anzsic4_code"] as? String) ?? "",
                industry: (row["industry_anzsic4_description"] as? String) ?? "Unknown",
                latitude: row["latitude"] as? Double,
                longitude: row["longitude"] as? Double
            )
        }
    }

    // MARK: Parking

    /// Public (commercial) car parks as points, plus private spaces per block, from the
    /// latest off-street parking census.
    func fetchOffStreetParking() async throws -> OffStreetParking {
        let yearRows = try await records(.offStreetParking, [
            "select": "census_year", "group_by": "census_year", "order_by": "census_year desc", "limit": "1"
        ])
        guard let raw = yearRows.first?["census_year"] as? String, let year = Int(raw.prefix(4)) else {
            throw OpenDataError.decoding("the off-street parking census year")
        }
        async let commercialTask = export(.offStreetParking, [
            "select": "building_address,parking_spaces,latitude,longitude,block_id",
            "where": "census_year=date'\(year)' and parking_type='Commercial'"
        ])
        async let privateTask = export(.offStreetParking, [
            "select": "block_id,sum(parking_spaces) as n",
            "where": "census_year=date'\(year)' and parking_type='Private'",
            "group_by": "block_id"
        ])
        let (commercialRows, privateRows) = try await (commercialTask, privateTask)
        let carParks: [CarPark] = commercialRows.compactMap { row in
            guard let lat = row["latitude"] as? Double, let lon = row["longitude"] as? Double,
                  let spaces = Self.int(row["parking_spaces"]), spaces > 0 else { return nil }
            return CarPark(address: (row["building_address"] as? String) ?? "Car park", spaces: spaces,
                           latitude: lat, longitude: lon, blockId: Self.int(row["block_id"]))
        }
        return OffStreetParking(censusYear: year, carParks: carParks, privateSpacesByBlock: Self.countsByBlock(privateRows))
    }

    /// Bays whose sensor has reported in the last 24 hours (older rows are offline sensors).
    func fetchOnStreetParking() async throws -> OnStreetParking {
        let rows = try await export(.onStreetParking, [
            "select": "kerbsideid,status_description,status_timestamp,lastupdated,location",
            "where": "lastupdated>=now(days=-1)"
        ])
        var latest: Date?
        let bays: [ParkingBay] = rows.compactMap { row in
            guard let id = Self.int(row["kerbsideid"]),
                  let point = row["location"] as? [String: Any],
                  let lat = point["lat"] as? Double, let lon = point["lon"] as? Double,
                  let status = row["status_description"] as? String else { return nil }
            if let updated = (row["lastupdated"] as? String).flatMap(Self.parseDate), updated > (latest ?? .distantPast) {
                latest = updated
            }
            return ParkingBay(kerbsideId: id, latitude: lat, longitude: lon,
                              isOccupied: status == "Present",
                              since: (row["status_timestamp"] as? String).flatMap(Self.parseDate))
        }
        // The feed can list a bay twice; keep one row per bay.
        var seen = Set<Int>()
        return OnStreetParking(bays: bays.filter { seen.insert($0.kerbsideId).inserted }, fetchedAt: Date(), latestReport: latest)
    }

    // MARK: Pieces

    private func latestCensusYear() async throws -> Int {
        let rows = try await records(.industryPerBlock, [
            "select": "census_year",
            "group_by": "census_year",
            "order_by": "census_year desc",
            "limit": "1"
        ])
        guard let raw = rows.first?["census_year"] as? String, let year = Int(raw.prefix(4)) else {
            throw OpenDataError.decoding("the latest census year")
        }
        return year
    }

    private func fetchDatasetInfo() async -> [DatasetInfo] {
        await withTaskGroup(of: DatasetInfo?.self) { group in
            for dataset in CityDataset.allCases {
                group.addTask { try? await self.info(dataset) }
            }
            var result: [DatasetInfo] = []
            for await info in group { if let info { result.append(info) } }
            return result.sorted { $0.dataset.rawValue < $1.dataset.rawValue }
        }
    }

    /// Active sensors plus their average hourly counts over the last 28 complete days,
    /// split into weekday and weekend profiles.
    private func fetchSensors() async throws -> ([PedestrianSensor], Date?, Date?) {
        async let locationsTask = export(.sensorLocations, [
            "select": "location_id,sensor_name,sensor_description,status,latitude,longitude"
        ])
        let latestRows = try await records(.pedestrianCounts, [
            "select": "sensing_date",
            "order_by": "sensing_date desc",
            "limit": "1"
        ])
        let locations = try await locationsTask

        var sensors: [Int: PedestrianSensor] = [:]
        for row in locations where (row["status"] as? String) == "A" {
            guard let id = Self.int(row["location_id"]),
                  let lat = row["latitude"] as? Double, let lon = row["longitude"] as? Double else { continue }
            sensors[id] = PedestrianSensor(
                locationId: id,
                name: (row["sensor_name"] as? String) ?? "Sensor \(id)",
                description: (row["sensor_description"] as? String) ?? "",
                latitude: lat, longitude: lon,
                weekdayHourly: Array(repeating: nil, count: 24),
                weekendHourly: Array(repeating: nil, count: 24)
            )
        }

        guard let latestRaw = latestRows.first?["sensing_date"] as? String,
              let latest = Self.parseDate(latestRaw) else {
            return (Array(sensors.values), nil, nil)
        }

        // The newest day is usually still being counted, so end the window the day before.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        let end = calendar.date(byAdding: .day, value: -1, to: latest)!
        let days = (0..<Self.footfallWindowDays).compactMap { calendar.date(byAdding: .day, value: -$0, to: end) }
        let weekendDays = days.filter { calendar.isDateInWeekend($0) }
        let weekdayDays = days.filter { !calendar.isDateInWeekend($0) }

        async let weekdayTask = hourlyAverages(on: weekdayDays)
        async let weekendTask = hourlyAverages(on: weekendDays)
        let (weekday, weekend) = try await (weekdayTask, weekendTask)

        for (key, value) in weekday where sensors[key.sensor] != nil {
            sensors[key.sensor]!.weekdayHourly[key.hour] = value
        }
        for (key, value) in weekend where sensors[key.sensor] != nil {
            sensors[key.sensor]!.weekendHourly[key.hour] = value
        }
        return (sensors.values.sorted { $0.locationId < $1.locationId }, days.last, end)
    }

    private nonisolated struct SensorHour: Hashable { let sensor: Int; let hour: Int }

    private func hourlyAverages(on days: [Date]) async throws -> [SensorHour: Double] {
        guard !days.isEmpty else { return [:] }
        let dateClause = days.map { "sensing_date=\(Self.odsqlDate($0))" }.joined(separator: " or ")
        let rows = try await export(.pedestrianCounts, [
            "select": "location_id,hourday,avg(pedestriancount) as avg",
            "where": dateClause,
            "group_by": "location_id,hourday"
        ])
        var result: [SensorHour: Double] = [:]
        for row in rows {
            guard let sensor = Self.int(row["location_id"]), let hour = Self.int(row["hourday"]),
                  (0..<24).contains(hour), let avg = row["avg"] as? Double else { continue }
            result[SensorHour(sensor: sensor, hour: hour)] = avg
        }
        return result
    }

    // MARK: Helpers

    private static let nonIndustryKeys: Set<String> = ["census_year", "block_id", "clue_small_area", "total_establishments_in_block"]

    private static func prettyIndustry(_ key: String) -> String {
        key.replacingOccurrences(of: "_and_", with: " & ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private static func countsByBlock(_ rows: [[String: Any]]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for row in rows {
            if let id = int(row["block_id"]), let n = int(row["n"]) { result[id] = n }
        }
        return result
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let v as Int: return v
        case let v as Double: return Int(v)
        case let v as String: return Int(v)
        default: return nil
        }
    }
}
