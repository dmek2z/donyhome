import Foundation

public struct RecommendedPlan: Sendable {
    public let items: [FileCandidate]
    public let originals: [String: FileCandidate]
    public var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

public enum RecommendedActions {
    public static func plan(cleanup: [FileCandidate], duplicates: [DuplicateGroup], includeCopies: Bool = true, preserving: [FileCandidate] = []) -> RecommendedPlan {
        let originals = Dictionary(uniqueKeysWithValues: duplicates.flatMap { group in group.copies.map { ($0.id, group.original) } })
        // Index retained leaves and all of their ancestors once. Only directory
        // candidates can contain another path; regular files need exact lookup.
        func retainedIndex(_ candidates: [FileCandidate]) -> Set<String> {
            var index = Set<String>()
            for candidate in candidates {
                var path = candidate.url
                while true {
                    index.insert(path.path)
                    let parent = path.deletingLastPathComponent()
                    if parent.path == path.path { break }
                    path = parent
                }
            }
            return index
        }
        let protected = retainedIndex(duplicates.flatMap { [$0.original] + $0.copies } + preserving)
        let preserved = retainedIndex(preserving)
        let eligible = cleanup.filter { !protected.contains($0.id) } +
            (includeCopies ? duplicates.flatMap(\.copies).filter { !preserved.contains($0.id) } : [])
        var seen = Set<String>()
        let unique = eligible.filter { seen.insert($0.id).inserted }
        let directories = Set(unique.filter { $0.fingerprint.isDirectory }.map(\.id))
        let items = unique.filter { item in
            guard !directories.isEmpty else { return true }
            var parent = item.url.deletingLastPathComponent()
            while true {
                if directories.contains(parent.path) { return false }
                let next = parent.deletingLastPathComponent()
                if next.path == parent.path { return true }
                parent = next
            }
        }
        return RecommendedPlan(items: items, originals: originals)
    }
}
