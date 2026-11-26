# Reader journeys and recovery tests

The **Reader journeys and recovery** workflow selects pull-request jobs using the changed paths. Router, shared toolbar, or navigation-shell changes run the Android Back journey and Chrome history check. Changes to the upload connector run the disposable sync tests. Shared data models, persistence, or package dependencies run Chrome, sync, and the Android PR suite. That suite covers import/resume, EPUB bookmark reflow, goal correction, book notes, and Back navigation. Changes to the gesture test itself run the full Android journey suite. A new push cancels the previous journey run for that PR.

Nightly and manual runs exercise all jobs, including iPhone edge swipes, Android and iOS highlight selection and PDF zoom/pan, native Live Activity tests, Android process recovery, and 1,000 Android Monkey events. GitHub runs the schedule from the default branch. The optional workflow seed repeats a sequence on the same OS image, app revision, and starting library.

## Chrome history

From the workspace root with Chrome and uv installed:

```sh
(cd client/app && ../../tools/flutter build web --profile)
uv run --script client/tools/test_browser_history.py client/app/build/web
```

The journey starts a local web server and a fresh browser profile, creates a physical book, and edits its title. It verifies the URL and the displayed title after browser Back with **Keep editing**, toolbar Back with **Discard**, and browser Forward. It also opens the editor URL directly, saves or discards an edit, and checks that browser Back returns to the preceding document.

## Patrol on Android and iOS

Use a fresh English-language Android emulator or iPhone simulator. Patrol installs and uninstalls its test build. The runner copies the bundled Frankenstein EPUB into Downloads or On My iPhone. The test enters the guest library, imports the book with the native file picker, turns pages, and reopens the book at the saved location. The seed controls page turns and background/foreground transitions in the import journey. The other cases use small local fixtures. The EPUB has numbered passages so a bookmark or highlight can be checked against the visible words after a reflow. The PDF has three labeled pages so a pan can be distinguished from a page turn.

From the Papyrus workspace, with the pinned SDK and Android platform tools on PATH:

```sh
export PATH="$PWD/.fvm/flutter_sdk/bin:$HOME/.pub-cache/bin:$PATH"
tools/dart pub global activate patrol_cli 4.10.0
JOURNEY_SEED=42 client/tools/mobile_journey.sh emulator-5554
JOURNEY_SEED=42 client/tools/mobile_journey.sh YOUR_IPHONE_SIMULATOR_UDID
client/tools/mobile_journey.sh emulator-5554 patrol_test/library_journeys_test.dart
client/tools/mobile_journey.sh emulator-5554 patrol_test/back_navigation_test.dart
```

The iPhone Back journey swipes from book details to the originating shelf, cancels a short edge swipe in the editor, and completes a swipe with unsaved changes.

## Android cold restart and Monkey

Use a fresh Android API 36 emulator with an empty Papyrus library. This check drives the normal debug APK from the host so the assertions survive process termination. It turns off Wi-Fi and mobile data during recovery, exercises the timer's notification action and starts Monkey in the populated reader. Run from the workspace:

```sh
(cd client/app && ../../tools/flutter build apk --debug --flavor direct)
adb -s emulator-5554 install client/app/build/app/outputs/flutter-apk/app-direct-debug.apk
uv run --script client/tools/android_resilience.py --device emulator-5554 \
  --seed 42 --events 1000 --output client/app/build/resilience
```

The output directory holds the seed, fingerprint, fixture name, Git revision, logcat, and a screenshot. At the start of Monkey it captures the reader screenshot and accessibility tree, then records the event stream. Replay with the same seed and event count on a fresh emulator.

## Lost upload acknowledgement

Install Docker Compose, uv, and Toxiproxy Server 2.13.0. Put `toxiproxy-server` on PATH. From the workspace:

```sh
FLUTTER_BIN="$PWD/tools/flutter" client/tools/run_sync_fault.sh server
```

The runner starts temporary PostgreSQL and PowerSync containers, a local API, and Toxiproxy using the server checkout's committed revision. It needs host ports 25432, 28080, 28081, and 28474 available. Only the writer's API connection goes through the proxy. A second client confirms the annotation arrived while the response is withheld. The test resets the connection, observes a second upload attempt, and checks both clients have one copy with the original ID and text. The same run disconnects the writer, edits one note and deletes another. It withholds the reconnect upload response, verifies a retry, then reopens both databases to check the surviving note. The runner removes its containers, volumes, credentials, and temporary checkout on exit.

The same stack also runs the Notes page with two authenticated profiles and a book of the same title in each library. It edits one note offline, switches profiles, reconnects, and checks the rendered notes. Fresh client databases verify the replicated note for each account.
