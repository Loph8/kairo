import CallKit
import UIKit

/// Watches the call Kairos just started and notes whether it connected.
/// iOS only reports that a call exists and its state, never the number or what was said.
/// Kairos asks for ~30 s of background time after handing off to FaceTime; if the call
/// connects in that window we know they picked up without asking.
@MainActor
final class CallDetector: NSObject, CXCallObserverDelegate {
    enum Outcome { case connected, notConnected, unknown }

    private let observer = CXCallObserver()
    private var sawOutgoing = false
    private var connected = false
    private var ended = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
    }

    /// Call right before opening the call app.
    func start() {
        sawOutgoing = false
        connected = false
        ended = false
        endBackgroundTime()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "kairos.call-watch") { [weak self] in
            self?.endBackgroundTime()
        }
    }

    /// What we saw, read once when the user comes back to Kairos.
    func finish() -> Outcome {
        endBackgroundTime()
        defer { sawOutgoing = false; connected = false; ended = false }
        if connected { return .connected }
        if sawOutgoing && ended { return .notConnected }
        return .unknown   // didn't see the call in time: fall back to asking
    }

    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let outgoing = call.isOutgoing, didConnect = call.hasConnected, didEnd = call.hasEnded
        MainActor.assumeIsolated {
            guard outgoing else { return }
            sawOutgoing = true
            if didConnect { connected = true }
            if didEnd { ended = true }
            if connected || ended { endBackgroundTime() }   // we have our answer
        }
    }

    private func endBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
