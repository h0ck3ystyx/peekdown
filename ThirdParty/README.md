# Experimental native rendering dependencies

Peekdown's own source remains MIT licensed. Dependency code retains its own license.
The exact revisions are recorded in `Package.swift` and `Package.resolved`.

- SwiftMath: MIT; https://github.com/mgriebling/SwiftMath
- BeautifulMermaidSwift: MIT; https://github.com/lukilabs/beautiful-mermaid-swift
- ElkSwift: EPL-2.0; https://github.com/lukilabs/elk-swift

ElkSwift source for the distributed revision is available from its Git repository
at the commit recorded in Package.resolved. SwiftMath is vendored from revision `0b0222e102ba415b352cd29f334075622bd4e6aa`.
Its resource lookup is patched in PeekdownResources.swift and two Bundle lookup
references so signed app extensions can load fonts from Contents/Resources.
The package test target is omitted from the vendored build manifest. Other libraries
are unmodified. These notices ship in the app's Resources/ThirdParty directory.
SwiftMath's font bundle includes its own MIT, OFL, and GUST font license files;
those are preserved with the font resources inside the preview extension.
