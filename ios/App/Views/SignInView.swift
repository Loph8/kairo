import SwiftUI
import GoldenHourCore

/// Email → 6-digit code. No passwords.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var code = ""
    @State private var sentTo: String?
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case email, code }

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)
            hero
            GlassGroup(spacing: 20) {
                VStack(spacing: 16) {
                    if let sentTo { codeStep(sentTo) } else { emailStep }
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(Night.font(13)).foregroundStyle(GH.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                }
                .padding(22)
                .glassSurface(cornerRadius: 32)
            }
            .animation(.smooth, value: sentTo)
            .animation(.smooth, value: error)
            Spacer()
            #if targetEnvironment(simulator)
            Button {
                Task { await model.startLocalDemo() }
            } label: {
                Label("Try the demo (no sign-in)", systemImage: "sparkles")
                    .font(Night.font(15, .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(GH.ink)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .glassSurface(cornerRadius: 22)
            #endif
            Text("We only know when you talk, never what you say.")
                .font(Night.font(13)).foregroundStyle(GH.inkSoft).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .onAppear { focus = .email }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            KairosLogo(size: 96)
                .shadow(color: GH.apricot.opacity(0.35), radius: 18)   // the widget's in-sync glow
                .modifier(Breathe())
            Text("Kairos").font(Night.font(34, .bold)).foregroundStyle(GH.ink)
            Text("Call your family when they can actually pick up.")
                .font(Night.font(16)).foregroundStyle(GH.inkSoft).multilineTextAlignment(.center)
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in with your email").font(Night.font(17, .bold)).foregroundStyle(GH.ink)
            TextField("", text: $email, prompt: Text("you@example.com").foregroundStyle(GH.inkSoft.opacity(0.6)))
                .foregroundStyle(GH.ink).tint(GH.apricot)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focus, equals: .email).submitLabel(.send).onSubmit(send)
                .padding(14).background(GH.night.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button(action: send) {
                HStack { if busy { ProgressView() }; Text("Email me a code").bold() }.frame(maxWidth: .infinity)
            }
            .primaryGlassButton()
            .disabled(busy || email.isEmpty)
        }
    }

    private func codeStep(_ address: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Check your email").font(Night.font(17, .bold)).foregroundStyle(GH.ink)
            Text("We sent a code to \(address).").font(Night.font(15)).foregroundStyle(GH.inkSoft)
            TextField("", text: $code, prompt: Text("123456").foregroundStyle(GH.inkSoft.opacity(0.4)))
                .foregroundStyle(GH.ink).tint(GH.apricot)
                .textContentType(.oneTimeCode).keyboardType(.numberPad)
                .font(Night.font(30, .bold)).tracking(8)
                .multilineTextAlignment(.center)
                .focused($focus, equals: .code)
                .padding(14).glassSurface(cornerRadius: 16, interactive: true)
                .onChange(of: code) { _, new in if new.count >= 6, AuthClient.normalizedCode(new) != nil { verify() } }
            Button(action: verify) {
                HStack { if busy { ProgressView() }; Text("Sign in").bold() }.frame(maxWidth: .infinity)
            }
            .primaryGlassButton()
            .disabled(busy || code.count < 6)
            HStack {
                Button("Use a different email") { withAnimation { sentTo = nil; code = ""; error = nil; focus = .email } }
                Spacer()
                Button("Resend") { send() }.disabled(busy)
            }
            .font(Night.font(13)).foregroundStyle(GH.inkSoft)
        }
    }

    private func send() {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await model.sendCode(to: address)
                withAnimation { sentTo = AuthClient.normalizedEmail(address) ?? address }
                focus = .code
            } catch { self.error = message(error) }
        }
    }

    private func verify() {
        guard let sentTo, !busy else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await model.verify(email: sentTo, code: code)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.error = message(error)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Check your connection and try again."
    }
}

/// A slow breathing pulse on the sun (iOS 18+); still on older systems.
private struct Breathe: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) { content.symbolEffect(.breathe, options: .repeating) } else { content }
    }
}
