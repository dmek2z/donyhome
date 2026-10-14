import Foundation

public struct ClutterResult: Sendable {
    public var oldFiles = ScanResult()
    public var installers = ScanResult()
    public init() {}
}
public enum ClutterScanner {
    public static func scan(root: URL, token: ScanToken, now: Date = Date(), progress: Scanner.Progress? = nil) -> ClutterResult {
        let scanned = Scanner.walk(root: root, minimumBytes: 1, kind: .old, token: token, progress: progress)
        var result = ClutterResult()
        result.oldFiles = scanned; result.installers = scanned
        result.oldFiles.items = scanned.items.filter { Double($0.fingerprint.seconds) <= now.addingTimeInterval(-180 * 86400).timeIntervalSince1970 }
        result.installers.items = []
        for item in scanned.items where ["dmg", "pkg", "mpkg", "iso"].contains(item.url.pathExtension.lowercased()) {
            do { try token.check(); result.installers.items.append(try FileCandidate.capture(url: item.url, root: root, kind: .installer, token: token)) }
            catch {
                if token.isCancelled { result.installers.cancelled = true; break }
                result.installers.issues.append(ScanIssue(path: item.id, error: error))
            }
        }
        result.oldFiles.cancelled = result.oldFiles.cancelled || token.isCancelled
        result.installers.cancelled = result.installers.cancelled || token.isCancelled
        return result
    }
}
