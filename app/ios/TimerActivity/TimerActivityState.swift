import Foundation
import ActivityKit
import AppIntents

struct TimerSnapshot: Codable, Hashable {
    var id: String
    var version: String
    var title: String
    var phase: String
    var recordedMs: Int64
    var runningSinceMs: Int64?
    var targetMs: Int64?
    var token: String?

    var controlToken: String { token ?? version }
    var deadline: Date? {
        guard let start = runningSinceMs, let target = targetMs else { return nil }
        return Date(timeIntervalSince1970: Double(start + target - recordedMs) / 1000)
    }

    func elapsed(at: Int64) -> Int64 {
        let total = recordedMs + (runningSinceMs.map { max(0, at - $0) } ?? 0)
        return targetMs.map { min($0, total) } ?? total
    }
}

struct TimerNativeAction: Codable {
    let id: String
    let kind: String
    let atMs: Int64
}

/// Only the app process writes this journal. LiveActivityIntent runs there too.
struct TimerJournal: Codable {
    var base: TimerSnapshot?
    var actions: [TimerNativeAction] = []

    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reading-timer-notification.json")
    }

    static func load() throws -> TimerJournal {
        guard FileManager.default.fileExists(atPath: file.path) else { return TimerJournal() }
        return try JSONDecoder().decode(TimerJournal.self, from: Data(contentsOf: file))
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func view(at: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> TimerSnapshot? {
        guard var value = base else { return nil }
        for action in actions {
            value.recordedMs = value.elapsed(at: action.atMs)
            value.runningSinceMs = nil
            value.token = action.id
            switch action.kind {
            case "pause": value.phase = "paused"
            case "resume": value.phase = "running"; value.runningSinceMs = action.atMs
            case "finish": return nil
            default: break
            }
        }
        if let target = value.targetMs, value.elapsed(at: at) >= target {
            value.phase = "finished"
            value.recordedMs = target
            value.runningSinceMs = nil
        }
        return value
    }

    mutating func record(sessionId: String, token: String, kind: String) throws {
        guard let current = view(), current.id == sessionId, current.controlToken == token else { return }
        guard ["pause", "resume", "finish"].contains(kind), actions.count < 256 else { return }
        if kind == "pause" && current.phase != "running" { return }
        if kind == "resume" && current.phase != "paused" { return }
        actions.append(TimerNativeAction(id: UUID().uuidString, kind: kind, atMs: Int64(Date().timeIntervalSince1970 * 1000)))
        try save()
    }

    mutating func acknowledge(through: String, snapshot: TimerSnapshot?) throws {
        guard let index = actions.firstIndex(where: { $0.id == through }) else { return }
        actions = snapshot?.id == base?.id ? Array(actions.dropFirst(index + 1)) : []
        base = snapshot
        try save()
    }
}

@available(iOS 16.2, *)
struct ReadingTimerAttributes: ActivityAttributes {
    typealias ContentState = TimerSnapshot
    var sessionId: String
}

@available(iOS 16.2, *)
@MainActor
enum TimerLiveActivity {
    private static var updating = false
    private static var requested = false
    private static var mayStart = false

    static func refresh(allowStart: Bool = false) async throws {
        requested = true
        mayStart = mayStart || allowStart
        guard !updating else { return }
        updating = true
        defer { updating = false }
        while requested {
            requested = false
            let start = mayStart
            mayStart = false
            let snapshot = try TimerJournal.load().view()
            let activities = Activity<ReadingTimerAttributes>.activities
            for activity in activities where activity.attributes.sessionId != snapshot?.id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            guard let snapshot else { continue }
            let content = ActivityContent(state: snapshot, staleDate: snapshot.deadline)
            if let activity = activities.first(where: { $0.attributes.sessionId == snapshot.id }) {
                await activity.update(content)
            } else if start && snapshot.phase != "finished" && ActivityAuthorizationInfo().areActivitiesEnabled {
                _ = try Activity.request(attributes: ReadingTimerAttributes(sessionId: snapshot.id), content: content, pushType: nil)
            }
        }
    }
}

@available(iOS 17.0, *)
struct ReadingTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Control reading timer"
    static var openAppWhenRun = false

    @Parameter(title: "Session") var sessionId: String
    @Parameter(title: "Version") var token: String
    @Parameter(title: "Action") var kind: String

    init() {}
    init(sessionId: String, token: String, kind: String) {
        self.sessionId = sessionId
        self.token = token
        self.kind = kind
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        var journal = try TimerJournal.load()
        try journal.record(sessionId: sessionId, token: token, kind: kind)
        try await TimerLiveActivity.refresh()
        NotificationCenter.default.post(name: Notification.Name("PapyrusTimerChanged"), object: nil)
        return .result()
    }
}
