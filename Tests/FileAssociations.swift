import AppKit
import CoreServices

// The caller provides an isolated copy with a unique bundle identifier.
let app = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fixture = URL(fileURLWithPath: CommandLine.arguments[2])
let workspace = NSWorkspace.shared
let fixtures = ["md", "markdown", "mdown", "mkd", "mkdn"].map {
    fixture.deletingPathExtension().appendingPathExtension($0)
}
for file in fixtures { try "# Association test\n".write(to: file, atomically: true, encoding: .utf8) }
func handler() -> [String] {
    return fixtures.map { workspace.urlForApplication(toOpen: $0)?.standardizedFileURL.path ?? "<none>" }
}
let before = handler()
print("Before registration: \(before)")
let result = LSRegisterURL(app as CFURL, true)
guard result == noErr else { fatalError("Registration failed: \(result)") }
let registered = handler()
print("After registration:  \(registered)")
let unregister = Process()
unregister.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
unregister.arguments = ["-u", app.path]
try unregister.run()
unregister.waitUntilExit()
guard unregister.terminationStatus == 0 else { fatalError("Unregistration failed") }
let after = handler()
print("After removal:       \(after)")
guard before == registered && before == after else {
    fatalError("Markdown default handler changed")
}
print("Passed registration/removal preservation of the current Markdown handler")
