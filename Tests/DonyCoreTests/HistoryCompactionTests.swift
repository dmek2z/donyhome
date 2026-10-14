import Testing
import Foundation
@testable import DonyCore

@Suite struct HistoryCompactionTests {
    private func record(_ kind: String = "휴지통 이동", at seconds: Double, bytes: Int64 = 10, success: Bool = true) -> ActionRecord {
        ActionRecord(summaryOf: kind, success: success, timestamp: Date(timeIntervalSinceReferenceDate: seconds), count: 1, bytes: bytes)
    }
    @Test func smallHistoryIsLeftAlone() {
        let records = (0..<100).map { record(at: Double(1_000 - $0)) }
        #expect(HistoryStore.compact(records).count == 100)
    }
    @Test func oldRunsAreSummarizedAndTotalsPreserved() {
        // 최신순: 최근 정리 6,000건(1분 안), 그 이전 정리 4,000건(하루 전)
        let recent = (0..<6000).map { record(at: 200_000 - Double($0) * 0.01) }
        let old = (0..<4000).map { record(at: 100_000 - Double($0) * 0.01) }
        let all = recent + old
        let compacted = HistoryStore.compact(all, detailLimit: 5000)
        #expect(compacted.count < all.count)
        #expect(compacted.prefix(5000).allSatisfy { $0.count == 1 })
        // 상세 한도를 넘은 최근 정리 1,000건과 이전 정리 4,000건은 정리 단위로 요약된다(총 2개 요약)
        let summaries = compacted.dropFirst(5000)
        #expect(summaries.count == 2)
        #expect(summaries.map { $0.count ?? 0 } == [1000, 4000])
        // 용량·개수 합계는 압축 전과 같다
        #expect(compacted.reduce(0) { $0 + $1.bytes } == all.reduce(0) { $0 + $1.bytes })
        #expect(compacted.reduce(0) { $0 + ($1.count ?? 1) } == all.count)
    }
    @Test func differentKindsOrFailuresAreNotMerged() {
        let mixed = (0..<10).map { record($0 % 2 == 0 ? "휴지통 이동" : "앱 종료 요청", at: 1_000 - Double($0)) }
        let compacted = HistoryStore.compact(mixed, detailLimit: 0)
        #expect(compacted.count == 10)
        let failure = [record(at: 100), record(at: 99, success: false), record(at: 98)]
        #expect(HistoryStore.compact(failure, detailLimit: 0).count == 3)
    }
    @Test func oldFilesWithoutCountStillDecode() throws {
        let json = #"[{"bytes":5,"id":"3EBB4CD9-0B91-4741-9631-D5730B3CABC6","kind":"휴지통 이동","message":"ok","sourcePath":"/a/b","success":true,"timestamp":813689090.2}]"#
        let decoded = try JSONDecoder().decode([ActionRecord].self, from: Data(json.utf8))
        #expect(decoded.count == 1 && decoded[0].count == nil)
    }
}
