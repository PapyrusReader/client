# Reading timer notifications

The native surfaces mirror the existing reading timer. They do not own a second
PowerSync database or create their own reading sessions.

- Android shows a silent notification with the book, a native chronometer,
  pause/resume and finish. Running timers use a `specialUse` foreground service.
  Pausing stops the service but retains the ongoing notification and its controls.
  Android 13+ asks for notification permission when an active timer is first shown.
- iOS 16.2+ shows a Live Activity on the Lock Screen and Dynamic Island. iOS 17+
  provides pause/resume and finish through `LiveActivityIntent`, without opening
  the app. Earlier supported versions link back to the timer. ActivityKit and the
  user's system settings control visibility and lifetime.
- Finish saves time without page input. Subsecond sessions are discarded quietly.
  Countdown time is capped at the goal. A completed countdown offers Save.
- Other platforms retain the in-app timer and do not request notification access.

## Background actions and synchronization

Native controls first write a private, durable action journal containing the
session ID, base version, command IDs and tap timestamps. They update the native
surface immediately. Dart replays those actions through `ReadingTimerProvider`
and the current profile's repository when it is available. On a suspended or
terminated iPhone app, replay may wait until the app next runs. PowerSync receives
the normal timer and reading-activity writes at that point.

Command IDs become timer versions, making replay recoverable if the process stops
between persisting an action and acknowledging it. A remote version change or a
different active session rejects stale controls. Switching library profiles clears
the old native surface and journal. Native acknowledgements preserve newer actions
that arrived while Dart was writing.

The clock renders from timestamps rather than per-second native channel calls.
iOS does not keep a Dart engine or network connection running indefinitely. Remote
PowerSync changes update the Live Activity when the app is running again. There is
no APNs push-to-update integration. Android does not acquire a wake lock. On screen
wake, its service refreshes countdown completion.

## Validation

Dart tests cover delayed timestamps, save-once replay, interrupted finish recovery,
stale remote versions, subsecond finish, countdown limits, persistence failures and
profile isolation. Native XCTest covers the durable journal, concurrent
acknowledgement, countdown clamping and real Live Activity intent execution.

The native smoke-test host at
`app/integration_test/support/timer_notification_app.dart` uses synthetic data and
no user library. Build it only for isolated test simulators/emulators. The normal
application entry point remains `app/lib/main.dart`. Use the fixture for native
XCTest so the production provider does not clear synthetic sessions during a test.
From `app/ios`, with an isolated iOS simulator booted:

```sh
xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=YOUR_TEST_SIMULATOR' \
  -only-testing:RunnerTests -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  FLUTTER_TARGET=integration_test/support/timer_notification_app.dart
```

Use `flutter run -t integration_test/support/timer_notification_app.dart` on an
isolated Android emulator to check notification actions after backgrounding or
killing the app. The fixture is never the release entry point.

Android special-use foreground service declarations must be included in the Play
Console declaration when this feature is distributed. The widget extension is
embedded in the iOS Runner target and uses the app's build version and signing team.
