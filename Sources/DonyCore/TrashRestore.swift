import Foundation

/// 휴지통으로 옮긴 항목을 원래 위치로 되돌린다. 덮어쓰기 없이, 내 홈 폴더 안에서만 동작한다.
public enum TrashRestore {
    public static func restore(_ record: ActionRecord, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ActionRecord {
        func failed(_ message: String) -> ActionRecord { ActionRecord(kind: "되돌리기", sourcePath: record.sourcePath, trashPath: record.trashPath, bytes: 0, success: false, message: message) }
        do {
            guard record.success, record.kind == "휴지통 이동", let trashPath = record.trashPath else { return failed("되돌릴 수 없는 기록입니다.") }
            let base = try FileSafety.canonicalRoot(home)
            let trash = try FileSafety.canonicalRoot(base.appendingPathComponent(".Trash"))
            let item = URL(fileURLWithPath: trashPath)
            // 휴지통 바로 아래 항목만(링크를 따라가지 않는다).
            guard try FileSafety.canonicalRoot(item.deletingLastPathComponent()).path == trash.path,
                  try FileSafety.metadataIfPresent(item) != nil else { return failed("휴지통에서 항목을 찾지 못했습니다. 이미 비웠거나 옮겼을 수 있어요.") }
            let source = URL(fileURLWithPath: record.sourcePath)
            let parent = try FileSafety.canonicalRoot(source.deletingLastPathComponent())
            guard parent.path == base.path || FileSafety.isWithin(parent, root: base), parent.path != trash.path, !FileSafety.isWithin(parent, root: trash) else { return failed("원래 위치가 안전한 범위 밖입니다.") }
            guard try FileSafety.metadataIfPresent(source) == nil else { return failed("원래 위치에 같은 이름의 항목이 있어 되돌리지 않았어요.") }
            try FileManager.default.moveItem(at: item, to: source)
            return ActionRecord(kind: "되돌리기", sourcePath: record.sourcePath, trashPath: nil, bytes: record.bytes, success: true, message: "원래 위치로 되돌렸습니다.")
        } catch { return failed(error.localizedDescription) }
    }
}
