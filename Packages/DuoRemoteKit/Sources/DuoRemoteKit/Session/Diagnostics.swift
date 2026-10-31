import Foundation
import MetricKit

/// Saves MetricKit crash/hang diagnostics (delivered by iOS on the next launch after a crash or
/// hang) as JSON files, so they can be shared from the app instead of waiting for TestFlight.
public nonisolated final class Diagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    public static let shared = Diagnostics()

    static var folder: URL {
        URL.documentsDirectory.appending(path: "Diagnostics", directoryHint: .isDirectory)
    }

    public func start() {
        MXMetricManager.shared.add(self)
        // Also save anything iOS has already queued for us.
        save(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        save(payloads)
    }

    private func save(_ payloads: [MXDiagnosticPayload]) {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        for p in payloads {
            var kinds: [String] = []
            if !(p.crashDiagnostics ?? []).isEmpty { kinds.append("crash") }
            if !(p.hangDiagnostics ?? []).isEmpty { kinds.append("hang") }
            if kinds.isEmpty { kinds.append("other") }
            let stamp = ISO8601DateFormatter().string(from: p.timeStampEnd).replacingOccurrences(of: ":", with: "-")
            let url = Self.folder.appending(path: "\(stamp)-\(kinds.joined(separator: "+")).json")
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try? p.jsonRepresentation().write(to: url)
        }
    }

    /// Saved reports, newest first.
    static func reports() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
