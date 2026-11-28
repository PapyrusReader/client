<div align="center">
  <img width="300" src="/public/img/logo-dark.svg#gh-dark-mode-only" alt="Papyrus">
  <img width="300" src="/public/img/logo-light.svg#gh-light-mode-only" alt="Papyrus">

  <p><strong>A cross-platform book management application</strong></p>

  <p>
    <a href="https://join.slack.com/t/papyrus-crew/shared_invite/zt-4btcyuevl-RVRivB9rreOiri4SQhVxdQ"><img src="https://img.shields.io/badge/Slack-Join%20the%20community-4A154B?logo=slack&logoColor=white" alt="Join the Papyrus community on Slack"/></a>
    <a href="https://github.com/orgs/PapyrusReader/projects/1"><img src="https://img.shields.io/badge/GitHub-Project-blue?logo=github&logoColor=white" alt="GitHub Project"/></a>
    <a href="https://docs.papyrus-reader.com/"><img src="https://img.shields.io/badge/Documentation-darkslateblue?logo=gitbook&logoColor=white" alt="Documentation"/></a>
    <a href="https://app.codecov.io/gh/PapyrusReader/client/branch/development"><img src="https://codecov.io/gh/PapyrusReader/client/branch/development/graph/badge.svg" alt="Coverage"/></a>
    <a href="https://github.com/PapyrusReader/client/tree/master?tab=AGPL-3.0-1-ov-file"><img src="https://img.shields.io/badge/License-AGPL--3.0-blue" alt="License"/></a>
  </p>
</div>

---

## Overview

Papyrus is an open-source, cross-platform application for managing and reading books. It supports both physical and digital book collections across Android, iOS, Web, Windows and Linux. The application features an integrated book reader, flexible organization tools, reading statistics, progress tracking, and cross-device synchronization.

<div align="center">
  <img src="/public/img/library.png" alt="Papyrus library view" />
</div>

### Why Papyrus?

Many reading applications offer partial solutions but fall short on essential features, platform availability or user experience. Papyrus aims to deliver a comprehensive, well-rounded, and privacy oriented solution that:

- Works offline-first with optional cloud synchronization
- Supports self-hosting for complete data ownership
- Provides a unified experience across all popular platforms
- Offers extensive customization for different reading preferences

## Features

| Category | Features |
|----------|----------|
| **Reading** | EPUB, PDF, MOBI, AZW3, TXT, CBZ and CBR reader |
| **Organization** | Shelves, tags/topics and library filters |
| **Annotations** | Book-level bookmarks, notes and annotations |
| **Progress** | Saved progress, reading sessions and statistics |
| **Goals** | Reading goals and progress views |
| **Sync** | Offline-first local library and optional synchronization across devices |
| **Storage** | Papyrus-managed uploads by default with ability to connect your own storage solutions  |
| **Catalogs** | OPDS 1.2/2.0 browsing, search and imports |
| **Accessibility** | E-ink, light/dark/high-contrast themes and typography controls |

The built-in reader and native/web file pickers accept EPUB, PDF, MOBI, AZW3,
TXT, CBR and CBZ, but DRM protected files are currently not supported.

## Supported platforms

- Android
- iOS
- macOS
- Linux
- Windows
- Web

## Getting started

### Prerequisites

- Flutter 3.47.9, matching the CI SDK: [installation guide](https://docs.flutter.dev/get-started/install)

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

When the user signs in, the Flutter client communicates with the Papyrus server for authentication and asks the server for PowerSync credentials.

Run the server and PowerSync locally, then start Flutter with:

```bash
cd ../server
./scripts/bootstrap_local.sh
cd ../client/app
flutter run -d chrome --web-hostname papyrus.localhost --web-port 3000 --dart-define-from-file=.dart_defines
```

For local web authentication links, add these entries to `/etc/hosts`:

```text
127.0.0.1 papyrus.localhost
::1 papyrus.localhost
```

## Documentation

See [PapyrusReader/docs](https://github.com/PapyrusReader/docs) for the user manual
and specification.

## Technology stack

| Layer          | Technology                    |
|----------------|-------------------------------|
| Frontend       | Flutter, Dart                 |
| Backend        | FastAPI, Python               |
| Database       | PostgreSQL                    |
| Local database | SQLite, PowerSync             |
| File storage   | OPFS (Web) or Papyrus server  |

## Contributing

Join the [Papyrus Slack community](https://join.slack.com/t/papyrus-crew/shared_invite/zt-4btcyuevl-RVRivB9rreOiri4SQhVxdQ) to meet contributors, ask questions, and discuss development across the PapyrusReader repositories. Start in `#announcements`, introduce yourself in `#introductions`, and collaborate in `#development`. Please follow our [Code of Conduct](CODE_OF_CONDUCT.md).

Keep actionable bug reports and technical decisions in GitHub issues and pull requests so they remain easy to find.

### Setup

1. Fork and clone the repository
2. Install dependencies from `app/` using the Flutter version in CI (currently 3.47.9):

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
   ```

3. Commit your changes and push:

   ```bash
   git commit -m "feat: description of your changes"
   git push origin feature/your-feature-name
   ```

4. Open a pull request

## Resources

| Repository | Description |
|---|---|
| [server](https://github.com/PapyrusReader/server) | Back-end for self-hosted sync and file storage |
| [reader](https://github.com/PapyrusReader/reader) | Book file viewer library |
| [website](https://github.com/PapyrusReader/website) | Landing page |
| [docs](https://github.com/PapyrusReader/docs) | Documentation |
| [papyrus](https://github.com/PapyrusReader/papyrus) | Development workspace |
