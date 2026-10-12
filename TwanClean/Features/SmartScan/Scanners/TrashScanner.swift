import Foundation

struct TrashScanner: CategoryScanner {
    let category = CleanupCategoryID.trash

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        var builder = CategoryResultBuilder(category, context: context)
        try builder.addChildren(of: context.homeURL(".Trash"), purpose: .trashContents)
        return builder.finish()
    }
}
