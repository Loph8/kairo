import Contacts
import SwiftUI
import GoldenHourCore

/// Contact photo when the member is linked to a contact, initials otherwise.
struct MemberAvatar: View {
    @Environment(AppModel.self) private var model
    let member: ServerState.Member
    var size: CGFloat = 32
    var body: some View {
        if let data = model.contacts.linked[member.id]?.thumbnail, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: size, height: size).clipShape(Circle())
                .overlay(Circle().strokeBorder(GH.apricot.opacity(0.6), lineWidth: 1))
                .accessibilityHidden(true)
        } else {
            Avatar(initials: String(member.name.prefix(1)), size: size,
                   tint: MemberPalette.color(model.members.firstIndex(where: { $0.id == member.id }) ?? 0))
        }
    }
}

/// Contacts status and links, shown on the Family tab.
struct ContactsCard: View {
    @Environment(AppModel.self) private var model
    @State private var picking: ServerState.Member?

    var body: some View {
        let c = model.contacts
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.crop.circle").font(Night.font(22, .bold)).foregroundStyle(GH.apricot)
                    VStack(alignment: .leading, spacing: 4) {
                        switch c.access {
                        case .granted, .limited:
                            Text("Family in your contacts").font(Night.font(17, .bold))
                            Text(c.access == .limited
                                 ? "You shared only some contacts. Add family in Settings → Kairos → Contacts if someone is missing."
                                 : "Used for photos and calling. Contacts never leave your phone.")
                                .font(Night.font(12)).foregroundStyle(GH.inkSoft)
                        case .notAsked:
                            Text("Call family from here").font(Night.font(17, .bold))
                            Text("Match your family to your contacts for their photos and a one-tap FaceTime call. Contacts never leave your phone.")
                                .font(Night.font(12)).foregroundStyle(GH.inkSoft)
                            Button("Connect contacts") { Task { await model.connectContacts() } }
                                .buttonStyle(.borderedProminent).foregroundStyle(GH.night)
                        case .denied:
                            Text("Contacts are off").font(Night.font(17, .bold))
                            Text("Turn on Settings → Kairos → Contacts to call family from here.")
                                .font(Night.font(12)).foregroundStyle(GH.inkSoft)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if c.canRead {
                    ForEach(model.liveOthers, id: \.id) { m in
                        HStack {
                            MemberAvatar(member: m, size: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(m.name).font(Night.font(15, .bold))
                                Text(c.linked[m.id].map { "\($0.displayName)\($0.callURL == nil ? " · no number" : "")" } ?? "Not linked")
                                    .font(Night.font(12)).foregroundStyle(GH.inkSoft)
                            }
                            Spacer()
                            Button(c.linked[m.id] == nil ? "Choose" : "Change") { picking = m }
                                .font(Night.font(12, .bold))
                        }
                    }
                }
            }
        }
        .sheet(item: $picking) { m in ContactPicker(member: m) }
    }
}


/// Searchable list of this phone's contacts, to link one to a family member.
struct ContactPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let member: ServerState.Member
    @State private var all: [CNContact] = []
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if model.contacts.linked[member.id] != nil {
                    Button("Unlink \(member.name)", role: .destructive) {
                        model.contacts.unlink(memberID: member.id); dismiss()
                    }
                }
                ForEach(filtered, id: \.identifier) { c in
                    Button {
                        model.contacts.link(memberID: member.id, to: c); dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(Self.name(c)).foregroundStyle(GH.ink)
                            if let p = c.phoneNumbers.first?.value.stringValue {
                                Text(p).font(Night.font(12)).foregroundStyle(GH.inkSoft)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("Who is \(member.name)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { all = model.contacts.allContacts() }
        }
    }

    var filtered: [CNContact] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? all : all.filter { Self.name($0).lowercased().contains(q) || $0.nickname.lowercased().contains(q) }
    }

    static func name(_ c: CNContact) -> String {
        let n = CNContactFormatter.string(from: c, style: .fullName) ?? ""
        return n.isEmpty ? (c.nickname.isEmpty ? "No name" : c.nickname) : n
    }
}
