import Testing
@testable import DonyCore

@Suite struct NoticeCopyTests {
    @Test func overloadMessagesAreDistinctPerState() {
        let cpu = NoticeCopy.overload(.cpu), memory = NoticeCopy.overload(.memory), both = NoticeCopy.overload(.both)
        #expect(Set([cpu.title, memory.title, both.title]).count == 3)
        #expect(memory.title.contains("메모리") && cpu.title.contains("CPU"))
    }
    @Test func storageCriticalDiffersFromLowAndShowsAvailableSpace() {
        let low = NoticeCopy.storage(.low, availableText: "12 GB"), critical = NoticeCopy.storage(.critical, availableText: "3 GB")
        #expect(low.title != critical.title)
        #expect(low.body.contains("12 GB") && critical.body.contains("3 GB"))
    }
    @Test func variantsNeverCrashOnAnyIndex() {
        for variant in [-3, -1, 0, 1, 7, Int.min + 1] { #expect(!NoticeCopy.overload(.cpu, variant: variant).title.isEmpty) }
    }
}
