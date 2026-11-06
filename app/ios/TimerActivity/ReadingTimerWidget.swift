import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ReadingTimerWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingTimerAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "book.closed").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.title).font(.headline).lineLimit(2).privacySensitive()
                        Text(status(context)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    TimerClock(snapshot: context.state).font(.title2.monospacedDigit())
                }
                TimerControls(snapshot: context.state, complete: context.isStale)
            }
            .padding(16)
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "papyrus:///library/timer"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Reading", systemImage: "book.closed").font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerClock(snapshot: context.state).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.title).font(.headline).lineLimit(1).privacySensitive()
                        TimerControls(snapshot: context.state, complete: context.isStale)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.phase == "paused" ? "pause.fill" : "book.closed")
            } compactTrailing: {
                TimerClock(snapshot: context.state).monospacedDigit().frame(maxWidth: 72)
            } minimal: {
                Image(systemName: context.state.phase == "paused" ? "pause.fill" : "timer")
            }
            .widgetURL(URL(string: "papyrus:///library/timer"))
        }
    }

    private func status(_ context: ActivityViewContext<ReadingTimerAttributes>) -> String {
        if context.isStale { return "Reading goal reached" }
        if context.state.phase == "finished" {
            return context.state.targetMs == context.state.recordedMs ? "Reading goal reached" : "Finished"
        }
        return context.state.phase == "paused" ? "Paused" : "Reading"
    }
}

private struct TimerClock: View {
    let snapshot: TimerSnapshot

    var body: some View {
        if let start = snapshot.runningSinceMs {
            if let deadline = snapshot.deadline {
                Text(timerInterval: Date(timeIntervalSince1970: 0)...deadline, countsDown: true)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(Date(timeIntervalSince1970: Double(start - snapshot.recordedMs) / 1000), style: .timer)
                    .multilineTextAlignment(.trailing)
            }
        } else {
            let seconds = max(0, (snapshot.targetMs.map { $0 - snapshot.recordedMs } ?? snapshot.recordedMs) / 1000)
            Text(seconds >= 3600 ? String(format: "%lld:%02lld:%02lld", seconds / 3600, seconds / 60 % 60, seconds % 60)
                 : String(format: "%02lld:%02lld", seconds / 60, seconds % 60))
        }
    }
}

private struct TimerControls: View {
    let snapshot: TimerSnapshot
    let complete: Bool

    var body: some View {
        if #available(iOS 17.0, *) {
            HStack {
                if !complete && snapshot.phase != "finished" {
                    let running = snapshot.phase == "running"
                    Button(intent: ReadingTimerIntent(sessionId: snapshot.id, token: snapshot.controlToken, kind: running ? "pause" : "resume")) {
                        Label(running ? "Pause" : "Resume", systemImage: running ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                Button(intent: ReadingTimerIntent(sessionId: snapshot.id, token: snapshot.controlToken, kind: "finish")) {
                    Label(complete || snapshot.phase == "finished" ? "Save" : "Finish", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
        } else {
            Link("Open timer", destination: URL(string: "papyrus:///library/timer")!)
        }
    }
}
