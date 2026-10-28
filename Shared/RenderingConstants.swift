import Foundation

/// Shared constants for safe rendering across the Quick Look extensions.
enum RenderingConstants {
    /// Maximum file size (in bytes) that will be rendered.
    /// Files larger than ~10 MB will show a fallback message.
    static let maxFileSize = 10 * 1024 * 1024
}
