import Foundation
import DonySystemBridge

public struct OpenFileSnapshot: Sendable {
    public let paths: Set<String>
    public let identities: Set<String>
    public let complete: Bool
    public init(paths: Set<String>, identities: Set<String> = [], complete: Bool) {
        self.paths = paths; self.identities = identities; self.complete = complete
    }
    public func contains(_ candidate: FileCandidate) -> Bool {
        paths.contains(candidate.id) || identities.contains(candidate.fingerprint.identity)
    }
    public static func read(processes: [ProcessReading], token: ScanToken) -> Self {
        var paths = Set<String>(); var identities = Set<String>(); var seen = Set<Int32>()
        var buffer = [CChar](repeating: 0, count: 2_000_000)
        for process in processes where seen.insert(process.pid).inserted {
            guard !token.isCancelled,
                  dc_process_matches(process.pid, process.uid, process.startSeconds, process.startMicroseconds) != 0 else { return Self(paths: paths, identities: identities, complete: false) }
            let count = buffer.withUnsafeMutableBufferPointer { dc_process_open_files(process.pid, $0.baseAddress, Int32($0.count)) }
            guard count >= 0, !token.isCancelled,
                  dc_process_matches(process.pid, process.uid, process.startSeconds, process.startMicroseconds) != 0 else { return Self(paths: paths, identities: identities, complete: false) }
            var record = [UInt8]()
            for character in buffer.prefix(Int(count)) {
                let byte = UInt8(bitPattern: character)
                if byte != 0 { record.append(byte); continue }
                guard let value = String(bytes: record, encoding: .utf8), value.count > 1 else { return Self(paths: paths, identities: identities, complete: false) }
                if value.first == "p" { paths.insert(String(value.dropFirst())) }
                else if value.first == "i" { identities.insert(String(value.dropFirst())) }
                else { return Self(paths: paths, identities: identities, complete: false) }
                record.removeAll(keepingCapacity: true)
            }
            guard record.isEmpty else { return Self(paths: paths, identities: identities, complete: false) }
        }
        return Self(paths: paths, identities: identities, complete: !token.isCancelled)
    }
}
