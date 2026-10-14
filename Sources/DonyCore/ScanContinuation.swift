import Foundation

/// A one-shot continuation, recorded before opening Settings because macOS may
/// terminate the app immediately when file permissions change.
public struct ScanContinuation: Codable, Sendable {
    public let folderPath: String
    public let createdAt: Date
    public init(folder: URL, now: Date = Date()) { folderPath = folder.path; createdAt = now }
    public static func save(folder: URL, defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(try? JSONEncoder().encode(Self(folder: folder, now: now)), forKey: "pendingFullScan")
    }
    public static func take(defaults: UserDefaults = .standard, now: Date = Date()) -> URL? {
        guard let data = defaults.data(forKey: "pendingFullScan") else { return nil }
        defaults.removeObject(forKey: "pendingFullScan")
        guard let value = try? JSONDecoder().decode(Self.self, from: data),
              now.timeIntervalSince(value.createdAt) >= 0, now.timeIntervalSince(value.createdAt) < 86400 else { return nil }
        let folder = URL(fileURLWithPath: value.folderPath)
        return FileSafety.allowedRoot(folder, kind: .large) ? folder : nil
    }
    public static func clear(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: "pendingFullScan") }
}

public struct FileAccessReport: Sendable {
    public var checked = 0
    public var issues: [ScanIssue] = []
    public init() {}
    public var deniedPaths: [String] { Array(Set(issues.filter { $0.permissionDenied == true }.map(\.path))).sorted() }
    public static func inspect(paths: [URL], readDirectory: (URL) throws -> Void = { _ = try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }) -> Self {
        var result = Self()
        for path in Set(paths).sorted(by: { $0.path < $1.path }) {
            do { try readDirectory(path); result.checked += 1 }
            catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == 2 { continue }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { continue }
            catch { result.issues.append(ScanIssue(path: path.path, error: error)) }
        }
        return result
    }
}
