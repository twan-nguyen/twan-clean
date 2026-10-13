import Foundation

struct DockerCacheScanner: CategoryScanner {
    let category = CleanupCategoryID.docker

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        var builder = CategoryResultBuilder(category, context: context)
        for path in [
            "Library/Containers/com.docker.docker/Data/cache",
            "Library/Containers/com.docker.docker/Data/log",
            "Library/Containers/com.docker.docker/Data/tmp",
            "Library/Group Containers/group.com.docker/Caches",
        ] {
            try builder.addChildren(of: context.homeURL(path), purpose: .regenerableCache, owners: ["com.docker.docker"])
        }
        // Images, containers and build cache live inside Docker's disk image
        // and only Docker can free them; show the amount so the user knows.
        let reclaimable = await context.commands.output(of: "docker", ["system", "df", "--format", "{{.Reclaimable}}"])
        builder.setDockerReclaimable(reclaimable.flatMap(Self.reclaimableBytes))
        return builder.finish()
    }

    /// Sums lines such as "1.2GB (45%)" from `docker system df`.
    static func reclaimableBytes(_ output: String) -> Int64? {
        let values = output.split(separator: "\n").compactMap { line in
            line.split(separator: " ").first.flatMap { parseSize(String($0)) }
        }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    /// Docker prints decimal units: "512B", "12.5kB", "1.2GB".
    static func parseSize(_ text: String) -> Int64? {
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (suffix, multiplier) in units where text.hasSuffix(suffix) {
            guard let value = Double(text.dropLast(suffix.count)) else { return nil }
            return Int64((value * multiplier).rounded())
        }
        return nil
    }
}
