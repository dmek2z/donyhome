import Foundation
import Testing
@testable import DonyCore

@Suite struct DeviceCareTests {
    let gb: Int64 = 1_000_000_000
    @Test func missingOrImpossibleDiskMetricsAreNotReportedAsFullOrHealthy() {
        #expect(StorageAssessment.resolve(available: nil, total: 250 * gb).health == .unknown)
        #expect(StorageAssessment.resolve(available: -1, total: 250 * gb).health == .unknown)
        #expect(StorageAssessment.resolve(available: 300 * gb, total: 250 * gb).health == .unknown)
        #expect(StorageAssessment.resolve(available: 0, total: 0).health == .unknown)
    }
    @Test func capacityAndUserThresholdDetermineSeverity() {
        #expect(StorageAssessment.resolve(available: 30 * gb, total: 250 * gb).health == .normal)
        #expect(StorageAssessment.resolve(available: 20 * gb, total: 250 * gb).health == .low)
        #expect(StorageAssessment.resolve(available: 5 * gb, total: 250 * gb).health == .critical)
        #expect(StorageAssessment.resolve(available: 30 * gb, total: 250 * gb, warningGB: 40).health == .low)
        #expect(StorageAssessment.resolve(available: 7 * gb, total: 10 * gb).health == .normal)
    }
    @Test func recoveryMarginPreventsThresholdFlapping() {
        #expect(StorageAssessment.resolve(available: 21 * gb, total: 250 * gb, recovering: true).health == .low)
        #expect(StorageAssessment.resolve(available: 23 * gb, total: 250 * gb, recovering: true).health == .normal)
        #expect(StorageAssessment.resolve(available: 21 * gb, total: 250 * gb).health == .normal)
    }
    @Test func persistentPressureWaitsAndLimitsRepeatNotifications() {
        let now = Date(timeIntervalSince1970: 10000)
        let low = StorageAssessment.resolve(available: 12 * gb, total: 250 * gb)
        var gate = StorageNoticeGate()
        let notice1 = gate.update(low, now: now, enabled: true)
        #expect(!notice1)
        let notice2 = gate.update(low, now: now.addingTimeInterval(29), enabled: true)
        #expect(!notice2)
        let notice3 = gate.update(low, now: now.addingTimeInterval(30), enabled: true)
        #expect(notice3)
        let notice4 = gate.update(low, now: now.addingTimeInterval(40), enabled: true)
        #expect(!notice4)
        let notice5 = gate.update(low, now: now.addingTimeInterval(3630), enabled: true)
        #expect(notice5)
    }
    @Test func recoveryAndDisablePreventUnexpectedNotice() {
        let now = Date(); let low = StorageAssessment.resolve(available: 10 * gb, total: 250 * gb)
        var gate = StorageNoticeGate()
        let notice6 = gate.update(low, now: now, enabled: false)
        #expect(!notice6)
        let notice7 = gate.update(low, now: now.addingTimeInterval(60), enabled: false)
        #expect(!notice7)
        let notice8 = gate.update(StorageAssessment.resolve(available: 30 * gb, total: 250 * gb), now: now.addingTimeInterval(61), enabled: true)
        #expect(!notice8)
        let notice9 = gate.update(low, now: now.addingTimeInterval(62), enabled: true)
        #expect(!notice9)
    }
    @Test func trashBytesAreNeverPresentedAsReclaimedCapacity() {
        let outcome = CleanupOutcome(movedBytes: 10 * gb, successful: 4, failed: 2, beforeAvailable: 20 * gb, afterAvailable: 20 * gb)
        #expect(outcome.movedBytes == 10 * gb)
        #expect(outcome.observedGain == 0)
        #expect(!outcome.permanent)
        let unknown = CleanupOutcome(movedBytes: 10 * gb, successful: 4, failed: 0, beforeAvailable: nil, afterAvailable: 20 * gb)
        #expect(unknown.observedGain == nil)
    }
    @Test func observedChangeRecordsConcurrentConsumptionAndPermanentDeletionHonestly() {
        let consumed = CleanupOutcome(movedBytes: gb, successful: 1, failed: 0, beforeAvailable: 20 * gb, afterAvailable: 19 * gb)
        #expect(consumed.observedDelta == -gb)
        #expect(consumed.observedGain == 0)
        let reclaimed = CleanupOutcome(movedBytes: 2 * gb, successful: 1, failed: 0, beforeAvailable: 20 * gb, afterAvailable: 22 * gb, permanent: true)
        #expect(reclaimed.observedGain == 2 * gb)
        #expect(reclaimed.permanent)
    }
}

@Test func cleanupSpaceCapturedAtFirstMutationOnly() {
    let meter = CleanupSpaceMeasurement()
    #expect(meter.beforeAvailable == nil)
    meter.captureBeforeMutation { 42 }
    meter.captureBeforeMutation { 90 }
    #expect(meter.beforeAvailable == 42)
}
@Test func unavailableSpaceRemainsUnknown() {
    let meter = CleanupSpaceMeasurement()
    meter.captureBeforeMutation { nil }
    meter.captureBeforeMutation { 90 }
    #expect(meter.beforeAvailable == nil)
}
