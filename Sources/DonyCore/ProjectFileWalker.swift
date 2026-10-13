import Foundation
import Darwin

/// Metadata-only traversal. Never opens symlinks, FIFO files or file contents.
public enum ProjectFileWalker {
    public static func walk(root: URL, token: ScanToken, limit: Int = 100_000, timeout: TimeInterval = 10, shouldDescend: (URL) -> Bool = { _ in true }, visit: (URL, FileFingerprint) throws -> Void) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var folders = [root]
        var count = 0
        while let folder = folders.popLast() {
            try token.check()
            guard Date() < deadline else { throw DonyError.scanLimit }
            let descriptor = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            guard let directory = fdopendir(descriptor) else { let code = errno; close(descriptor); throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
            defer { closedir(directory) }
            errno = 0
            while let pointer = readdir(directory) {
                try token.check()
                guard Date() < deadline else { throw DonyError.scanLimit }
                let name = withUnsafePointer(to: pointer.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(pointer.pointee.d_namlen) + 1) { String(cString: $0) } }
                if name == "." || name == ".." { continue }
                count += 1; guard count <= limit else { throw DonyError.scanLimit }
                let file = folder.appendingPathComponent(name)
                let stamp = try FileSafety.fingerprint(file)
                try visit(file, stamp)
                if stamp.isDirectory && shouldDescend(file) { folders.append(file) }
                errno = 0
            }
            if errno != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
    }
}
