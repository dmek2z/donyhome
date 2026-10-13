import Foundation
import Testing
@testable import DonyCore

@Suite struct GitBackupTests {
    func check(overrides: [String: String] = [:]) -> GitBackupReport {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return GitBackup.check(root: root) { arguments in
            let key = arguments.joined(separator: " ")
            if let value = overrides[key] { return value }
            switch key {
            case "rev-parse --is-inside-work-tree": return "true"
            case "rev-parse HEAD": return "head-object"
            case "for-each-ref --format=%(objectname) refs": return "head-object\ntag-object"
            case "worktree list --porcelain": return "worktree /fixture\nHEAD head-object"
            case "remote": return "origin"
            case "remote get-url origin": return "https://example.test/repo.git"
            case "ls-remote --refs origin": return "head-object\trefs/heads/main\ntag-object\trefs/tags/v1"
            default: return ""
            }
        }
    }
    @Test func requiresLiveRemoteObjectsIncludingAllLocalBranchesAndTags() {
        #expect(check().verified)
        #expect(!check(overrides: ["ls-remote --refs origin": "head-object\trefs/heads/main"]).verified)
        #expect(!check(overrides: ["for-each-ref --format=%(objectname) refs": "unpublished-branch"]).verified)
        #expect(!check(overrides: ["remote": ""]).verified)
        #expect(!check(overrides: ["remote get-url origin": "/same-disk/copy.git"]).verified)
    }
    @Test func localWorkAndLinkedWorktreesBlockWholeFolderRemoval() {
        for (key, value) in [("status --porcelain=v1 --untracked-files=all", "?? new.swift"), ("stash list", "stash@{0}"), ("rev-list --reflog --not --all", "orphaned-commit"), ("worktree list --porcelain", "worktree /fixture\nworktree /other"), ("submodule status --recursive", "submodule"), ("ls-files --others --ignored --exclude-standard", ".env\nnode_modules/generated")] {
            #expect(!check(overrides: [key: value]).verified)
        }
        #expect(!check(overrides: ["ls-files -z": "asset.bin\0", "check-attr -z filter -- asset.bin": "asset.bin\0filter\0lfs\0"]).verified)
        #expect(check(overrides: ["ls-files --others --ignored --exclude-standard": ".next/cache"]).verified)
    }
    @Test func inaccessibleRemoteFailsClosed() {
        let report = GitBackup.check(root: URL(fileURLWithPath: "/fixture")) { _ in throw DonyError.unsupported }
        #expect(!report.verified)
        #expect(report.reason == "원격 확인 실패 · 보관")
    }
    @Test func commandOutputLimitsAreExplicitSoIncompleteGitResultsCannotCertifyBackup() throws {
        let result = try CommandRunner.run(CommandSpec(executable: "/usr/bin/awk", arguments: ["BEGIN { for (i=0; i<70000; i++) printf \"x\"; printf \"local-only-tail\" }"], requiresAdmin: false), timeout: 5)
        #expect(result.success)
        #expect(result.truncated)
        #expect(!result.output.contains("local-only-tail"))
    }
    @Test func ignoredBuildDirectoriesCannotHideIndependentRepositories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git/objects"), withIntermediateDirectories: true)
        #expect(try !GitBackup.containsNestedRepository(root: root))
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".next/private-source/.git"), withIntermediateDirectories: true)
        #expect(try GitBackup.containsNestedRepository(root: root))
    }

    @Test func worktreeProtectionIsIndependentOfRemoteBackupChoice() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        #expect(GitBackup.structuralCheck(root: root, run: { _ in "worktree /main" }).verified)
        #expect(!GitBackup.structuralCheck(root: root, run: { _ in "worktree /main\nworktree /unselected" }).verified)
    }
    @Test func cancellingDuringBackupVerificationNeverPublishesMovableCandidates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: root.appendingPathComponent("source"))
        let token = ScanToken()
        let item = try FileCandidate.capture(url: root.appendingPathComponent("source"), root: root, kind: .project, token: token)
        var input = ScanResult(); input.items = [item]
        let result = ProjectBackupPolicy.filter(input, token: token) { _ in token.cancel(); return GitBackupReport(true, "verified") }
        #expect(result.cancelled)
        #expect(result.items.isEmpty)
    }

}
