import Foundation
import Darwin
import CryptoKit

public enum FileSafety {
    public static func canonicalRoot(_ url: URL) throws -> URL {
        guard let pointer = realpath(url.path, nil) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
        }
        defer { free(pointer) }
        return URL(fileURLWithPath: String(cString: pointer), isDirectory: true)
    }
    public static func fingerprint(_ url: URL) throws -> FileFingerprint {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path]) }
        return FileFingerprint(device: UInt64(value.st_dev), inode: UInt64(value.st_ino), mode: UInt32(value.st_mode), size: Int64(value.st_size), seconds: Int64(value.st_mtimespec.tv_sec), nanoseconds: Int64(value.st_mtimespec.tv_nsec))
    }

    public static func isWithin(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        return path.hasPrefix(base == "/" ? "/" : base + "/") && path != base
    }

    public static func allowedRoot(_ root: URL, kind: CandidateKind) -> Bool {
        let path = ((try? canonicalRoot(root)) ?? root.standardizedFileURL).path.lowercased()
        let home = ((try? canonicalRoot(FileManager.default.homeDirectoryForCurrentUser)) ?? FileManager.default.homeDirectoryForCurrentUser).path.lowercased()
        guard path != "/", path != home else { return false }
        if kind == .application && (path == "/applications" || path == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path.lowercased()) { return true }
        let temporary = ((try? canonicalRoot(FileManager.default.temporaryDirectory)) ?? FileManager.default.temporaryDirectory).path.lowercased()
        if path == temporary || path.hasPrefix(temporary + "/") { return true }
        for protected in ["/system", "/library", "/usr", "/bin", "/sbin", "/private", "/dev", "/applications"] {
            if path == protected || path.hasPrefix(protected + "/") { return false }
        }
        // Home's Library root is too broad, but scoped cache/support directories are permitted.
        let library = home + "/library"
        return path != library
    }

    public static func validate(_ candidate: FileCandidate, token: ScanToken? = nil) throws {
        guard allowedRoot(candidate.root, kind: candidate.kind), isWithin(candidate.url, root: candidate.root) else { throw DonyError.unsafePath }
        for anchor in candidate.anchors {
            let current = try fingerprint(anchor.url)
            guard current.isDirectory, current.sameObject(as: anchor.fingerprint) else { throw DonyError.changed }
        }
        let current = try fingerprint(candidate.url)
        guard current == candidate.fingerprint else { throw DonyError.changed }
        if let stamp = candidate.treeStamp {
            let measured = try FileTree.measure(candidate.url, token: token)
            guard measured.stamp == stamp else { throw DonyError.changed }
        }
    }
}

extension FileCandidate {
    public static func capture(url: URL, root: URL, kind: CandidateKind, token: ScanToken? = nil) throws -> Self {
        let originalRoot = root.standardizedFileURL
        let resolvedRoot = try FileSafety.canonicalRoot(originalRoot)
        guard FileSafety.allowedRoot(resolvedRoot, kind: kind), FileSafety.isWithin(url, root: originalRoot) else { throw DonyError.unsafePath }
        // Resolve the explicitly chosen root's ancestors, never resolve an untrusted child link.
        let relative = String(url.standardizedFileURL.path.dropFirst(originalRoot.path.count + 1))
        // Foundation's standardizedFileURL can shorten an existing /private/var path
        // back to the /var symlink. Keep realpath's canonical spelling for anchors.
        let target = resolvedRoot.appendingPathComponent(relative)
        guard FileSafety.isWithin(target, root: resolvedRoot) else { throw DonyError.unsafePath }
        var anchors: [PathAnchor] = []
        var parent = target.deletingLastPathComponent()
        while true {
            let fp = try FileSafety.fingerprint(parent)
            guard fp.isDirectory else { throw DonyError.unsafePath }
            anchors.append(PathAnchor(url: parent, fingerprint: fp))
            if parent.path == "/" { break }
            parent.deleteLastPathComponent()
        }
        let fp = try FileSafety.fingerprint(target)
        guard fp.isRegular || fp.isDirectory else { throw DonyError.unsafePath }
        let measurement = fp.isDirectory ? try FileTree.measure(target, token: token) : nil
        guard try FileSafety.fingerprint(target) == fp else { throw DonyError.changed }
        return Self(url: target, root: resolvedRoot, kind: kind, fingerprint: fp, anchors: anchors, bytes: measurement?.bytes ?? fp.size, treeStamp: measurement?.stamp)
    }
}

enum FileTree {
    static func measure(_ url: URL, token: ScanToken?) throws -> (bytes: Int64, stamp: String) {
        var issue: Error?
        guard let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in issue = error; return false }) else { throw DonyError.unsupported }
        var bytes: Int64 = 0
        var identities = Set<String>()
        var rows: [String] = []
        for case let child as URL in iterator {
            try token?.check()
            guard rows.count < 100_000 else { throw DonyError.scanLimit }
            let fp = try FileSafety.fingerprint(child)
            rows.append("\(child.path)\t\(fp.identity)\t\(fp.mode)\t\(fp.size)\t\(fp.seconds)\t\(fp.nanoseconds)")
            if !fp.isDirectory { iterator.skipDescendants() }
            if fp.isRegular && identities.insert(fp.identity).inserted { bytes += max(0, fp.size) }
        }
        if let issue { throw issue }
        var hash = SHA256()
        for row in rows.sorted() { hash.update(data: Data((row + "\n").utf8)) }
        return (bytes, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
