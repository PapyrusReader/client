#!/usr/bin/env bash
# Input is git diff --no-renames --name-only -z, including removed paths.
set -euo pipefail
android=none
gestures=false
history=false
sync=false
while IFS= read -r -d '' path; do
  case "$path" in
    app/lib/powersync/papyrus_powersync_connector.dart|tools/run_sync_fault.sh|\
    app/test/powersync/lost_acknowledgement_test.dart|app/test/powersync/profile_note_journey_test.dart)
      sync=true ;;
    .github/workflows/resilience.yml|.github/scripts/select_journeys.sh|app/pubspec.*|app/lib/main.dart|\
    app/lib/data/*|app/lib/models/*|app/lib/powersync/*|app/lib/auth/*|app/lib/providers/auth_provider.dart|\
    app/lib/providers/sync_settings_provider.dart)
      android="pr"; history=true; sync=true ;;
    app/lib/pages/notes_page.dart|app/lib/providers/notes_provider.dart|app/lib/widgets/book_details/note_*.dart)
      android="pr"; sync=true ;;
    app/lib/config/app_router.dart|app/lib/config/page_history.dart|app/lib/widgets/shared/app_page_bar.dart|\
    app/lib/widgets/shell/*|app/patrol_test/back_navigation_test.dart)
      if [[ "$android" == none ]]; then android=navigation; fi
      history=true ;;
    app/lib/pages/book_details_page.dart|app/lib/pages/book_edit_page.dart|app/lib/pages/library_page.dart|\
    app/lib/providers/book_edit_provider.dart|app/lib/widgets/book/*|app/lib/widgets/book_details/*|\
    app/lib/widgets/book_form/*|app/lib/widgets/add_book/*|app/lib/widgets/shared/*|app/lib/widgets/library/*|app/lib/themes/*)
      android="pr"; history=true ;;
    app/patrol_test/reader_gestures_test.dart)
      gestures=true ;;
    app/web/*|tools/test_browser_history.py)
      history=true ;;
    app/lib/*|app/patrol_test/*|app/android/*|app/assets/*|app/test/data/book1.epub|tools/mobile_journey.sh|tools/android_resilience.py)
      android="pr" ;;
  esac
done
if [[ $gestures == true ]]; then android=full; fi
printf 'android=%s\nhistory=%s\nsync=%s\n' "$android" "$history" "$sync"
