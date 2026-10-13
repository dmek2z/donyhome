import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import DonyCore

@Suite struct SimilarPhotoTests {
    @Test func localFeaturePrintGroupsImagesAndRetainsOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let context = try #require(CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 128 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1)); context.fillEllipse(in: CGRect(x: 20, y: 20, width: 80, height: 80))
        let image = try #require(context.makeImage())
        for name in ["a.png", "b.png"] {
            let output = root.appendingPathComponent(name)
            let destination = try #require(CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil); #expect(CGImageDestinationFinalize(destination))
        }
        let result = SimilarPhotoFinder.find(root: root, token: ScanToken())
        #expect(result.issues.isEmpty)
        #expect(result.groups.count == 1)
        let group = try #require(result.groups.first)
        #expect(group.copies.count == 1)
        #expect(group.copies[0].distance < 0.001)
        let changed = try SimilarPhotoFinder.replacingOriginal(in: group, with: group.copies[0].candidate, token: ScanToken())
        #expect(changed.original.id == group.copies[0].candidate.id)
        #expect(changed.copies[0].candidate.id == group.original.id)
        let protectedPlan = RecommendedActions.plan(cleanup: [group.original], duplicates: [], preserving: [group.original, group.copies[0].candidate])
        #expect(protectedPlan.items.isEmpty)
        let exact = DuplicateFinder.find(root: root, token: ScanToken())
        let crossing = RecommendedActions.plan(cleanup: [], duplicates: exact.groups, preserving: [changed.original])
        #expect(!crossing.items.contains { $0.id == changed.original.id })
        try FileManager.default.removeItem(at: group.original.url)
        let action = TrashService.move(group.copies[0].candidate, keeping: group.original)
        #expect(!action.success)
        if let path = action.trashPath { try FileManager.default.moveItem(at: URL(fileURLWithPath: path), to: group.copies[0].candidate.url) }
    }
    @Test func unreadableImagesAndCancellationAreVisible() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("invalid image fixture".utf8).write(to: root.appendingPathComponent("bad.jpg"))
        #expect(!SimilarPhotoFinder.find(root: root, token: ScanToken()).issues.isEmpty)
        let token = ScanToken(); token.cancel()
        #expect(SimilarPhotoFinder.find(root: root, token: token).cancelled)
    }
}
