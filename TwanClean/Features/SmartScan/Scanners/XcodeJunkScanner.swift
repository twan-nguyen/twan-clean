import Foundation

struct XcodeJunkScanner: CategoryScanner {
    let category = CleanupCategoryID.xcode

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        var builder = CategoryResultBuilder(category, context: context)
        try builder.addChildren(of: context.homeURL("Library/Developer/Xcode/DerivedData"), purpose: .regenerableCache)
        try builder.addChildren(of: context.homeURL("Library/Developer/CoreSimulator/Caches"), purpose: .regenerableCache)
        try builder.add(context.homeURL("Library/Caches/com.apple.dt.Xcode"), purpose: .regenerableCache)
        // Archives hold the symbols needed to read crash reports of shipped
        // builds: listed, never preselected, and only moved to the Trash.
        try builder.addChildren(of: context.homeURL("Library/Developer/Xcode/Archives"), purpose: .buildArchive,
                                selected: false, notes: [.mayBeNeeded])
        return builder.finish()
    }
}
