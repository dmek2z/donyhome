import Testing
import Foundation
@testable import DonyCore

@MainActor @Suite struct ClipboardPrivacyTests {
    private func item(_ text: String, daysAgo: Double, pinned: Bool = false) -> ClipboardItem {
        var value = ClipboardItem(representations: [[ClipboardRepresentation(type: "public.utf8-plain-text", data: Data(text.utf8))]])
        value.lastCopiedAt = Date().addingTimeInterval(-daysAgo * 86_400); value.pinned = pinned
        return value
    }
    @Test func expiryRemovesOldUnpinnedItemsOnly() {
        let items = [item("recent", daysAgo: 1), item("old", daysAgo: 45), item("old pinned", daysAgo: 400, pinned: true)]
        let kept = ClipboardHistory.removingExpired(items, days: 30).compactMap(\.text)
        #expect(Set(kept) == ["recent", "old pinned"])
        #expect(ClipboardHistory.removingExpired(items, days: 0).count == 3)
    }
    @Test func defaultExpiryIsThirtyDaysAndNeverMeansZero() {
        #expect(ClipboardBehavior().effectiveExpireDays == 30)
        var behavior = ClipboardBehavior(); behavior.expireDays = 0
        #expect(behavior.effectiveExpireDays == 0)
    }
    @Test func storedBehaviorFromEarlierVersionsStillDecodes() throws {
        let json = #"{"pasteAutomatically":true,"plainText":false,"clearOnQuit":false,"clearSystemOnQuit":false}"#
        let decoded = try JSONDecoder().decode(ClipboardBehavior.self, from: Data(json.utf8))
        #expect(decoded.pasteAutomatically && decoded.expireDays == nil && decoded.effectiveExpireDays == 30)
    }
    @Test func defaultPatternsBlockSecretsButNotOrdinaryText() {
        let patterns = ClipboardPreferences().ignoredPatterns
        func blocked(_ text: String) -> Bool { patterns.contains { text.range(of: $0, options: .regularExpression) != nil } }
        #expect(blocked("-----BEGIN RSA PRIVATE KEY-----"))
        #expect(blocked("sk-abcdefghijklmnopqrstuvwxyz123456"))
        #expect(blocked("ghp_abcdefghijklmnopqrstuvwxyz1234567890"))
        #expect(blocked("AKIAABCDEFGHIJKLMNOP"))
        #expect(blocked("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop"))
        #expect(blocked("900101-1234567"))
        #expect(blocked("4111 1111 1111 1111"))
        #expect(!blocked("git commit -m \"fix: 맥이 난로가 되기 전에 정리\""))
        #expect(!blocked("https://github.com/dmek2z/donyhome"))
        #expect(!blocked("내일 오전 10시 · 회의 2026-10-15"))
    }
}
