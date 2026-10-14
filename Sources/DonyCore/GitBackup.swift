import Foundation

public struct GitBackupReport: Codable, Sendable {
    public let verified: Bool
    public let reason: String
    public init(_ verified: Bool, _ reason: String) { self.verified = verified; self.reason = reason }
}

public enum GitBackup {
    public static func check(root: URL, run: (([String]) throws -> String)? = nil) -> GitBackupReport {
        let command: ([String]) throws -> String = run ?? { arguments in
            var environment = ProcessInfo.processInfo.environment
            environment["GIT_TERMINAL_PROMPT"] = "0"
            environment["GIT_SSH_COMMAND"] = "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=5"
            let result = try CommandRunner.run(CommandSpec(executable: "/usr/bin/git", arguments: ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-C", root.path] + arguments, requiresAdmin: false), timeout: 10, environment: environment)
            guard result.success, !result.truncated else { throw DonyError.unsupported }
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            guard try command(["rev-parse", "--is-inside-work-tree"]) == "true" else { return GitBackupReport(false, "Git 저장소 아님") }
            guard try !containsNestedRepository(root: root) else { return GitBackupReport(false, "내부에 별도 저장소 있음") }
            guard try command(["status", "--porcelain=v1", "--untracked-files=all"]).isEmpty else { return GitBackupReport(false, "로컬 변경·새 파일 있음") }
            guard try command(["stash", "list"]).isEmpty else { return GitBackupReport(false, "보관하지 않은 stash 있음") }
            let worktrees = try command(["worktree", "list", "--porcelain"])
            guard worktrees.split(separator: "\n").filter({ $0.hasPrefix("worktree ") }).count == 1 else { return GitBackupReport(false, "연결된 worktree 있음") }
            guard try command(["submodule", "status", "--recursive"]).isEmpty else { return GitBackupReport(false, "하위 저장소 확인 필요") }
            let ignored = try command(["ls-files", "--others", "--ignored", "--exclude-standard"])
            var allowedGenerated = ProjectCleanup.generatedPaths
            if ["package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb"].contains(where: { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }) { allowedGenerated.append("node_modules") }
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) { allowedGenerated.append(".build") }
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("Cargo.toml").path) { allowedGenerated.append("target") }
            guard ignored.split(separator: "\n").allSatisfy({ path in allowedGenerated.contains { path.hasPrefix($0 + "/") } }) else { return GitBackupReport(false, "로컬 전용 파일 있음") }
            let lfsPath = try command(["rev-parse", "--git-path", "lfs"])
            if !lfsPath.isEmpty {
                let lfs = lfsPath.hasPrefix("/") ? URL(fileURLWithPath: lfsPath) : root.appendingPathComponent(lfsPath)
                if FileManager.default.fileExists(atPath: lfs.path) { return GitBackupReport(false, "LFS 원격 파일 확인 필요") }
            }
            let tracked = try command(["ls-files", "-z"]).split(separator: "\0").map(String.init)
            if !tracked.isEmpty, try command(["check-attr", "-z", "filter", "--"] + tracked).contains("\0lfs\0") { return GitBackupReport(false, "LFS 원격 파일 확인 필요") }
            // LFS payload availability is separate from Git commit availability.
            let attributePaths = try command(["ls-files", "--", ".gitattributes", "**/.gitattributes"])
            for path in attributePaths.split(separator: "\n") {
                let data = try Data(contentsOf: root.appendingPathComponent(String(path)))
                if String(data: data, encoding: .utf8)?.contains("filter=lfs") == true { return GitBackupReport(false, "LFS 원격 파일 확인 필요") }
            }
            guard try command(["rev-list", "--reflog", "--not", "--all"]).isEmpty else { return GitBackupReport(false, "브랜치에 남기지 않은 이전 작업 있음") }
            let head = try command(["rev-parse", "HEAD"])
            let refs = try command(["for-each-ref", "--format=%(objectname)", "refs"])
            let localObjects = Set(refs.split(separator: "\n").map(String.init) + [head])
            guard !head.isEmpty else { return GitBackupReport(false, "커밋 없음") }
            let remotes = try command(["remote"]).split(separator: "\n").map(String.init)
            guard !remotes.isEmpty else { return GitBackupReport(false, "원격 저장소 없음") }
            var remoteObjects = Set<String>()
            for remote in remotes {
                let address = try command(["remote", "get-url", remote])
                guard address.hasPrefix("https://") || address.hasPrefix("ssh://") || address.hasPrefix("git@") else { continue }
                let response = try command(["ls-remote", "--refs", remote])
                for row in response.split(separator: "\n") {
                    let fields = row.split(separator: "\t", maxSplits: 1)
                    if fields.count == 2, fields[1].hasPrefix("refs/") { remoteObjects.insert(String(fields[0])) }
                }
            }
            guard localObjects.isSubset(of: remoteObjects) else { return GitBackupReport(false, "원격에 없는 커밋·브랜치 있음") }
            return GitBackupReport(true, "원격 저장 확인")
        } catch { return GitBackupReport(false, "원격 확인 실패 · 보관") }
    }
    public static func containsNestedRepository(root: URL) throws -> Bool {
        let base = try FileSafety.canonicalRoot(root)
        var found = false
        try ProjectFileWalker.walk(root: base, token: ScanToken(), shouldDescend: { $0.lastPathComponent != ".git" }) { file, _ in
            if file.path != base.appendingPathComponent(".git").path, file.lastPathComponent == ".git" { found = true }
        }
        return found
    }

    public static func structuralCheck(root: URL, run: ((URL) throws -> String)? = nil) -> GitBackupReport {
        do {
            let base = try FileSafety.canonicalRoot(root)
            var repositories: [URL] = []
            try ProjectFileWalker.walk(root: base, token: ScanToken(), shouldDescend: { $0.lastPathComponent != ".git" }) { file, stamp in
                if file.lastPathComponent == ".git" {
                    guard stamp.isDirectory else { throw DonyError.unsupported }
                    repositories.append(file.deletingLastPathComponent())
                }
            }
            for repository in repositories {
                let listing: String
                if let run { listing = try run(repository) }
                else {
                    let result = try CommandRunner.run(CommandSpec(executable: "/usr/bin/git", arguments: ["--no-optional-locks", "-c", "core.fsmonitor=false", "-C", repository.path, "worktree", "list", "--porcelain"], requiresAdmin: false), timeout: 5)
                    guard result.success, !result.truncated else { throw DonyError.unsupported }; listing = result.output
                }
                guard listing.split(separator: "\n").filter({ $0.hasPrefix("worktree ") }).count == 1 else { return GitBackupReport(false, "연결된 worktree 있음 · 보관") }
            }
            return GitBackupReport(true, "작업 폴더 구조 확인")
        } catch { return GitBackupReport(false, "작업 폴더 구조 확인 필요") }
    }
}

public enum ProjectBackupPolicy {
    public static func filter(_ input: ScanResult, token: ScanToken, check: (FileCandidate) -> GitBackupReport) -> ScanResult {
        var result = input
        result.items = []
        for item in input.items {
            if token.isCancelled { break }
            let report = check(item)
            if token.isCancelled { break }
            if report.verified { result.items.append(item) }
            else { result.issues.append(ScanIssue(path: item.id, message: report.reason)) }
        }
        result.cancelled = input.cancelled || token.isCancelled
        if result.cancelled { result.items.removeAll() }
        return result
    }
}
