<div align="center">
  <img width="300" src="/public/img/logo-dark.svg#gh-dark-mode-only" alt="Papyrus">
  <img width="300" src="/public/img/logo-light.svg#gh-light-mode-only" alt="Papyrus">

  <p><strong>A cross-platform book management application</strong></p>

  <p>
    <a href="https://join.slack.com/t/papyrus-crew/shared_invite/zt-4btcyuevl-RVRivB9rreOiri4SQhVxdQ"><img src="https://img.shields.io/badge/Slack-Join%20the%20community-4A154B?logo=slack&logoColor=white" alt="Join the Papyrus community on Slack"/></a>
    <a href="https://trello.com/invite/b/681367b2ba91db4e40b0cfea/ATTI5156837607437467bd3d646f933528054D126F02/papyrus"><img src="https://img.shields.io/badge/Trello-blue?logo=trello&logoColor=white" alt="Trello"/></a>
    <a href="https://papyrusreader.github.io/docs/"><img src="https://img.shields.io/badge/Documentation-darkslateblue?logo=gitbook&logoColor=white" alt="Documentation"/></a>
    <a href="https://app.codecov.io/gh/PapyrusReader/client/branch/development"><img src="https://codecov.io/gh/PapyrusReader/client/branch/development/graph/badge.svg" alt="Coverage"/></a>
    <a href="https://github.com/PapyrusReader/client/tree/master?tab=AGPL-3.0-1-ov-file"><img src="https://img.shields.io/badge/License-AGPL--3.0-blue" alt="License"/></a>
  </p>
</div>

---

## Overview

Papyrus is an open-source, cross-platform application for managing and reading books. It supports both physical and digital book collections across Android, iOS, Web, Windows and Linux. The application features an integrated book reader, flexible organization tools, reading statistics, progress tracking, uses local media caches and optional Papyrus server storage and cross-device synchronization via a self-hostable server.

<div align="center">
  <img src="/public/img/library.png" alt="Papyrus library view" />
</div>

### Why Papyrus?

Many reading applications offer partial solutions but fall short on essential features, platform availability or user experience. Papyrus aims to deliver a comprehensive, privacy oriented solution that:

- Works offline-first with optional cloud synchronization
- Supports self-hosting for complete data ownership
- Provides a unified experience across all popular platforms
- Offers extensive customization for different reading preferences

## Features

| Category | Features |
|----------|----------|
| **Reading** | EPUB/PDF reader with pagination/scrolling, appearance settings and saved positions |
| **Organization** | Shelves, tags/topics and library filters |
| **Annotations** | Book-level bookmarks, notes and annotations; reader text selection/export is future work |
| **Progress** | Saved progress, reading sessions and statistics |
| **Goals** | Reading goals and progress views |
| **Sync** | Offline-first local library and optional self-hosted PowerSync synchronization |
| **Storage** | Local media caches and Papyrus-managed server uploads |
| **Catalogs** | OPDS 1.2/2.0 browsing, search and imports through the backend relay |
| **Accessibility** | E-ink, light/dark themes and reader typography controls |

The built-in reader opens EPUB and PDF. Native metadata import also accepts MOBI,
AZW3, TXT, CBR and CBZ; these formats do not have reading engines yet. The web
file picker currently accepts EPUB. Additional cloud storage providers and
selection-based reader annotations remain future work.

## Supported platforms

- Android
- iOS
- macOS
- Linux
- Windows
- Web

## Getting started

### Prerequisites

