import Foundation

public enum Codec {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
}

public struct WidgetPerson: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var relationship: String
    public var city: String
    public var flag: String?
    public var initials: String
    public var timeZoneID: String
    /// 48 coarse levels in 30-minute steps from `WidgetSnapshot.forecastStart`.
    public var forecast: [AvailabilityLevel]
    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)! }
}

public struct WidgetProposal: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var personID: String
    public var personName: String
    public var start: Date
    public var end: Date
    public var state: ViewerBookingState
    public var explanation: String
}

/// What widgets render. Widgets never run the model or touch the network; they read this.
public struct WidgetSnapshot: Codable, Sendable {
    public static let currentSchema = 1
    public static let staleAfter: TimeInterval = 6 * 3600
    public var schemaVersion = WidgetSnapshot.currentSchema
    /// Effective (demo-adjusted) time the snapshot was built.
    public var generatedAt: Date
    public var forecastStart: Date
    /// Add to the real clock to get effective time (non-zero only in demo mode).
    public var clockOffset: TimeInterval
    public var viewerID: String
    public var viewerName: String
    public var viewerTimeZoneID: String
    public var use24Hour: Bool
    public var focusPersonID: String
    public var people: [WidgetPerson]
    public var proposals: [WidgetProposal]
    public var busyUntil: Date?
    public var sync: SyncStatus
    public var isDemo: Bool

    public var viewerTimeZone: TimeZone { TimeZone(identifier: viewerTimeZoneID) ?? TimeZone(secondsFromGMT: 0)! }

    public func effectiveNow(real: Date = Date()) -> Date { real.addingTimeInterval(clockOffset) }
    public func isStale(at effectiveNow: Date) -> Bool { effectiveNow.timeIntervalSince(generatedAt) > Self.staleAfter }

    /// Level at `instant`, or nil when beyond the cached forecast (render as "Learning/Unknown").
    public func level(of personID: String, at instant: Date) -> AvailabilityLevel? {
        guard let p = people.first(where: { $0.id == personID }) else { return nil }
        let idx = Int(floor(instant.timeIntervalSince(forecastStart) / 1800))
        return (0..<p.forecast.count).contains(idx) ? p.forecast[idx] : nil
    }

    public func nextProposal(for personID: String?) -> WidgetProposal? {
        let live: Set<ViewerBookingState> = [.suggested, .awaitingYou, .awaitingOther, .confirmed]
        return proposals.filter { live.contains($0.state) && (personID == nil || $0.personID == personID) }
            .sorted { $0.start < $1.start }.first
    }

    public static func placeholder(now: Date) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: now, forecastStart: now, clockOffset: 0, viewerID: "", viewerName: "You",
                       viewerTimeZoneID: TimeZone.current.identifier, use24Hour: false, focusPersonID: "",
                       people: [], proposals: [], busyUntil: nil, sync: .localOnly, isDemo: false)
    }
}

public enum SnapshotLoadResult: Sendable {
    case loaded(WidgetSnapshot)
    case empty            // no file yet
    case corrupted        // unreadable JSON
    case unsupportedVersion
    case unavailable      // shared container (App Group) not reachable
}

/// Atomic, corruption-tolerant store for the shared widget snapshot.
public struct SnapshotStore: Sendable {
    public let fileURL: URL?
    public init(directory: URL?) { fileURL = directory?.appendingPathComponent("snapshot.json") }

    public func load() -> SnapshotLoadResult {
        guard let url = fileURL else { return .unavailable }
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        guard let data = try? Data(contentsOf: url) else { return .corrupted }
        struct Probe: Decodable { var schemaVersion: Int }
        if let probe = try? Codec.decoder().decode(Probe.self, from: data),
           probe.schemaVersion != WidgetSnapshot.currentSchema { return .unsupportedVersion }
        guard let snap = try? Codec.decoder().decode(WidgetSnapshot.self, from: data) else { return .corrupted }
        return .loaded(snap)
    }

    public func save(_ snapshot: WidgetSnapshot) throws {
        guard let url = fileURL else { throw RepositoryError.storageUnavailable }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Codec.encoder().encode(snapshot).write(to: url, options: .atomic)
    }
}
