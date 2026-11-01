// Peekdown integration patch: locate fonts in a signed bundle's Resources folder.
// SwiftMath is MIT licensed; see ../../LICENSE and ThirdParty/README.md.
import Foundation

private final class PeekdownMathResourceAnchor: NSObject {}

extension Bundle {
    static let peekdownMathResources: Bundle = {
        let name = "SwiftMath_SwiftMath.bundle"
        let roots = [Bundle(for: PeekdownMathResourceAnchor.self).resourceURL,
                     Bundle.main.resourceURL, Bundle.main.bundleURL]
        for root in roots.compactMap({ $0 }) {
            if let bundle = Bundle(url: root.appendingPathComponent(name)) { return bundle }
        }
        // The package's own tests / standalone SwiftPM clients retain their normal lookup.
        return Bundle.module
    }()
}
