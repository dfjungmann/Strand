import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

extension Notification.Name {
    static let watchSettingsDidUpdate = Notification.Name("watchSettingsDidUpdate")
}

/// Überträgt Referenz-Offset und Zeitkorrektur vom iPhone auf die Watch (WatchConnectivity).
#if canImport(WatchConnectivity)
final class WatchSettingsSync: NSObject, @unchecked Sendable {
    static let shared = WatchSettingsSync()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    #if os(iOS)
    func pushFromPhone() {
        guard WCSession.default.activationState == .activated else { return }
        let context = contextFromPhoneDefaults()
        guard !context.isEmpty else { return }
        try? WCSession.default.updateApplicationContext(context)
    }
    #endif

    #if os(watchOS)
    func applyStoredContext() {
        let ctx = WCSession.default.receivedApplicationContext
        guard !ctx.isEmpty else { return }
        applyContext(ctx)
    }
    #endif

    #if os(iOS)
    private func contextFromPhoneDefaults() -> [String: Any] {
        let d = UserDefaults.standard
        var ctx: [String: Any] = [:]
        for key in TideSettingsKeys.watchSyncKeys {
            if let v = d.object(forKey: key) {
                ctx[key] = v
            }
        }
        return ctx
    }
    #endif

    private func applyContext(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        let defaults = UserDefaults.standard
        var changed = false
        for key in TideSettingsKeys.watchSyncKeys {
            if let v = context[key] {
                defaults.set(v, forKey: key)
                changed = true
            }
        }
        if changed {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .watchSettingsDidUpdate, object: nil)
            }
        }
    }
}

extension WatchSettingsSync: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: (any Error)?) {
        #if os(watchOS)
        DispatchQueue.main.async { [self] in
            applyStoredContext()
        }
        #endif
        #if os(iOS)
        pushFromPhone()
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        pushFromPhone()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            pushFromPhone()
        }
    }
    #endif

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [self] in
            applyContext(applicationContext)
        }
    }
}
#endif
