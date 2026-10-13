import CoreServices
import Foundation

/// Every app bundle Spotlight knows about, wherever it is: other volumes,
/// /Users/Shared, tool caches and folders apps keep their own helpers in.
/// Empty when Spotlight is off or has not indexed the disk, in which case the
/// folders the index searches itself still apply.
enum SpotlightApplications {
    @Sendable
    static func urls() -> [URL] {
        guard let query = MDQueryCreate(kCFAllocatorDefault,
                                        "kMDItemContentType == 'com.apple.application-bundle'" as CFString,
                                        nil, nil) else { return [] }
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        return (0..<MDQueryGetResultCount(query)).compactMap { index in
            guard let pointer = MDQueryGetResultAtIndex(query, index) else { return nil }
            let item = Unmanaged<MDItem>.fromOpaque(pointer).takeUnretainedValue()
            return (MDItemCopyAttribute(item, kMDItemPath) as? String).map { URL(fileURLWithPath: $0) }
        }
    }
}
