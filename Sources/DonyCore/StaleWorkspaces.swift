import Foundation
import Darwin

/// 에이전트(Codex·Claude 등)가 만든 git worktree 중 오래 방치된 것을 찾는다.
/// 추천 조건은 모두 만족해야 한다: git 변경 없음 · 모든 커밋이 원격에 존재 · 보관 기간 이상 활동 없음 · 사용 중인 프로세스 없음.
public enum StaleWorkspaces {
    static let roots = [".codex/worktrees", ".claude/worktrees"]
    /// 생성물이 아닌 무시 파일이 이 크기 이하면 사소한 것으로 본다(휴지통에서 복원 가능).
    static let ignoredLimit: Int64 = 5_000_000
    /// 다시 만들 수 있는 생성물 폴더. 이 밖의 무시된 파일(.env 계열 제외)이 있으면 추천하지 않는다.
    static let regenerable: Set<String> = ["node_modules", ".next", "dist", "build", ".turbo", ".cache", "coverage", ".vercel", ".swc", "target", ".venv", "venv", "__pycache__", ".pnpm-store", ".parcel-cache", ".nuxt", ".svelte-kit", ".gradle", "out", ".DS_Store"]

    public static func workspaceRoots(home: URL) -> [URL] {
        roots.compactMap { path in
            let url = home.appendingPathComponent(path)
            guard (try? FileSafety.metadataIfPresent(url)) != nil, let canonical = try? FileSafety.canonicalRoot(url) else { return nil }
            return canonical
        }
    }
    public static func isWorkspace(_ item: FileCandidate, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        item.kind == .developer && workspaceRoots(home: home).contains { item.url.deletingLastPathComponent().path == $0.path }
    }

    private struct Failure: LocalizedError { let errorDescription: String? }

    private static func git(_ dir: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"; environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(errorDescription: "git 상태를 확인하지 못했습니다.") }
        return String(decoding: data, as: UTF8.self)
    }

