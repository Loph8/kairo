import Testing
import Foundation
@testable import GoldenHourCore

@Suite struct BackendTests {
    static let json = """
    {"ok":true,"state":{
      "now":"2026-11-10T01:12:00.000Z","forecastStart":"2026-11-10T01:00:00.000Z","slotMinutes":30,"isDemo":true,
      "members":[
        {"id":"you","name":"You","city":"Durham","tz":"America/New_York","simulated":false,"week":"GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG","said":"YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY","insights":["Usually free after 8 PM"],"signals":12,"levels":["G","Y","R"]},
        {"id":"mom","name":"Mom","city":"Seoul","tz":"Asia/Seoul","simulated":true,"week":"GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG","said":"YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY","insights":["Usually free after 8 PM"],"signals":12,"levels":["R","G","X"]},
        {"id":"dad","name":"Dad","city":"Seoul","tz":"Asia/Seoul","simulated":true,"week":"GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG","said":"YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY","insights":["Usually free after 8 PM"],"signals":12,"levels":["Y","Y","Y"]}],
      "suggestion":{"start":"2026-11-10T23:00:00.000Z","end":"2026-11-10T23:45:00.000Z",
        "pickup":{"you":0.86,"mom":0.86,"dad":0.08},"levels":{"you":"G","mom":"G","dad":"R"},"everyoneLikely":false},
      "moves":[{"blockId":"demo-gym","memberId":"you","from":"2026-11-10T12:00:00.000Z",
        "to":"2026-11-10T13:00:00.000Z","frees":"2026-11-10T12:00:00.000Z","gain":2.4}],
      "bookings":[{"id":"b1","start":"2026-11-10T12:00:00.000Z","end":"2026-11-10T12:45:00.000Z",
        "acceptedBy":["mom"],"status":"proposed"}],
      "lastChange":{"memberId":"mom","at":"2026-11-10T01:10:00.000Z","source":"sim","kind":"label","positive":false,
        "changed":[{"cell":20,"from":"G","to":"Y"}]},"note":null},
     "account":{"email":"a@b.co","familyName":"Kims","inviteCode":"KQ7MZ2","memberId":"you"}}
    """

    struct Wrapped: Decodable { var state: ServerState }

    func decoded() throws -> ServerState {
        try BackendClient.decoder.decode(Wrapped.self, from: Data(Self.json.utf8)).state
    }

    @Test func configRejectsPlaceholdersAndHTTP() {
        #expect(BackendConfig(info: nil) == nil)
        #expect(BackendConfig(info: ["SUPABASE_URL": "https://YOUR-PROJECT.supabase.co", "SUPABASE_ANON_KEY": "k"]) == nil)
        #expect(BackendConfig(info: ["SUPABASE_URL": "http://x.supabase.co", "SUPABASE_ANON_KEY": "k"]) == nil)
        #expect(BackendConfig(info: ["SUPABASE_URL": "https://x.supabase.co", "SUPABASE_ANON_KEY": ""]) == nil)
        let ok = BackendConfig(info: ["SUPABASE_URL": "https://x.supabase.co", "SUPABASE_ANON_KEY": "sb_publishable_1"])
        #expect(ok?.endpoint.absoluteString == "https://x.supabase.co/functions/v1/api")
    }

    @Test func decodesServerDatesWithMilliseconds() throws {
        let s = try decoded()
        #expect(s.now == Date(timeIntervalSince1970: 1_794_273_120))
        #expect(s.members.count == 3)
        #expect(s.moves.first?.blockId == "demo-gym")
        #expect(s.members[1].simulated && s.members[1].week.count == 96)
        #expect(s.lastChange?.changed == [.init(cell: 20, from: "G", to: "Y")])
        #expect(s.note == nil)
    }

    @Test func noteReplacesTheBuiltInExplanation() throws {
        var s = try decoded()
        s.note = "8:00 PM for you, 10:00 AM for Mom."
        #expect(ServerSnapshot.familyCalls(s, viewerID: "you").last?.explanation == "8:00 PM for you, 10:00 AM for Mom.")
    }

    @Test func signedOutIsRecognised() {
        #expect(BackendError.server(status: 401, message: "sign in first").isSignedOut)
        #expect(!BackendError.server(status: 409, message: "x").isSignedOut)
        #expect(BackendError.server(status: 409, message: "create or join a family first").errorDescription == "Create or join a family first.")
    }

    @Test func mapsLevels() {
        #expect(ServerSnapshot.level("G") == .likelyFree)
        #expect(ServerSnapshot.level("Y") == .maybeFree)
        #expect(ServerSnapshot.level("R") == .unlikely)
        #expect(ServerSnapshot.level("?") == .learning)
    }

    @Test func proposalIDRoundTripsAndPassesDeepLinkValidation() {
        let start = Date(timeIntervalSince1970: 1_762_815_600)
        let id = FamilyProposalID.make(start)
        #expect(DeepLink.validID(id))
        #expect(FamilyProposalID.start(of: id) == start)
        #expect(FamilyProposalID.start(of: "p-123") == nil)
    }

    @Test func viewerStateFollowsWhoJoined() throws {
        let b = try decoded().bookings[0]
        #expect(ServerSnapshot.viewerState(b, viewerID: "mom") == .awaitingOther)
        #expect(ServerSnapshot.viewerState(b, viewerID: "you") == .awaitingYou)
        var booked = b; booked.status = "booked"
        #expect(ServerSnapshot.viewerState(booked, viewerID: "you") == .confirmed)
    }

    @Test func snapshotUsesServerClockAndShowsCallsToEveryOtherMember() throws {
        let s = try decoded()
        let real = Date(timeIntervalSince1970: 2_000_000_000)
        let snap = ServerSnapshot.make(s, viewerID: "you", realNow: real)
        #expect(snap.clockOffset == s.now.timeIntervalSince(real))
        #expect(snap.people.map(\.id) == ["mom", "dad"])
        #expect(snap.people[0].forecast == [.unlikely, .likelyFree, .learning])
        #expect(snap.viewerForecast == [.likelyFree, .maybeFree, .unlikely])
        #expect(snap.sync == .synced(real))
        // booking at 12:00 + suggestion at 23:00, for each of the 2 others
        #expect(snap.proposals.count == 4)
        let mom = snap.proposals.filter { $0.personID == "mom" }
        #expect(mom.map(\.state) == [.awaitingYou, .suggested])
        #expect(mom[1].explanation.contains("Dad may not pick up"))
        #expect(mom[1].explanation.contains("Moving one calendar event"))
    }

    @Test func suggestionIsHiddenOnceItIsBooked() throws {
        var s = try decoded()
        s.bookings[0].start = s.suggestion!.start
        let calls = ServerSnapshot.familyCalls(s, viewerID: "you")
        #expect(calls.count == 1)
    }
}
