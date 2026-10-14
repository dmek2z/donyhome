import Foundation
import Vision
import ImageIO

public struct SimilarMatch: Sendable {
    public let candidate: FileCandidate
    public let distance: Float
}
public struct SimilarGroup: Identifiable, Sendable {
    public var id: String { original.id }
    public let original: FileCandidate
    public let copies: [SimilarMatch]
    public init(original: FileCandidate, copies: [SimilarMatch]) { self.original = original; self.copies = copies }
}
public struct SimilarResult: Sendable {
    public var groups: [SimilarGroup] = []
    public var issues: [ScanIssue] = []
    public var cancelled = false
    public var compared = 0
    public init() {}
}
public enum SimilarPhotoFinder {
    public static func thumbnail(_ url: URL, pixels: Int = 1024) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw DonyError.unsupported }
        return image
    }
    private static func feature(_ item: FileCandidate, token: ScanToken) throws -> VNFeaturePrintObservation {
        try FileSafety.validate(item, token: token)
        let request = VNGenerateImageFeaturePrintRequest(); request.revision = VNGenerateImageFeaturePrintRequestRevision2; request.imageCropAndScaleOption = .scaleFit; request.usesCPUOnly = true
        try VNImageRequestHandler(cgImage: thumbnail(item.url), options: [:]).perform([request])
        try token.check(); try FileSafety.validate(item, token: token)
        guard let print = request.results?.first else { throw DonyError.unsupported }; return print
    }
    public static func replacingOriginal(in group: SimilarGroup, with chosen: FileCandidate, token: ScanToken) throws -> SimilarGroup {
        let members = [group.original] + group.copies.map(\.candidate)
        guard members.contains(where: { $0.id == chosen.id }) else { throw DonyError.unsafePath }
        let reference = try feature(chosen, token: token)
        var copies: [SimilarMatch] = []
        for member in members where member.id != chosen.id {
            try token.check()
            var distance: Float = 0; try reference.computeDistance(&distance, to: feature(member, token: token))
            copies.append(SimilarMatch(candidate: member, distance: distance))
        }
        return SimilarGroup(original: chosen, copies: copies)
    }
    public static func find(root: URL, token: ScanToken, maximumDistance: Float = 0.35, progress: Scanner.Progress? = nil) -> SimilarResult {
        let scanned = Scanner.walk(root: root, minimumBytes: 1, kind: .similar, token: token, progress: progress)
        var result = SimilarResult(); result.issues = scanned.issues; result.cancelled = scanned.cancelled
        guard !token.isCancelled else { result.cancelled = true; return result }
        let images = scanned.items.filter { ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"].contains($0.url.pathExtension.lowercased()) }.sorted { $0.id < $1.id }
        if images.count > 200 { result.issues.append(ScanIssue(path: root.path, message: "이미지 200개까지만 비교했습니다. 더 작은 폴더로 나누어 검사해 주세요.")) }
        var prints: [(FileCandidate, VNFeaturePrintObservation)] = []
        var seen = Set<String>()
        for item in images.prefix(200) where seen.insert(item.fingerprint.identity).inserted {
            if token.isCancelled { result.cancelled = true; break }
            progress?(prints.count, "사진 분석 · " + item.name)
            do {
                let observation = try autoreleasepool { () throws -> VNFeaturePrintObservation in
                    try feature(item, token: token)
                }
                prints.append((item, observation))
            } catch { if token.isCancelled { result.cancelled = true; break }; result.issues.append(ScanIssue(path: item.id, error: error)) }
        }
        var assigned = Set<Int>()
        for index in prints.indices where !assigned.contains(index) {
            if token.isCancelled { result.cancelled = true; break }
            var copies: [SimilarMatch] = []
            for other in prints.indices where other > index && !assigned.contains(other) {
                if token.isCancelled { result.cancelled = true; break }
                do {
                    var distance: Float = 0; try prints[index].1.computeDistance(&distance, to: prints[other].1); result.compared += 1
                    if distance.isFinite && distance <= maximumDistance { copies.append(SimilarMatch(candidate: prints[other].0, distance: distance)); assigned.insert(other) }
                } catch { result.issues.append(ScanIssue(path: prints[other].0.id, error: error)) }
            }
            if !copies.isEmpty { result.groups.append(SimilarGroup(original: prints[index].0, copies: copies)) }
        }
        return result
    }
}
