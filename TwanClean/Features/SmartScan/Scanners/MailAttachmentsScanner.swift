import Foundation

struct MailAttachmentsScanner: CategoryScanner {
    let category = CleanupCategoryID.mail

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        var builder = CategoryResultBuilder(category, context: context)
        for path in ["Library/Mail Downloads", "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"] {
            try builder.addChildren(of: context.homeURL(path), purpose: .regenerableCache)
        }
        return builder.finish()
    }
}
