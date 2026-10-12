import Foundation
@testable import TwanClean

extension FakeHome {
    /// A scan context bound to this fake home that never runs real tools.
    func scanContext(settings: ScanSettings = ScanSettings(), running: Set<String> = [],
                     now: Date = Date()) -> ScanContext {
        ScanContext(home: home, policy: policy, commands: CommandRunner(searchPaths: [], timeout: 1),
                    settings: settings, runningBundleIDs: running, now: now)
    }
}

func makeItem(_ path: String, _ category: CleanupCategoryID, bytes: Int64 = 100) -> CleanableItem {
    CleanableItem(url: URL(fileURLWithPath: path), category: category,
                  identity: FileIdentity(device: 1, inode: UInt64(abs(path.hashValue))), isDirectory: true,
                  bytes: bytes, purpose: .regenerableCache, requiresAdministrator: false,
                  selectedByDefault: true, lastModified: nil, notes: [])
}
