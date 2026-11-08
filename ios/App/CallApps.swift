import UIKit

/// The apps a family member can be called on. Kairos only opens the other app; it never reads it.
/// When you come back, the app asks "Did they pick up?", which is the only signal it learns from.
///
/// What iOS allows: FaceTime and the phone dialer can start a call directly. WhatsApp, Instagram,
/// Messenger, Telegram and LINE open the chat with that person, one tap from their call button.
/// KakaoTalk and WeChat have no public link to a specific person, so they open the app.
enum CallApp: String, CaseIterable, Codable, Identifiable {
    case facetimeAudio, facetimeVideo, phone, whatsapp, kakaotalk, wechat, line, telegram, messenger, instagram

    enum Handle { case phoneOrEmail, phone, username, none }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .facetimeAudio: return "FaceTime Audio"
        case .facetimeVideo: return "FaceTime Video"
        case .phone: return "Phone"
        case .whatsapp: return "WhatsApp"
        case .kakaotalk: return "KakaoTalk"
        case .wechat: return "WeChat"
        case .line: return "LINE"
        case .telegram: return "Telegram"
        case .messenger: return "Messenger"
        case .instagram: return "Instagram"
        }
    }

    var symbol: String {
        switch self {
        case .facetimeAudio, .phone: return "phone.fill"
        case .facetimeVideo: return "video.fill"
        case .instagram: return "camera.fill"
        default: return "bubble.left.and.bubble.right.fill"
        }
    }

    var handle: Handle {
        switch self {
        case .facetimeAudio, .facetimeVideo: return .phoneOrEmail
        case .phone, .whatsapp: return .phone
        case .telegram, .messenger, .instagram, .line: return .username
        case .kakaotalk, .wechat: return .none
        }
    }

    /// Shown under the app name so nobody expects more than iOS allows.
    var whatHappens: String {
        switch self {
        case .facetimeAudio, .facetimeVideo, .phone: return "Starts the call"
        case .whatsapp, .telegram, .messenger, .instagram: return "Opens your chat, tap the call button"
        case .line: return "Opens their profile, tap call"
        case .kakaotalk, .wechat: return "Opens the app, pick them and call"
        }
    }

    var handlePrompt: String {
        switch self {
        case .facetimeAudio, .facetimeVideo: return "Phone number or Apple ID email"
        case .phone, .whatsapp: return "Phone number with country code, e.g. +82 10 1234 5678"
        case .telegram: return "Telegram username"
        case .messenger: return "Facebook username"
        case .instagram: return "Instagram username"
        case .line: return "LINE ID"
        case .kakaotalk, .wechat: return ""
        }
    }

    /// Scheme used to check the app is installed (must be listed in LSApplicationQueriesSchemes).
    private var probe: URL? {
        switch self {
        case .facetimeAudio, .facetimeVideo, .phone: return nil   // always on iPhone
        case .whatsapp: return URL(string: "whatsapp://")
        case .kakaotalk: return URL(string: "kakaotalk://")
        case .wechat: return URL(string: "weixin://")
        case .line: return URL(string: "line://")
        case .telegram: return URL(string: "tg://")
        case .messenger: return URL(string: "fb-messenger://")
        case .instagram: return URL(string: "instagram://")
        }
    }

    @MainActor var isInstalled: Bool {
        guard let probe else { return true }
        return UIApplication.shared.canOpenURL(probe)
    }

    func url(handle raw: String?) -> URL? {
        let h = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = h.filter { $0.isNumber || $0 == "+" }
        let user = h.hasPrefix("@") ? String(h.dropFirst()) : h
        let safeUser = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
        switch self {
        case .facetimeAudio, .facetimeVideo:
            let target = h.contains("@") ? h : digits
            guard !target.isEmpty else { return nil }
            return URL(string: (self == .facetimeAudio ? "facetime-audio://" : "facetime://") + target)
        case .phone:
            return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
        case .whatsapp:
            let n = digits.filter(\.isNumber)
            return n.isEmpty ? nil : URL(string: "whatsapp://send?phone=\(n)")
        case .telegram:
            return user.isEmpty ? nil : URL(string: "tg://resolve?domain=\(safeUser)")
        case .messenger:
            return user.isEmpty ? nil : URL(string: "https://m.me/\(safeUser)")
        case .instagram:
            return user.isEmpty ? nil : URL(string: "https://ig.me/m/\(safeUser)")
        case .line:
            return user.isEmpty ? URL(string: "line://") : URL(string: "https://line.me/R/ti/p/~\(safeUser)")
        case .kakaotalk:
            return URL(string: "kakaotalk://")
        case .wechat:
            return URL(string: "weixin://")
        }
    }
}

/// Which app and handle to use for each family member. Kept on this phone only, never uploaded.
struct CallChoice: Codable, Equatable {
    var app: CallApp
    var handle: String?
}

enum CallChoices {
    private static let key = "gh.callChoices"
    private static var defaults: UserDefaults { UserDefaults(suiteName: AppGroup.identifier) ?? .standard }

    static func all() -> [String: CallChoice] {
        guard let data = defaults.data(forKey: key),
              let map = try? JSONDecoder().decode([String: CallChoice].self, from: data) else { return [:] }
        return map
    }

    static func save(_ choice: CallChoice?, for memberID: String) {
        var map = all()
        map[memberID] = choice
        if let data = try? JSONEncoder().encode(map) { defaults.set(data, forKey: key) }
    }
}
