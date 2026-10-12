import Foundation

extension Int64 {
    /// A file size such as "1,2 GB", in the user's locale.
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
