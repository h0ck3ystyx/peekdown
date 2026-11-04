import Foundation

/// Snapshot settings for each new preview; the renderer never reads mutable defaults.
struct PreviewSettings: Equatable {
    static let suiteName = "7ZH96S5LF4.com.markdownpreview.shared"
    static let defaults = PreviewSettings()
    var textScale: Double = 1
    var compact: Bool = false
    var codeLineSpacing: Double = 2
    var diagrams: Bool = false
    var equations: Bool = false
    var metadata: Bool = false

    static var store: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }
    static func load(from store: UserDefaults = store) -> PreviewSettings {
        var result = PreviewSettings()
        if store.object(forKey: "textScale") != nil {
            let value = store.double(forKey: "textScale")
            result.textScale = value.isFinite ? min(1.6, max(0.8, value)) : 1
        }
        result.compact = store.bool(forKey: "compact")
        if store.object(forKey: "codeLineSpacing") != nil {
            let value = store.double(forKey: "codeLineSpacing")
            result.codeLineSpacing = value.isFinite ? min(6, max(0, value)) : 2
        }
        result.diagrams = store.bool(forKey: "diagrams")
        result.metadata = store.bool(forKey: "metadata")
        result.equations = store.bool(forKey: "equations")
        return result
    }
    func save(to store: UserDefaults = store) {
        store.set(textScale, forKey: "textScale")
        store.set(compact, forKey: "compact")
        store.set(codeLineSpacing, forKey: "codeLineSpacing")
        store.set(diagrams, forKey: "diagrams")
        store.set(equations, forKey: "equations")
        store.set(metadata, forKey: "metadata")
    }
}
