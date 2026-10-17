import Foundation
import Observation

/// Per-block values that depend on the current filters.
struct BlockMetrics {
    let footfall: Double?
    let footfallTier: FootfallLevel?
    let score: OpportunityScore
    /// Competitors (per the Competitor Type filter) within the search radius, this block included.
    let competitorsInRadius: Int
    let competitionBand: CompetitionPreference
}

/// Parking around one block, within the current search radius.
struct ParkingSummary {
    /// Public car parks, nearest first.
    let carParks: [(carPark: CarPark, distance: Double)]
    let publicSpaces: Int
    let privateSpacesInBlock: Int
    let bayCount: Int
    let freeBays: Int
    var occupiedBays: Int { bayCount - freeBays }
    var freeShare: Double? { bayCount > 0 ? Double(freeBays) / Double(bayCount) : nil }
}

/// App-wide source of truth for city data, the current selection and the map
/// filters. Shared by the Map, Info and report features so they always agree.
@Observable
final class CityDataStore {
    private(set) var snapshot: CitySnapshot?
    private(set) var source: DataSourceState = .loading
    let filters = MapFilterState()
    var selectedBlockId: Int?

    private(set) var premisesByBlock: [Int: [BusinessRecord]] = [:]
    private(set) var premisesLoading: Set<Int> = []
    private(set) var premisesErrors: [Int: String] = [:]

    /// Live on-street bays (dataset 6), refreshed separately from the snapshot.
    private(set) var onStreet: OnStreetParking?
    private(set) var onStreetError: String?
    private(set) var onStreetLoading = false
    static let onStreetRefreshInterval: TimeInterval = 300

    @ObservationIgnored private let client = OpenDataClient()
    @ObservationIgnored private var sensorsById: [Int: PedestrianSensor] = [:]
    @ObservationIgnored private var blockIndex: [Int: Int] = [:]
    @ObservationIgnored private var neighbourCache: [Int: [Int: [Int]]] = [:]   // radius -> blockId -> neighbour indices
    @ObservationIgnored private var metricsCache: (key: MetricsKey, values: [Int: BlockMetrics])?
    @ObservationIgnored private var confidenceCache: (key: String, values: [Int: ConfidenceAssessment])?
    @ObservationIgnored private var bayOccupancyCache: (key: Date, values: [Int: (free: Int, total: Int)])?

    // MARK: - Accessors

    var blocks: [CityBlock] { snapshot?.blocks ?? [] }
    var censusYear: Int { snapshot?.censusYear ?? 0 }
    var sensors: [PedestrianSensor] { snapshot?.sensors.filter(\.hasCounts) ?? [] }
    var areas: [String] { Array(Set(blocks.map(\.area))).sorted() }

    var selectedBlock: CityBlock? {
        guard let id = selectedBlockId, let i = blockIndex[id] else { return nil }
        return blocks[i]
    }

    func block(id: Int) -> CityBlock? { blockIndex[id].map { blocks[$0] } }
    func sensor(for block: CityBlock) -> PedestrianSensor? { block.sensorId.flatMap { sensorsById[$0] } }
    func datasetInfo(_ dataset: CityDataset) -> DatasetInfo? { snapshot?.datasets.first { $0.dataset == dataset } }

    // MARK: - Loading

    func load() async {
        if snapshot == nil, let cached = Self.readCache() {
            apply(cached)
            source = .cached(cached.fetchedAt, reason: "refreshing")
        }
        do {
            let live = try await client.fetchSnapshot()
            apply(live)
            source = .live(live.fetchedAt)
            Self.writeCache(live)
        } catch {
            if let snapshot {
                source = .cached(snapshot.fetchedAt, reason: "live fetch failed: \(error.localizedDescription)")
            } else {
                source = .unavailable(error.localizedDescription)
            }
        }
    }

