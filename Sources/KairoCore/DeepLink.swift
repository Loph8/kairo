import Foundation

/// kairo://schedule | member/<id> | proposal/<id> | call/<id>
/// Identifiers are validated before use; anything else is rejected.
public enum DeepLink: Hashable, Sendable {
    case dashboard, schedule
    case member(String), proposal(String), call(String)

    public static func validID(_ s: String) -> Bool {
        guard (1...80).contains(s.count) else { return false }
        return s.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_+.:").contains($0) }
    }

    public init?(url: URL) {
        guard url.scheme == "kairo", let host = url.host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch (host, parts.count) {
        case ("dashboard", 0): self = .dashboard
        case ("schedule", 0): self = .schedule
        case ("member", 1) where Self.validID(parts[0]): self = .member(parts[0])
        case ("proposal", 1) where Self.validID(parts[0]): self = .proposal(parts[0])
        case ("call", 1) where Self.validID(parts[0]): self = .call(parts[0])
        default: return nil
        }
    }

    public var url: URL {
        switch self {
        case .dashboard: return URL(string: "kairo://dashboard")!
        case .schedule: return URL(string: "kairo://schedule")!
        case .member(let id): return URL(string: "kairo://member/\(id)")!
        case .proposal(let id): return URL(string: "kairo://proposal/\(id)")!
        case .call(let id): return URL(string: "kairo://call/\(id)")!
        }
    }
}
