import Foundation

public struct RecommendedPlan: Sendable {
    public let items: [FileCandidate]
    public let originals: [String: FileCandidate]
    public var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

public enum RecommendedActions {
    public static func plan(cleanup: [FileCandidate], duplicates: [DuplicateGroup], includeCopies: Bool = true, preserving: [FileCandidate] = []) -> RecommendedPlan {
        let originals = Dictionary(uniqueKeysWithValues: duplicates.flatMap { group in group.copies.map { ($0.id, group.original) } })
        let protected = duplicates.flatMap { [$0.original] + $0.copies } + preserving
        // A chosen scan folder may itself be in Caches. Never recommend its parent
        // for removal while promising to retain a duplicate original inside it.
        let eligible = cleanup.filter { item in
            !protected.contains { participant in item.id == participant.id || FileSafety.isWithin(participant.url, root: item.url) }
        } + (includeCopies ? duplicates.flatMap(\.copies).filter { copy in
            !preserving.contains { retained in copy.id == retained.id || FileSafety.isWithin(retained.url, root: copy.url) }
        } : [])
        var seen = Set<String>()
        let unique = eligible.filter { seen.insert($0.id).inserted }
        let items = unique.filter { item in
            !unique.contains { other in other.id != item.id && other.fingerprint.isDirectory && FileSafety.isWithin(item.url, root: other.url) }
        }
        return RecommendedPlan(items: items, originals: originals)
    }
}