    func loadPremises(for blockId: Int) async {
        guard premisesByBlock[blockId] == nil, !premisesLoading.contains(blockId), censusYear > 0 else { return }
        premisesLoading.insert(blockId)
        defer { premisesLoading.remove(blockId) }
        do {
            premisesByBlock[blockId] = try await client.fetchPremises(blockId: blockId, censusYear: censusYear)
            premisesErrors[blockId] = nil
        } catch {
            premisesErrors[blockId] = error.localizedDescription
        }
    }

    private func apply(_ snapshot: CitySnapshot) {
        self.snapshot = snapshot
        sensorsById = Dictionary(uniqueKeysWithValues: snapshot.sensors.map { ($0.locationId, $0) })
        blockIndex = Dictionary(uniqueKeysWithValues: snapshot.blocks.enumerated().map { ($1.blockId, $0) })
        neighbourCache = [:]
        metricsCache = nil
        confidenceCache = nil
    }

    // MARK: - Parking

    var carParks: [CarPark] { snapshot?.offStreet?.carParks ?? [] }

    /// Fetches live bay status if it's missing or older than the refresh interval.
    func refreshOnStreetIfStale() async {
        if let fetched = onStreet?.fetchedAt, Date().timeIntervalSince(fetched) < Self.onStreetRefreshInterval - 5 { return }
        guard !onStreetLoading else { return }
        onStreetLoading = true
        defer { onStreetLoading = false }
        do {
            onStreet = try await client.fetchOnStreetParking()
            onStreetError = nil
        } catch {
            onStreetError = error.localizedDescription
        }
    }

    func parking(for block: CityBlock) -> ParkingSummary {
        let radius = Double(filters.searchRadius.rawValue)
        let parks = carParks
            .map { ($0, haversineMetres(block.coordinate, $0.coordinate)) }
            .filter { $0.1 <= radius }
            .sorted { $0.1 < $1.1 }
        let bays = (onStreet?.bays ?? []).filter { haversineMetres(block.coordinate, $0.coordinate) <= radius }
        return ParkingSummary(
            carParks: parks.map { (carPark: $0.0, distance: $0.1) },
            publicSpaces: parks.map(\.0.spaces).reduce(0, +),
            privateSpacesInBlock: snapshot?.offStreet?.privateSpacesByBlock[block.blockId] ?? 0,
            bayCount: bays.count,
            freeBays: bays.filter { !$0.isOccupied }.count
        )
    }

    /// Bays in the selected block's search radius, for drawing individually.
    func bays(around block: CityBlock) -> [ParkingBay] {
        let radius = Double(filters.searchRadius.rawValue)
        return (onStreet?.bays ?? []).filter { haversineMetres(block.coordinate, $0.coordinate) <= radius }
    }

    /// Live bays grouped onto their nearest block (within 150 m), for the city-wide overlay.
    func bayOccupancyByBlock() -> [Int: (free: Int, total: Int)] {
        guard let onStreet else { return [:] }
        if let cache = bayOccupancyCache, cache.key == onStreet.fetchedAt { return cache.values }
        let blocks = self.blocks
        var result: [Int: (free: Int, total: Int)] = [:]
        let metresPerDegLat = 111_320.0, metresPerDegLon = 111_320.0 * cos(37.81 * .pi / 180)
        for bay in onStreet.bays {
            var best: (id: Int, d2: Double)?
            for b in blocks {
                let dy = (b.centroidLat - bay.latitude) * metresPerDegLat
                let dx = (b.centroidLon - bay.longitude) * metresPerDegLon
                let d2 = dx * dx + dy * dy
                if d2 < (best?.d2 ?? 150 * 150) { best = (b.blockId, d2) }
            }
            guard let id = best?.id else { continue }
            var entry = result[id] ?? (0, 0)
            entry.total += 1
            if !bay.isOccupied { entry.free += 1 }
            result[id] = entry
        }
        bayOccupancyCache = (onStreet.fetchedAt, result)
        return result
    }

    // MARK: - Foot traffic

    /// Hourly profile at the block's sensor for one day type (index = hour).
    func hourlyProfile(for block: CityBlock, dayType: DayType) -> [Double?]? {
        guard let sensor = sensor(for: block) else { return nil }
        return dayType == .weekday ? sensor.weekdayHourly : sensor.weekendHourly
    }

