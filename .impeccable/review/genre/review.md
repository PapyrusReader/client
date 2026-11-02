# Pages and genre follow-up

Genre now uses the existing custom metadata key through a Book getter, Edit book
field and book-details row. Clearing the field removes only the genre key. Tests
verify database persistence across profile reopening, preservation of other
metadata, mobile/desktop editing and immediate statistics refresh.

The reader now emits one coverage range per rendered EPUB page, including each
column of a spread. Stable page keys use content boundaries. Scrolling clips the
visible range without changing page identity. The host credits one page after
ten seconds of exposure, independent of publisher page counts. Per-page exposure
timers survive scrolling within a page. Existing daily coverage unions deduplicate
checkpoints and revisits. Font/window changes may produce different pages. Old
activity is preserved without inventing missing history or recalculating estimates.

Checked synthetic Flutter renders of Genre in Edit book and book details on
390/1200 logical px viewports. These are scrolled to the relevant field/row. The
temporary capture harness is outside the repository in /tmp/book_genre_capture.local_test.dart.

Validation: full client suite 2078 passed, 19 skipped; full reader suite 235 passed.
Client and reader checks passed, including analysis, formatting, reader example
analysis, generated worker drift validation and 17 client JavaScript tests.
SQLite/queued-upload round-trip tests cover rendered-page coverage. The existing
server Pydantic schema accepted and round-tripped the same coverage structure.
No schema migration or server changes were needed. Live server replication and
native-device acceptance were not run. The existing local reader path override
was preserved for client integration tests, without changing release pins.
