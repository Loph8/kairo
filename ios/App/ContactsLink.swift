import Contacts
import Foundation
import GoldenHourCore
import UIKit

/// Links each family member to a contact on this phone, for their photo and a number to call.
/// Contacts are read on the phone only. Nothing from them is sent to the family server.
@MainActor @Observable
final class ContactsLink {
    enum Access: Equatable { case notAsked, granted, limited, denied }

    struct Linked: Equatable {
        var contactID: String
        var displayName: String
        var phone: String?
        var email: String?
        var thumbnail: Data?
        /// FaceTime audio to the phone number, or the email if there's no number.
        var callURL: URL? {
            guard let raw = phone ?? email else { return nil }
            let cleaned = phone != nil ? raw.filter { $0.isNumber || $0 == "+" } : raw
            guard !cleaned.isEmpty,
                  let enc = cleaned.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return nil }
            return URL(string: "facetime-audio://\(enc)")
        }
    }

    private let store = CNContactStore()
    private let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private static let linksKey = "gh.contactLinks"   // memberID → contact identifier
    private(set) var access: Access = ContactsLink.currentAccess()
    private(set) var linked: [String: Linked] = [:]

    private static let keys: [CNKeyDescriptor] = [
        CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
        CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactThumbnailImageDataKey,
        CNContactRelationsKey,
    ].map { $0 as CNKeyDescriptor } + [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]

    static func currentAccess() -> Access {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: .granted
        case .notDetermined: .notAsked
        case .limited: .limited     // iOS 18: the user shared only some contacts
        default: .denied
        }
    }

    var canRead: Bool { access == .granted || access == .limited }

    func requestAccess() async -> Bool {
        do { _ = try await store.requestAccess(for: .contacts) } catch { /* status below is the truth */ }
        access = Self.currentAccess()
        return canRead
    }

    /// Reloads saved links, and for members with no link yet, guesses one by name or nickname
    /// ("Mom" saved as "Mom", "Mum", "Mother", or a contact whose relation to me is mother).
    func refresh(members: [ServerState.Member], me: String) {
        access = Self.currentAccess()
        guard canRead else { linked = [:]; return }
        var ids = savedLinks()
        let unlinked = members.filter { $0.id != me && ids[$0.id] == nil }
        let all = unlinked.isEmpty ? [] : allContacts()   // full scan only when there's something to match
        for m in unlinked {
            if let match = Self.bestMatch(for: m, in: all) { ids[m.id] = match.identifier }
        }
        saveLinks(ids)
        var out: [String: Linked] = [:]
        for (memberID, contactID) in ids {
            if let c = all.first(where: { $0.identifier == contactID }) ?? fetch(contactID) { out[memberID] = Self.linked(c) }
        }
        linked = out
    }

    func allContacts() -> [CNContact] {
        guard canRead else { return [] }
        var result: [CNContact] = []
        let req = CNContactFetchRequest(keysToFetch: Self.keys)
        req.sortOrder = .userDefault
        do { try store.enumerateContacts(with: req) { c, _ in result.append(c) } } catch { return [] }
        return result
    }

    func link(memberID: String, to contact: CNContact) {
        var ids = savedLinks(); ids[memberID] = contact.identifier; saveLinks(ids)
        linked[memberID] = Self.linked(contact)
    }

    func unlink(memberID: String) {
        var ids = savedLinks(); ids[memberID] = nil; saveLinks(ids)
        linked[memberID] = nil
    }

    // MARK: private

    private func fetch(_ id: String) -> CNContact? { try? store.unifiedContact(withIdentifier: id, keysToFetch: Self.keys) }
    private func savedLinks() -> [String: String] { defaults.dictionary(forKey: Self.linksKey) as? [String: String] ?? [:] }
    private func saveLinks(_ ids: [String: String]) { defaults.set(ids, forKey: Self.linksKey) }

    static func linked(_ c: CNContact) -> Linked {
        let name = CNContactFormatter.string(from: c, style: .fullName) ?? c.nickname
        return Linked(contactID: c.identifier,
                      displayName: name.isEmpty ? "Contact" : name,
                      phone: c.phoneNumbers.first(where: { $0.label == CNLabelPhoneNumberMobile || $0.label == CNLabelPhoneNumberiPhone })?.value.stringValue
                          ?? c.phoneNumbers.first?.value.stringValue,
                      email: c.emailAddresses.first.map { String($0.value) },
                      thumbnail: c.thumbnailImageData)
    }

    /// Words people save family under, keyed by the server's member id.
    static let aliases: [String: [String]] = [
        "mom": ["mom", "mum", "mother", "mama", "mommy", "엄마", "어머니"],
        "dad": ["dad", "father", "papa", "daddy", "아빠", "아버지"],
        "grandpa": ["grandpa", "grandfather", "granddad", "grandad", "할아버지"],
        "grandma": ["grandma", "grandmother", "granny", "할머니"],
        "sis": ["sis", "sister", "언니", "누나", "동생"],
    ]
    static let relationLabels: [String: [String]] = [
        "mom": [CNLabelContactRelationMother], "dad": [CNLabelContactRelationFather],
        "sis": [CNLabelContactRelationSister],
    ]

    static func bestMatch(for m: ServerState.Member, in contacts: [CNContact]) -> CNContact? {
        let words = Set((aliases[m.id] ?? []) + [m.name.lowercased()])
        func norm(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespaces) }
        if let c = contacts.first(where: { words.contains(norm($0.nickname)) || words.contains(norm($0.givenName))
            || words.contains(norm("\($0.givenName) \($0.familyName)")) }) { return c }
        // A "me" card that lists this person as my mother/father: match by that relation's name.
        let labels = relationLabels[m.id] ?? []
        let relNames = contacts.flatMap(\.contactRelations).filter { labels.contains($0.label ?? "") }.map { norm($0.value.name) }
        return contacts.first { relNames.contains(norm(CNContactFormatter.string(from: $0, style: .fullName) ?? "")) }
    }
}
