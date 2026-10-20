# Contributing to Papyrus

## Before you start

Find or create an issue in the repository that owns the change. The shared
[Papyrus project](https://github.com/orgs/PapyrusReader/projects/1) tracks work
across the client, server, reader, documentation, website, and workspace.

Product requirements and acceptance criteria live in the
[documentation repository](https://github.com/PapyrusReader/docs). Requirement
tracking issues belong there. Client implementation issues belong here and link
the relevant requirement IDs, such as `FR-1_1`.

Keep one branch and pull request focused on one bounded implementation issue.
Use fully qualified issue links for cross-repository dependencies. Agree on
shared API or data contracts before implementing dependent client behavior.

Locally launched agents take scoped, unassigned Ready tasks from the project.
The [workflow guide](https://github.com/PapyrusReader/docs/blob/development/implementation/github-workflow.rst)
explains specification synchronization, task claims, and dependency checks.

## Branches and commits

`development` is the default integration branch and the target for ordinary
feature and fix pull requests. `master` is the release branch. Keep version
numbers unchanged while accumulating ordinary changes.

Start from the current integration branch in an isolated checkout:

```bash
git fetch origin
git switch -c feature/issue-42-reading-goals origin/development
```

Use descriptive branch names such as `feature/issue-42-reading-goals` or
`fix/issue-42-reading-position`. The local task launcher reserves
`agent/issue-NUMBER` branches as atomic claims. Do not reuse or remove a claim
without checking whether it contains another contributor's work.

Write concise, imperative commit subjects that explain the change. Reference
the owning issue in the commit body when useful:

```text
Preserve reading position across profile switches

Refs #42
```

Keep commits focused and preserve other contributors' changes. Coordinate before
rewriting a shared branch. Follow the repository's active merge and protection
settings.

## Implementation and checks

Read [AGENTS.md](AGENTS.md) for code ownership, style, persistence boundaries,
and platform validation. In the Papyrus workspace, also read
`CODING_STYLE.md` and use the pinned SDK through the workspace tools.

From the workspace root:

```bash
tools/papyrus check client
tools/papyrus test client -- test/path_test.dart
```

For a standalone checkout, follow the equivalent commands in `AGENTS.md`
using the Flutter version pinned by client CI.

Run checks appropriate to the changed behavior. Cover relevant regressions,
profile isolation, asynchronous state changes, and offline persistence.
UI changes need relevant widget tests and visual evidence when a running target
is available. Platform-sensitive changes need checks on the affected platforms.
State clearly which checks passed, failed, or were not run.

Preserve guest, user, and server profile isolation, saved reading positions,
queued writes, and user media. Never clear user data to make a test pass.
Live sync and provider tests need explicit service configuration.

## Pull requests

Use the pull request template and target `development`. Include:

- The owning issue and covered requirement IDs.
- The concrete behavior before and after the change.
- Validation results and relevant screenshots or recordings.
- Compatibility, migration, and remaining acceptance limitations.
- Links to prerequisite or companion PRs in other repositories.

Use `Closes #NUMBER` only when the change completes that issue. Otherwise use
`Refs #NUMBER` and describe the remaining work. Draft PRs are useful for early
review. Move the task to In review when the PR and validation evidence are ready.

Address review findings and required checks before merge. A PR's existence does
not make a requirement implemented or verified. After merge, record acceptance
evidence and close the completed implementation issue. Review the parent
requirement's remaining criteria before updating its specification status.
Create separate issues for deferred follow-up work.

## Releases and hotfixes

Follow the workspace
[release guide](https://github.com/PapyrusReader/papyrus/blob/development/RELEASING.md).
Promote `development` to `master` with a release PR and merge commit, then bring
`master` back into `development`. Use the existing version bump process.
Do not deploy ordinary work from `development`.

An urgent release hotfix may start from `master` when explicitly coordinated.
Bring the fix back into `development` afterwards. Component changes use their
own repository PRs. A separate workspace PR solely to advance a submodule
pointer is not part of the ordinary contribution workflow.
