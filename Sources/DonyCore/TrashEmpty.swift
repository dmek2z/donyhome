import Foundation

public enum TrashEmptyService {
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanToken) -> ScanResult {
        var result = ScanResult()
        if token.isCancelled { result.cancelled = true; return result }
        let root = home.appendingPathComponent(".Trash")
        do {
            guard try FileSafety.metadataIfPresent(root) != nil else { return result }
            let base = try FileSafety.canonicalRoot(home)
            guard try FileSafety.canonicalRoot(root).path == base.appendingPathComponent(".Trash").path else { throw DonyError.unsafePath }
            for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
                do { try token.check(); result.items.append(try FileCandidate.capture(url: url, root: root, kind: .trash, token: token)) }
                catch { if token.isCancelled { result.cancelled = true; break }; result.issues.append(ScanIssue(path: url.path, error: error)) }
            }
        } catch { result.issues.append(ScanIssue(path: root.path, error: error)) }
        return result
    }
    public static func remove(_ item: FileCandidate, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ActionRecord {
        do {
            let root = try FileSafety.canonicalRoot(home).appendingPathComponent(".Trash")
            guard item.kind == .trash, item.root.path == root.path, item.url.deletingLastPathComponent().path == root.path,
                  try FileSafety.canonicalRoot(root).path == root.path else { throw DonyError.unsafePath }
            try FileSafety.validate(item)
            // Native removeItem unlinks nested symlinks, without following their targets.
            try FileManager.default.removeItem(at: item.url)
            return ActionRecord(kind: "휴지통 영구 삭제", sourcePath: item.id, trashPath: nil, bytes: item.bytes, success: true, message: "검사한 휴지통 항목을 영구 삭제했습니다.")
        } catch { return ActionRecord(kind: "휴지통 영구 삭제", sourcePath: item.id, trashPath: nil, bytes: 0, success: false, message: error.localizedDescription) }
    }
}
