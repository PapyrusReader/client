# Reading statistics

Mode: Operate. Scope: `app/lib/pages/statistics_page.dart`, statistics widgets and
`app/lib/providers/statistics_provider.dart`.

## Confirmed direction

Help readers understand their habits. Build directly in Flutter with existing
Papyrus tokens. The user approved replacing Goals completed with Days read,
scoping genres to books read, and covering the entire selected period in charts
and averages. Current and best streaks remain lifetime context.

## Layout and interaction

Keep period buttons on the left and Custom range at the right edge of the same
row. Below 600 logical px the custom
control is a calendar icon with a tooltip. At large text sizes, period options
scroll horizontally while the calendar remains available. Do not shrink text.
Selected periods use identical typography and geometry to unselected periods,
changing only color. Custom range uses a stable heading, with dates in the activity
header. Captions use complete phrases without dot separators.

Show a borderless summary of reading time, pages, books finished and days read.
Use a dominant activity panel with a narrower session panel on wide screens.
Adjacent panels have equal heights. Phone layouts
stack panels and wrap summary metrics. Appearance > Page alignment defaults to
Left, using the available width and Library/Goals page margins: 24 logical px on
desktop and 16 on mobile. Center retains a 1120 logical px content limit. This
persisted setting currently affects only Statistics.

Time and Pages sit at the top right, vertically centered beside the activity
title and date range. They wrap within the action area only when text scaling
requires it. Native controls preserve keyboard and selected-state semantics.
Empty states use an icon and title without explanatory body copy. Daily average
sits alongside the other rhythm metrics without a divider.

## Data definitions

- Reading time and pages use the corrected reading ledger's existing projection.
  Newly recorded EPUB activity counts rendered pages, one per exposed page after
  ten seconds, including both pages of a spread. Checkpoints and revisits to the
  same page are deduplicated per day. Layout changes can alter EPUB page counts.
  Existing estimates remain labeled as estimated. No past activity is fabricated.
- Genre is editable in Edit book and displayed in book details, using the existing
  custom metadata field without changing unrelated metadata.
- Days read follows the existing five-minute qualification used for streaks and
  reading-day goals. The summary tooltip states this threshold.
- Daily average divides total seconds by elapsed calendar days in the selected
  period, including today and days without reading. Future chart buckets are
  excluded from this denominator. All time begins with the earliest
  effective activity or eligible historical completion, not an arbitrary year.
- Calendar activity axes always cover Monday through Sunday for Week, every date
  for Month, and January through December for Year. Future buckets stay empty.
  All-time/custom activity covers the selected range: daily through 60 days,
  monthly through five years, then yearly. Buckets carry exact seconds, page values and clipped
  boundaries. Short durations use second-based scales, with intermediate grid
  lines including the top boundary and a visible baseline. Time and Pages share
  the same bar renderer. Every bucket has an axis tick. Labels use a fixed integer
  interval based on measured text widths, anchored at the latest bucket. The
  first bucket may have only a tick to avoid an irregular endpoint gap. The header
  always shows the full date range. No smoothing
  invents trends.
- The chart has no expandable totals section. First/last partial calendar buckets
  are bounded by the date range shown in the header.
- Books read and genre shares count distinct books with reading activity or a
  completion in the period. Missing metadata uses Unspecified, including removed
  books whose historical activity remains. Unread inventory does not contribute.
- Books finished by month covers the entire selected year/all-time range and
  scrolls horizontally when needed. It does not discard older months.
- Streaks remain current/lifetime and are labeled separately. Reading pace is
  omitted because independent page-only logs cannot establish a trustworthy rate.
- Empty session averages display an em dash. Existing offline persistence,
  correction handling and profile isolation remain unchanged.

## Verification

Focused tests cover historical/corrected completions, full-range bucket totals,
sub-minute durations, custom boundaries, midnight-crossing sessions, scoped genre
counts, profile replacement, five-minute days, period/date interactions, equal
panel heights, unchanged date-control geometry, readable short
chart scales, separated monthly labels and responsive empty/populated layouts.

Committed synthetic Flutter captures in `.impeccable/review/calendar-axis/` show
the full Statistics page on desktop and phone in both Time and Pages modes.
`.impeccable/review/genre/` covers genre editing and book details. Widget tests also
cover e-ink and large text. These checks do not establish native-device or live
browser acceptance.
