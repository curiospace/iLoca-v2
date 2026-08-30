import Foundation

// MARK: - This file's job: open the JSON files bundled in the app and turn them into Swift objects.

enum DataLoader {

    /// Loads a JSON file by name (without the .json extension) from the app bundle.
    /// Generic <T> means this one function works for ANY of our data shapes above.
    static func load<T: Decodable>(_ filename: String, as type: T.Type) -> T? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            print("⚠️ Could not find \(filename).json in the app bundle. Did you add it to the project with 'Add to target' checked?")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            print("⚠️ Failed to decode \(filename).json: \(error)")
            return nil
        }
    }

    // Convenience shortcuts for our specific files:

    static func loadAllBlocksSummary() -> BlocksSummary? {
        load("all_blocks_summary_v2", as: BlocksSummary.self)
    }

    static func loadBlock25Detail() -> BlockDetail? {
        load("block25_detailed_v2", as: BlockDetail.self)
    }

    static func loadBlock804Detail() -> BlockDetail? {
        load("block804_detailed", as: BlockDetail.self)
    }
}
