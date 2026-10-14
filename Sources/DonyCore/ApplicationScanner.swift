import Foundation
import Darwin

public struct InstalledApplication: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let root: URL
    public let name: String
    public let bundleID: String
    public let version: String
}

public struct ApplicationResult: Sendable {
    public var apps: [InstalledApplication] = []
    public var issues: [ScanIssue] = []
    public var cancelled = false
    public init() {}
}

public enum ApplicationScanner {
    public static func inventory(token: ScanToken) -> ApplicationResult {
        var result = ApplicationResult()
        let home = FileManager.default.homeDirectoryForCurrentUser
        for root in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            do {
                guard let metadata = try existingMetadata(root), metadata.isDirectory else { continue }
                _ = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            } catch { result.issues.append(ScanIssue(path: root.path, error: error)); continue }
            guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isPackageKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
                result.issues.append(ScanIssue(path: url.path, error: error)); return true
            }) else { result.issues.append(ScanIssue(path: root.path, message: "이 폴더를 읽을 수 없습니다.")); continue }
            for case let url as URL in iterator {
                if token.isCancelled { result.cancelled = true; return result }
                let values: URLResourceValues
                do { values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isPackageKey]) }
                catch { result.issues.append(ScanIssue(path: url.path, error: error)); iterator.skipDescendants(); continue }
                guard values.isSymbolicLink != true else { iterator.skipDescendants(); continue }
                guard url.pathExtension == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                      !id.hasPrefix("com.apple."), id != "local.dony.DonyClean" else { continue }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
                result.apps.append(InstalledApplication(url: url, root: root, name: name, bundleID: id, version: version))
            }
        }
        result.apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return result
    }

    public static func relatedFiles(bundleID: String, home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanToken) -> ScanResult {
        var result = ScanResult()
        guard bundleID.contains("."), !bundleID.contains("/"), !bundleID.hasPrefix("com.apple."), bundleID != "local.dony.DonyClean" else { return result }
        let folders = ["Caches", "Logs", "Preferences", "Application Support", "Saved Application State", "Containers"]
        for folder in folders {
            if token.isCancelled { result.cancelled = true; break }
            let root = home.appendingPathComponent("Library/" + folder)
            let name = folder == "Preferences" ? bundleID + ".plist" : folder == "Saved Application State" ? bundleID + ".savedState" : bundleID
            let url = root.appendingPathComponent(name)
            do {
                guard try existingMetadata(url) != nil else { continue }
                result.items.append(try FileCandidate.capture(url: url, root: root, kind: .support, token: token))
            }
            catch {
                if token.isCancelled { result.cancelled = true; break }
                result.issues.append(ScanIssue(path: url.path, error: error))
            }
        }
        result.items.sort { $0.bytes > $1.bytes }
        return result
    }

    public static func inspect(_ app: InstalledApplication, token: ScanToken) -> ScanResult {
        var result = relatedFiles(bundleID: app.bundleID, token: token)
        do { result.items.insert(try FileCandidate.capture(url: app.url, root: app.root, kind: .application, token: token), at: 0) }
        catch { result.issues.append(ScanIssue(path: app.url.path, error: error)) }
        result.cancelled = token.isCancelled
        return result
    }
    private static func existingMetadata(_ url: URL) throws -> FileFingerprint? {
        do { return try FileSafety.fingerprint(url) }
        catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) { return nil }
    }
}