    /// Average people per hour across the hours and day types selected in the filters.
    func footfall(for block: CityBlock) -> Double? {
        guard let sensor = sensor(for: block) else { return nil }
        return Self.footfall(sensor: sensor, hours: filters.selectedHours, dayTypes: filters.dayTypes)
    }

    static func footfall(sensor: PedestrianSensor, hours: [Int], dayTypes: Set<DayType>) -> Double? {
        let wantWeekday = dayTypes.isEmpty || dayTypes.contains(.weekday)
        let wantWeekend = dayTypes.isEmpty || dayTypes.contains(.weekend)
        let values: [Double] = hours.compactMap { h in
            let wd = wantWeekday ? sensor.weekdayHourly[h] : nil
            let we = wantWeekend ? sensor.weekendHourly[h] : nil
            switch (wd, we) {
            case let (a?, b?): return (a * 5 + b * 2) / 7   // a typical week has 5 weekdays, 2 weekend days
            case let (a?, nil): return a
            case let (nil, b?): return b
            default: return nil
            }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Metrics (score, footfall tier, competition), cached per filter state

    private struct MetricsKey: Equatable {
        let fetchedAt: Date?
        let hours: [Int]
        let dayTypes: Set<DayType>
        let category: BusinessCategory?
        let competitorType: CompetitorType
        let radius: SearchRadius
    }

    func metrics(for block: CityBlock) -> BlockMetrics? {
        allMetrics()[block.blockId]
    }

    func score(for block: CityBlock) -> OpportunityScore? { metrics(for: block)?.score }

    private func allMetrics() -> [Int: BlockMetrics] {
        let key = MetricsKey(
            fetchedAt: snapshot?.fetchedAt,
            hours: filters.selectedHours,
            dayTypes: filters.dayTypes,
            category: filters.businessCategory,
            competitorType: filters.competitorType,
            radius: filters.searchRadius
        )
        if let cache = metricsCache, cache.key == key { return cache.values }

        let blocks = self.blocks
        let footfalls = blocks.map { footfall(for: $0) }
        let measured = footfalls.compactMap { $0 }.sorted()
        let footfallRef = Self.percentile(measured, 0.9) ?? 1
        let quartiles = (Self.percentile(measured, 0.25) ?? 0, Self.percentile(measured, 0.5) ?? 0, Self.percentile(measured, 0.75) ?? 0)
        let densityRef = Self.percentile(blocks.map { Double($0.activeEstablishments) }.sorted(), 0.95) ?? 1

        let neighbours = neighbourIndices(radius: Double(key.radius.rawValue))
        let competitors: [Int] = blocks.map { block in
            (neighbours[block.blockId] ?? []).reduce(0) { $0 + competitorCount(in: blocks[$1], category: key.category, type: key.competitorType) }
        }
        let sortedCompetitors = competitors.map(Double.init).sorted()
        let lowCut = Self.percentile(sortedCompetitors, 1.0 / 3) ?? 0
        let highCut = Self.percentile(sortedCompetitors, 2.0 / 3) ?? 0
        let windowLabel = filters.timeWindowLabel

        var values: [Int: BlockMetrics] = [:]
        for (i, block) in blocks.enumerated() {
            let ff = footfalls[i]
            let tier: FootfallLevel? = ff.map { v in
                v < quartiles.0 ? .low : v < quartiles.1 ? .medium : v < quartiles.2 ? .high : .veryHigh
            }
            let c = Double(competitors[i])
            let band: CompetitionPreference = c < lowCut ? .low : c > highCut ? .established : .balanced
            values[block.blockId] = BlockMetrics(
                footfall: ff,
                footfallTier: tier,
                score: .compute(block: block, footfall: ff, footfallReference: footfallRef,
                                 densityReference: densityRef, timeWindowLabel: windowLabel),
                competitorsInRadius: competitors[i],
                competitionBand: band
            )
        }
        metricsCache = (key, values)
        return values
    }

    func competitorCount(in block: CityBlock, category: BusinessCategory?, type: CompetitorType) -> Int {
        switch type {
        case .all: return block.activeEstablishments
        case .direct: return block.count(for: category)
        case .indirect: return category == nil ? block.activeEstablishments : block.activeEstablishments - block.count(for: category)
        }
    }

    /// Blocks within the search radius of `block` (excluding itself) that have competitors.
    func competitorBlocks(around block: CityBlock) -> [(block: CityBlock, count: Int)] {
        let neighbours = neighbourIndices(radius: Double(filters.searchRadius.rawValue))[block.blockId] ?? []
        return neighbours.compactMap { i in
            let other = blocks[i]
            guard other.blockId != block.blockId else { return nil }
            let n = competitorCount(in: other, category: filters.businessCategory, type: filters.competitorType)
            return n > 0 ? (other, n) : nil
        }
    }

    private func neighbourIndices(radius: Double) -> [Int: [Int]] {
        let key = Int(radius)
        if let cached = neighbourCache[key] { return cached }
        let blocks = self.blocks
        var result: [Int: [Int]] = [:]
        for (i, a) in blocks.enumerated() {
            result[a.blockId] = blocks.indices.filter { j in
                i == j || haversineMetres(a.coordinate, blocks[j].coordinate) <= radius
            }
        }
        neighbourCache[key] = result
        return result
    }

    // MARK: - Filtering

    var visibleBlocks: [CityBlock] {
        let metrics = allMetrics()
        return blocks.filter { block in
            if let area = filters.area, block.area != area { return false }
            if filters.footfallLevel != .any {
                // Blocks without a sensor have unknown foot traffic, so they can't match a level.
                guard metrics[block.blockId]?.footfallTier == filters.footfallLevel else { return false }
            }
            if filters.competitionPreference != .any,
               metrics[block.blockId]?.competitionBand != filters.competitionPreference { return false }
            return true
        }
    }

    // MARK: - Confidence

    func confidence(for block: CityBlock) -> ConfidenceAssessment {
        let key = "\(snapshot?.fetchedAt.timeIntervalSince1970 ?? 0)|\(source)"
        if confidenceCache?.key != key {
            var values: [Int: ConfidenceAssessment] = [:]
            for b in blocks {
                values[b.blockId] = ConfidenceAssessment.assess(
                    block: b, censusYear: censusYear,
                    footfallWindowEnd: snapshot?.footfallWindowEnd, source: source)
            }
            confidenceCache = (key, values)
        }
        return confidenceCache?.values[block.blockId]
            ?? ConfidenceAssessment.assess(block: block, censusYear: censusYear,
                                           footfallWindowEnd: snapshot?.footfallWindowEnd, source: source)
    }

    // MARK: - Freshness

    var freshnessLine: String {
        var parts: [String] = []
        if censusYear > 0 { parts.append("Businesses: \(censusYear) census") }
        if let end = snapshot?.footfallWindowEnd {
            parts.append("Foot traffic: to \(MelbourneTime.shortDay(end))")
        }
        if let report = onStreet?.latestReport {
            parts.append("Parking: \(MelbourneTime.time(report))")
        }
        switch source {
        case .live(let at): parts.append("Live · \(at.formatted(date: .omitted, time: .shortened))")
        case .cached(let at, _): parts.append("Offline copy · \(at.formatted(.relative(presentation: .named)))")
        case .loading: parts.append("Loading…")
        case .unavailable: parts.append("Data unavailable")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Helpers

    static func percentile(_ sorted: [Double], _ p: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let rank = p * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down)), hi = Int(rank.rounded(.up))
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - Double(lo))
    }

    // MARK: - Offline cache (last successful live fetch)

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("iLoca", isDirectory: true)
            .appendingPathComponent("city_snapshot.json")
    }

    private static func readCache() -> CitySnapshot? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CitySnapshot.self, from: data)
    }

    private static func writeCache(_ snapshot: CitySnapshot) {
        guard let url = cacheURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
