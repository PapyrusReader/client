import Flutter
import UIKit
import ActivityKit

@MainActor
final class TimerActivityBridge {
    private let channel: FlutterMethodChannel
    private var observer: NSObjectProtocol?

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "papyrus/reading_timer", binaryMessenger: messenger)
        observer = NotificationCenter.default.addObserver(forName: Notification.Name("PapyrusTimerChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.channel.invokeMethod("changed", arguments: nil)
        }
        channel.setMethodCallHandler { [weak self] call, result in
            Task { @MainActor in
                guard self != nil else { result(nil); return }
                do {
                    var journal = try TimerJournal.load()
                    let arguments = call.arguments as? [String: Any] ?? [:]
                    let snapshot = try (arguments["snapshot"] as? [String: Any]).map {
                        try JSONDecoder().decode(TimerSnapshot.self, from: JSONSerialization.data(withJSONObject: $0))
                    }
                    switch call.method {
                    case "pending":
                        if let base = journal.base, let last = journal.actions.last {
                            let actions = try JSONSerialization.jsonObject(with: JSONEncoder().encode(journal.actions))
                            result(["sessionId": base.id, "version": base.version, "through": last.id, "actions": actions])
                        } else { result(nil) }
                        return
                    case "publish":
                        if journal.actions.isEmpty {
                            journal.base = snapshot
                            try journal.save()
                        }
                    case "acknowledge":
                        if let through = arguments["through"] as? String {
                            try journal.acknowledge(through: through, snapshot: snapshot)
                        }
                    case "clear": try TimerJournal().save()
                    default: result(FlutterMethodNotImplemented); return
                    }
                    if #available(iOS 16.2, *) {
                        try await TimerLiveActivity.refresh(allowStart: arguments["foreground"] as? Bool == true && UIApplication.shared.applicationState == .active)
                    }
                    result(nil)
                } catch {
                    result(FlutterError(code: "notification", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
