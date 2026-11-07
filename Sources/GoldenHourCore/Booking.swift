import Foundation

public enum ProposalStatus: String, Codable, Sendable {
    case suggested, pending, confirmed, declined, expired, canceled, completed
    public var isOpen: Bool { self == .suggested || self == .pending }
    public var isTerminal: Bool { !isOpen && self != .confirmed }
}

/// What a specific viewer should see. "Awaiting you" vs "awaiting other" is viewer-relative.
public enum ViewerBookingState: String, Codable, Sendable {
    case suggested, awaitingYou, awaitingOther, confirmed, declined, expired, canceled, completed
}

public struct Proposal: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var participants: [String]
    public var start: Date
    public var end: Date
    public var createdAt: Date
    public var expiresAt: Date
    /// A person id, or "agent". The agent can create proposals but never consent.
    public var createdBy: String
    public var status: ProposalStatus
    /// Participant → when they explicitly confirmed. Only participants write their own entry.
    public var confirmations: [String: Date]
    public var declinedBy: String?
    public var canceledBy: String?
    public var explanation: String
    public var version: Int
    public var feedback: FeedbackChoice?
    public var rescheduledFromID: String?

    public init(id: String, participants: [String], start: Date, end: Date, createdAt: Date,
                expiresAt: Date, createdBy: String, explanation: String, rescheduledFromID: String? = nil) {
        self.id = id; self.participants = participants.sorted(); self.start = start; self.end = end
        self.createdAt = createdAt; self.expiresAt = expiresAt; self.createdBy = createdBy
        self.status = .suggested; self.confirmations = [:]; self.explanation = explanation
        self.version = 0; self.rescheduledFromID = rescheduledFromID
    }

    public var interval: Interval { .init(start: start, end: end) }

    public func viewerState(_ viewer: String) -> ViewerBookingState {
        switch status {
        case .suggested: return .suggested
        case .pending: return confirmations[viewer] == nil ? .awaitingYou : .awaitingOther
        case .confirmed: return .confirmed
        case .declined: return .declined
        case .expired: return .expired
        case .canceled: return .canceled
        case .completed: return .completed
        }
    }
}

public enum BookingAction: Sendable {
    case confirm(by: String), decline(by: String), cancel(by: String), complete
}

public enum RejectReason: String, Error, Sendable {
    case notParticipant, expired, alreadyDecided, notConfirmed, notEnded, availabilityChanged, notFound
    case agentCannotConsent
}

public enum TransitionResult: Sendable {
    case applied(Proposal)
    /// Idempotent repeat: nothing changed.
    case unchanged(Proposal)
    case rejected(RejectReason)
}

/// Pure state machine. No I/O, no clock access: `now` is injected.
public enum BookingStateMachine {
    /// Expires stale open proposals (past expiry or start) and completes finished calls.
    public static func normalized(_ p: Proposal, now: Date) -> Proposal {
        var q = p
        if q.status.isOpen && (now >= q.expiresAt || now >= q.start) {
            q.status = .expired; q.version += 1
        } else if q.status == .confirmed && now >= q.end {
            q.status = .completed; q.version += 1
        }
        return q
    }

    public static func apply(_ action: BookingAction, to proposal: Proposal, now: Date) -> TransitionResult {
        var p = normalized(proposal, now: now)
        let normalizedChanged = p.version != proposal.version

        switch action {
        case .confirm(let who):
            guard p.participants.contains(who) else { return .rejected(.notParticipant) }
            switch p.status {
            case .expired: return .rejected(.expired)
            case .declined, .canceled, .completed: return .rejected(.alreadyDecided)
            case .confirmed: return .unchanged(p)
            case .suggested, .pending:
                if p.confirmations[who] != nil { return .unchanged(p) }
                p.confirmations[who] = now
                p.status = Set(p.confirmations.keys) == Set(p.participants) ? .confirmed : .pending
                p.version += 1
                return .applied(p)
            }
        case .decline(let who):
            guard p.participants.contains(who) else { return .rejected(.notParticipant) }
            switch p.status {
            case .declined: return .unchanged(p)
            case .suggested, .pending:
                p.status = .declined; p.declinedBy = who; p.version += 1
                return .applied(p)
            case .expired: return .rejected(.expired)
            default: return .rejected(.alreadyDecided)
            }
        case .cancel(let who):
            guard p.participants.contains(who) else { return .rejected(.notParticipant) }
            switch p.status {
            case .canceled: return .unchanged(p)
            case .pending, .confirmed, .suggested:
                p.status = .canceled; p.canceledBy = who; p.version += 1
                return .applied(p)
            case .expired: return .rejected(.expired)
            default: return .rejected(.alreadyDecided)
            }
        case .complete:
            switch p.status {
            case .completed: return normalizedChanged ? .applied(p) : .unchanged(p)
            case .confirmed: return .rejected(.notEnded)
            default: return .rejected(.notConfirmed)
            }
        }
    }
}
