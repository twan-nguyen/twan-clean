import Foundation

struct XcodeJunkScanner: CategoryScanner {
    let category = CleanupCategoryID.xcode

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        var builder = CategoryResultBuilder(category, context: context)
        // Xcode, and the Simulator for its device caches, use these while they run.
        let xcode: Set<String> = ["com.apple.dt.Xcode"]
        let simulator: Set<String> = ["com.apple.dt.Xcode", "com.apple.iphonesimulator"]
        try builder.addChildren(of: context.homeURL("Library/Developer/Xcode/DerivedData"), purpose: .regenerableCache, owners: xcode)
        try builder.addChildren(of: context.homeURL("Library/Developer/CoreSimulator/Caches"), purpose: .regenerableCache, owners: simulator)
        try builder.add(context.homeURL("Library/Caches/com.apple.dt.Xcode"), purpose: .regenerableCache, owners: xcode)
        // Archives hold the symbols needed to read crash reports of shipped
        // builds: listed, never preselected, and only moved to the Trash.
        try builder.addChildren(of: context.homeURL("Library/Developer/Xcode/Archives"), purpose: .buildArchive,
                                selected: false, notes: [.mayBeNeeded])
        return builder.finish()
    }
}