    /// 현재 실행 중인 프로세스의 작업 디렉터리 목록. 읽지 못하면 nil(사용 여부를 알 수 없음).
    static func activeDirectories() -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-w", "-d", "cwd", "-Fn"]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { $0.hasPrefix("n/") ? String($0.dropFirst()) : nil }
    }

    static func checkouts(in workspace: URL) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        if fm.fileExists(atPath: workspace.appendingPathComponent(".git").path) { result.append(workspace) }
        let children = (try? fm.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil)) ?? []
        for child in children.sorted(by: { $0.path < $1.path }) where fm.fileExists(atPath: child.appendingPathComponent(".git").path) { result.append(child) }
        return result
    }

    /// 마지막 활동 시각: 작업공간·체크아웃 폴더·git 인덱스·HEAD 로그·최근 커밋 중 가장 늦은 것.
    private static func lastActivity(workspace: URL, checkouts: [URL]) throws -> Date {
        var newest = TimeInterval(try FileSafety.fingerprint(workspace).seconds)
        for checkout in checkouts {
            newest = max(newest, TimeInterval(try FileSafety.fingerprint(checkout).seconds))
            if let text = try? String(contentsOf: checkout.appendingPathComponent(".git"), encoding: .utf8), text.hasPrefix("gitdir:") {
                let gitdir = URL(fileURLWithPath: text.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines))
                for name in ["index", "logs/HEAD", "HEAD"] {
                    if let fp = try? FileSafety.metadataIfPresent(gitdir.appendingPathComponent(name)) { newest = max(newest, TimeInterval(fp.seconds)) }
                }
            }
            if let commit = TimeInterval(try git(checkout, ["log", "-1", "--format=%ct"]).trimmingCharacters(in: .whitespacesAndNewlines)) { newest = max(newest, commit) }
        }
        return Date(timeIntervalSince1970: newest)
    }

    private static func acceptableIgnored(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        if components.contains(where: { regenerable.contains($0) }) { return true }
        guard let last = components.last else { return true }
        return last.hasPrefix(".env") || last.hasSuffix(".log") || last.hasSuffix(".tsbuildinfo")
    }

    /// 작업공간이 안전하게 치울 수 있는 상태인지 판단. 안전하지 않으면 이유를 던진다.
    static func requireSafe(_ workspace: URL, active: [String]?, now: Date, requireOld: Bool, days: Int = 14, token: ScanToken) throws {
        guard (1...3650).contains(days) else { throw DonyError.unsafePath }
        try token.check()
        guard let active else { throw Failure(errorDescription: "사용 중인 프로세스를 확인하지 못했습니다.") }
        let prefix = workspace.path + "/"
        if active.contains(where: { $0 == workspace.path || $0.hasPrefix(prefix) }) { throw Failure(errorDescription: "사용 중 · 실행 중인 프로세스가 이 폴더에 있어요") }
        let found = checkouts(in: workspace)
        guard !found.isEmpty else { throw Failure(errorDescription: "git 작업공간이 아니라 직접 확인이 필요해요") }
        let idle = now.timeIntervalSince(try lastActivity(workspace: workspace, checkouts: found)) / 86400
        if requireOld && idle < Double(days) { throw Failure(errorDescription: "최근 \(Int(idle))일 이내 활동 · 보관") }
        for checkout in found {
            try token.check()
            let status = try git(checkout, ["status", "--porcelain", "--ignored"])
            var otherIgnored: Int64 = 0
            for line in status.split(separator: "\n") {
                if line.hasPrefix("!! ") {
                    let relative = String(line.dropFirst(3))
                    if !acceptableIgnored(relative) { otherIgnored += try diskUsage(checkout.appendingPathComponent(relative), token: token) + 4096 }
                } else { throw Failure(errorDescription: "커밋하지 않은 변경 있음 · 보관") }
            }
            if otherIgnored > ignoredLimit { throw Failure(errorDescription: "무시된 로컬 파일 \(DisplayFormat.bytes(otherIgnored)) 포함 · 직접 확인") }
            let remotes = try git(checkout, ["branch", "-r", "--contains", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if remotes.isEmpty { throw Failure(errorDescription: "원격에 올라가지 않은 커밋 있음 · 보관") }
        }
    }

    /// 용량 합계(하드 링크는 한 번만 계산). 링크는 따라가지 않는다.
    static func diskUsage(_ url: URL, token: ScanToken) throws -> Int64 {
        var single = stat()
        if lstat(url.path, &single) == 0, single.st_mode & S_IFMT != S_IFDIR { return single.st_mode & S_IFMT == S_IFREG ? Int64(single.st_blocks) * 512 : 0 }
        var issue: Error?
        guard let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in issue = error; return true }) else { throw DonyError.unsupported }
        var total: Int64 = 0
        var linked = Set<String>()
        var counter = 0
        for case let child as URL in iterator {
            counter += 1
            if counter % 2000 == 0 { try token.check() }
            var value = stat()
            guard lstat(child.path, &value) == 0, value.st_mode & S_IFMT == S_IFREG else { continue }
            if value.st_nlink > 1, !linked.insert("\(value.st_dev):\(value.st_ino)").inserted { continue }
            total += Int64(value.st_blocks) * 512
        }
        _ = issue
        return total
    }

    static func capture(_ original: URL, root: URL, token: ScanToken) throws -> FileCandidate {
        let resolvedRoot = try FileSafety.canonicalRoot(root)
        guard FileSafety.allowedRoot(resolvedRoot, kind: .developer), FileSafety.isWithin(original, root: root) else { throw DonyError.unsafePath }
        // 사용자가 준 경로의 조상만 정규화하고, 하위 이름은 그대로 쓴다.
        let workspace = resolvedRoot.appendingPathComponent(original.lastPathComponent)
        guard original.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path else { throw DonyError.unsafePath }
        var anchors: [PathAnchor] = []
        var parent = workspace.deletingLastPathComponent()
        while true {
            let fp = try FileSafety.fingerprint(parent)
            guard fp.isDirectory else { throw DonyError.unsafePath }
            anchors.append(PathAnchor(url: parent, fingerprint: fp))
            if parent.path == "/" { break }
            parent.deleteLastPathComponent()
        }
        let fp = try FileSafety.fingerprint(workspace)
        guard fp.isDirectory else { throw DonyError.unsafePath }
        let bytes = try diskUsage(workspace, token: token)
        guard try FileSafety.fingerprint(workspace) == fp else { throw DonyError.changed }
        return FileCandidate(url: workspace, root: resolvedRoot, kind: .developer, fingerprint: fp, anchors: anchors, bytes: bytes, treeStamp: nil)
    }

    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanToken, now: Date = Date(), days: Int = 14) -> DeveloperResult {
        var result = DeveloperResult()
        let rootURLs = workspaceRoots(home: home)
        guard !rootURLs.isEmpty else { return result }
        let active = activeDirectories()
        for root in rootURLs {
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
                result.issues.append(ScanIssue(path: root.path, message: "작업공간 폴더를 읽지 못했습니다.")); continue
            }
            for workspace in children.sorted(by: { $0.path < $1.path }) {
                if token.isCancelled { result.cancelled = true; return result }
                do {
                    guard let fp = try FileSafety.metadataIfPresent(workspace), fp.isDirectory else { continue }
                    let item = try capture(workspace, root: root, token: token)
                    guard item.bytes > 0 else { continue }
                    result.items.append(item)
                    do {
                        try requireSafe(item.url, active: active, now: now, requireOld: true, days: days, token: token)
                        result.decisions[item.id] = CleanupDecision(true, "\(days)일 이상 방치 · 변경·미푸시 없음 · 휴지통에서 복원 가능")
                    } catch { if token.isCancelled { result.cancelled = true; return result }; result.decisions[item.id] = CleanupDecision(false, error.localizedDescription) }
                } catch {
                    if token.isCancelled { result.cancelled = true; return result }
                    result.issues.append(ScanIssue(path: workspace.path, message: error.localizedDescription))
                }
            }
        }
        return result
    }

    public static func validate(_ item: FileCandidate, home: URL = FileManager.default.homeDirectoryForCurrentUser, requireOld: Bool, now: Date = Date(), days: Int = 14, token: ScanToken = ScanToken()) throws {
        guard isWorkspace(item, home: home) else { throw DonyError.unsafePath }
        try FileSafety.validate(item, token: token)
        try requireSafe(item.url, active: activeDirectories(), now: now, requireOld: requireOld, days: days, token: token)
        try FileSafety.validate(item, token: token)
    }
}