- Flutter 3.41.2, matching the CI SDK: [installation guide](https://docs.flutter.dev/get-started/install)

### Installation

> [!IMPORTANT]
> For instructions on setting up the full development environment on your platform, see [PapyrusReader/papyrus](https://github.com/PapyrusReader/papyrus).

1. **Clone the repository**

   ```bash
   git clone git@github.com:PapyrusReader/client.git
   cd client
   ```

2. **Install dependencies**

   ```bash
   cd app
   flutter pub get --enforce-lockfile
   ```

3. **Run the application**

   ```bash
   # Android/iOS (with connected device or emulator)
   flutter run

   # Web
   flutter run -d chrome

   # Desktop
   flutter run -d windows  # or: macos, linux
   ```

### Running with the back-end

When the user signs in, the Flutter client communicates with the Papyrus server for auth and asks the server for PowerSync credentials.

Run the server and PowerSync locally, then start Flutter with:

```bash
cd ../server
./scripts/bootstrap_local.sh
cd ../client/app
flutter run -d chrome --web-hostname papyrus.localhost --web-port 3000 --dart-define-from-file=.dart_defines
```

For local web auth links, add these entries to `/etc/hosts`:

```text
127.0.0.1 papyrus.localhost
::1 papyrus.localhost
```

## Documentation

See [PapyrusReader/docs](https://github.com/PapyrusReader/docs).

## Technology stack

| Layer        | Technology         |
|--------------|--------------------|
| Frontend     | Flutter / Dart     |
| Backend      | FastAPI / Python   |
| Database     | PostgreSQL         |
| Local database | SQLite / PowerSync |
| File storage | Device cache (OPFS on web) and Papyrus server |

## Contributing

Join the [Papyrus Slack community](https://join.slack.com/t/papyrus-crew/shared_invite/zt-4btcyuevl-RVRivB9rreOiri4SQhVxdQ) to meet contributors, ask questions, and discuss development across the PapyrusReader repositories. Start in `#announcements`, introduce yourself in `#introductions`, and collaborate in `#development`. Please follow our [Code of Conduct](CODE_OF_CONDUCT.md).

Keep actionable bug reports and technical decisions in GitHub issues and pull requests so they remain easy to find.

### Setup

1. Fork and clone the repository
2. Install dependencies from `app/` using the Flutter version in CI (currently 3.41.2):

   ```bash
   cd app
   flutter pub get --enforce-lockfile
   ```

   When using the full Papyrus workspace, run `tools/papyrus sdk` and
   `tools/papyrus deps client` from its root. The workspace includes pinned SDK
   wrappers, VS Code check/test tasks, project skills, and Dart MCP integration.
   See its [development tooling guide](https://github.com/PapyrusReader/papyrus/blob/master/DEVELOPMENT.md).

### Development workflow

1. Create a feature branch:

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes and ensure quality checks pass:

   ```bash
   dart format --output=none --set-exit-if-changed .
   flutter analyze --no-fatal-warnings --no-fatal-infos
   flutter test
   node --test test/web/flutter_bootstrap_test.cjs
   ```

3. Commit your changes and push:

   ```bash
   git commit -m "feat: description of your changes"
   git push origin feature/your-feature-name
   ```

4. Open a pull request

### Coverage

CI runs `flutter test --coverage --file-reporter json:build/test-results/tests.json`
from `app/`. The normal test log remains visible in Actions. A pinned JUnit
converter turns the JSON results into XML for Codecov Test Analytics, which
reports test duration and failures.
Before conversion, runtime skips are normalized from the test runner's final
result so they remain skipped in JUnit. The original JSON report is preserved.

Coverage and test results are uploaded even when tests fail. The failing test
step still fails the job; report generation and uploads cannot mask that failure.
Missing or empty reports and failed uploads also fail the quality job. Both
`client-coverage-<attempt>` and `client-test-results-<attempt>` artifacts are
retained for 14 days, including the raw JSON results for troubleshooting.

[`codecov.yml`](codecov.yml) uses `development` as the default branch. The
project status compares coverage against the PR base or parent commit and allows
a one percentage point drop. The patch status targets 80% of changed lines and
is informational initially; it reports coverage without failing on the target.

Four components show coverage for UI, state/models, auth/storage/sync, and
reading/goals in Codecov and PR comments, using paths from the single client
coverage upload. Reading/goals intentionally overlaps UI and state because it
crosses those layers. Component checks are informational during rollout.

Codecov's repository default branch must also be `development` under
**Configuration → General**. Verify that **Configuration → Yaml** reflects the
committed configuration and that `codecov/project` appears on GitHub before
making that check required in branch protection. A successful upload alone does
not prove that Codecov has applied the status-check configuration.

## Resources

| Repository | Description |
|---|---|
| [server](https://github.com/PapyrusReader/server) | Back-end for self-hosted sync and file storage |
| [reader](https://github.com/PapyrusReader/reader) | Book file viewer library |
| [website](https://github.com/PapyrusReader/website) | Landing page |
| [docs](https://github.com/PapyrusReader/docs) | Documentation |
| [papyrus](https://github.com/PapyrusReader/papyrus) | Development workspace |

## Google Play testing builds

See [the release guide](docs/RELEASING.md) for signed Android App Bundles,
version-triggered GitHub builds, required endpoint/signing settings and the first
internal testing upload.
