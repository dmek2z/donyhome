import Foundation
import CoreServices

public struct LeftoverItem: Identifiable, Sendable {
    public var id: String { candidate.id }
    public let bundleID: String
    public let candidate: FileCandidate
}
public struct LeftoverResult: Sendable {
    public var items: [LeftoverItem] = []
    public var issues: [ScanIssue] = []
    public var cancelled = false
    public init() {}
}
public enum LeftoverScanner {
    public static func registered(_ id: String) -> Bool {
        guard let result = LSCopyApplicationURLsForBundleIdentifier(id as CFString, nil)?.takeRetainedValue() as? [URL] else { return false }
        return result.contains { FileManager.default.fileExists(atPath: $0.path) && Bundle(url: $0)?.bundleIdentifier == id }
    }
    public static func ownerID(_ item: FileCandidate) -> String? {
        let name = item.name
        let id = name.hasSuffix(".plist") ? String(name.dropLast(6)) : name.hasSuffix(".savedState") ? String(name.dropLast(11)) : name
        guard id.range(of: #"^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+){2,}$"#, options: .regularExpression) != nil,
              !id.hasPrefix("com.apple."), id != "local.dony.DonyClean" else { return nil }
        return id
    }
    private static func belongs(_ id: String, to ids: Set<String>) -> Bool {
        ids.contains { id == $0 || id.hasPrefix($0 + ".") || $0.hasPrefix(id + ".") }
    }
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, installedIDs: Set<String>, runningIDs: Set<String>, registered: @Sendable (String) -> Bool = registered, token: ScanToken) -> LeftoverResult {
        var result = LeftoverResult()
        for name in ["Preferences", "Application Support", "Saved Application State", "Containers", "Caches", "Logs"] {
            if token.isCancelled { result.cancelled = true; break }
            let root = home.appendingPathComponent("Library/" + name)
            do {
                guard try FileSafety.metadataIfPresent(root) != nil else { continue }
                let base = try FileSafety.canonicalRoot(home)
                guard try FileSafety.canonicalRoot(root).path == base.appendingPathComponent("Library/" + name).path else { throw DonyError.unsafePath }
                for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
                    try token.check()
                    // Cheap ID filtering precedes potentially expensive directory measurements.
                    let stem = url.lastPathComponent.replacingOccurrences(of: #"\.(plist|savedState)$"#, with: "", options: .regularExpression)
                    guard stem.range(of: #"^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+){2,}$"#, options: .regularExpression) != nil,
                          !stem.hasPrefix("com.apple."), stem != "local.dony.DonyClean",
                          !belongs(stem, to: installedIDs), !belongs(stem, to: runningIDs), !registered(stem) else { continue }
                    do {
                        let candidate = try FileCandidate.capture(url: url, root: root, kind: .support, token: token)
                        if candidate.bytes > 0 { result.items.append(LeftoverItem(bundleID: stem, candidate: candidate)) }
                    } catch { if token.isCancelled { throw error }; result.issues.append(ScanIssue(path: url.path, message: error.localizedDescription)) }
                }
            } catch { if token.isCancelled { result.cancelled = true; break }; result.issues.append(ScanIssue(path: root.path, message: error.localizedDescription)) }
        }
        result.items.sort { $0.id < $1.id }
        return result
    }
    public static func validate(_ item: LeftoverItem, installedIDs: Set<String>, runningIDs: Set<String>, registered: (String) -> Bool = registered) throws {
        guard !belongs(item.bundleID, to: installedIDs), !belongs(item.bundleID, to: runningIDs), !registered(item.bundleID), ownerID(item.candidate) == item.bundleID else { throw DonyError.changed }
        try FileSafety.validate(item.candidate)
    }
}
