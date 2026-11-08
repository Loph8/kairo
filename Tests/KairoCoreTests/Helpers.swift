import Testing
import Foundation
@testable import KairoCore

enum TestEnv {
    static let ny = TimeZone(identifier: "America/New_York")!
    static let seoul = TimeZone(identifier: "Asia/Seoul")!
    static let addis = TimeZone(identifier: "Africa/Addis_Ababa")!
    static func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    static func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("gh-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    /// Repository at the demo anchor with the seeded family, onboarding complete.
    static func seededRepo(at date: Date = DemoSeed.anchor) async throws -> LocalDemoRepository {
        let repo = LocalDemoRepository(directory: tempDir(), clock: FixedTimeSource(date))
        let me = Person(id: "you", name: "You", relationship: "You", city: "Durham",
                        timeZoneID: "America/New_York", prefs: DemoSeed.people()[0].prefs)
        try await repo.completeOnboarding(profile: me, useDemoFamily: true)
        return repo
    }
}

// Minimal assertion shim over Swift Testing (XCTest is not installed with Command Line Tools).
func expectEq<T: Equatable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a == b, sourceLocation: sourceLocation) }
func expectNE<T: Equatable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a != b, sourceLocation: sourceLocation) }
func expectTrue(_ a: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a, sourceLocation: sourceLocation) }
func expectFalse(_ a: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(!a, sourceLocation: sourceLocation) }
func expectNil<T>(_ a: T?, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a == nil, sourceLocation: sourceLocation) }
func expectGT<T: Comparable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a > b, sourceLocation: sourceLocation) }
func expectGE<T: Comparable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a >= b, sourceLocation: sourceLocation) }
func expectLT<T: Comparable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a < b, sourceLocation: sourceLocation) }
func expectLE<T: Comparable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a <= b, sourceLocation: sourceLocation) }
func fail(_ msg: String = "failed", sourceLocation: SourceLocation = #_sourceLocation) { Issue.record(Comment(rawValue: msg), sourceLocation: sourceLocation) }
func expectThrows(_ body: @autoclosure () throws -> Void, sourceLocation: SourceLocation = #_sourceLocation) {
    do { try body(); Issue.record("expected throw", sourceLocation: sourceLocation) } catch {}
}
