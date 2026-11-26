import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/shelf.dart';
import 'package:papyrus/pages/shelf_contents_page.dart';
import 'package:papyrus/pages/shelves_page.dart';
import 'package:papyrus/widgets/library/book_card.dart';
import 'package:patrol/patrol.dart';

import 'journey_support.dart';

void main() {
  patrolTest('Back preserves the shelf, the active book tab and an unsaved edit', ($) async {
    await $.startGuest();
    final router = $.router;
    final book = await $.seedBook('Field guide');
    final now = DateTime.now();
    final shelf = Shelf(id: 'fieldwork', name: 'Fieldwork', createdAt: now, updatedAt: now);
    await $.store.addShelf(shelf);
    await $.store.addBookToShelf(book.id, shelf.id);
    await $.visit('/library/shelves');
    await $(shelf.name).tap();
    await $(book.title).tap();

    Future<void> systemBack() async {
      if (Platform.isAndroid) {
        await $.platform.android.pressBack();
        expect($.tester.binding.lifecycleState, AppLifecycleState.resumed, reason: 'Back must stay inside Papyrus.');
      } else {
        expect(await router.backButtonDispatcher.invokeCallback(Future.value(false)), isTrue);
      }

      await $.tester.pumpAndSettle();
    }

    if (Platform.isIOS) {
      await $.platform.ios.swipeBack();
      await $(find.byType(ShelfContentsPage)).waitUntilVisible();
      expect(router.routeInformationProvider.value.uri.path, '/library/shelves/${shelf.id}');
      await $(book.title).tap();
    }

    final notesTab = find.text('Notes (0)');
    await $.tester.ensureVisible(notesTab);
    await $(notesTab).tap();
    await $('No notes yet').waitUntilVisible();
    await $.tester.drag(find.byType(NestedScrollView), const Offset(0, 450));
    await $.tester.pumpAndSettle();
    final edit = find.widgetWithIcon(OutlinedButton, Icons.edit_outlined);
    await $(edit).tap();
    // Keep native Back scoped to navigation while the editor has unsaved changes.
    final rating = find.byTooltip('Rate 4 out of 5 stars');
    final selectedRating = find.byTooltip('Clear 4 star rating');
    await $(rating).waitUntilExists();
    await $.tester.ensureVisible(rating);
    await $(rating).tap();
    await $(selectedRating).waitUntilVisible();

    if (Platform.isIOS) {
      final navigator = Navigator.of($.tester.element(find.byTooltip('Back')));
      final gesture = navigator.userGestureInProgressNotifier;
      var started = false;
      void observeSwipe() => started |= gesture.value;
      gesture.addListener(observeSwipe);

      try {
        await $.platform.ios.swipe(from: const Offset(0, 0.5), to: const Offset(0.18, 0.5));
        await $.tester.pumpAndSettle();
      } finally {
        gesture.removeListener(observeSwipe);
      }

      expect(started, isTrue, reason: 'The short edge swipe must start an interactive Back gesture.');
      expect(router.routeInformationProvider.value.uri.path, '/library/edit/${book.id}');
      await $(selectedRating).waitUntilVisible();
      await $.platform.ios.swipeBack();
    } else {
      await $(find.byTooltip('Back')).tap();
    }

    await $('Keep editing').tap();
    await $(selectedRating).waitUntilVisible();
    await systemBack();
    await $('Discard').tap();
    await $('No notes yet').waitUntilVisible();
    expect($.store.getBook(book.id)!.rating, book.rating);
    await $(find.byTooltip('Back')).tap();
    await $(find.byType(ShelfContentsPage)).waitUntilExists();
    await $(book.title).tap();
    await systemBack();
    await $(shelf.name).waitUntilVisible();

    expect(router.routeInformationProvider.value.uri.path, '/library/shelves/${shelf.id}');
    final card = find
        .descendant(of: find.byType(ShelfContentsPage), matching: find.widgetWithText(BookCard, book.title))
        .hitTestable()
        .first;
    await $(card).waitUntilVisible();
    await $.tester.longPress(card);
    await $('Select').tap();
    await $(find.byTooltip('Exit selection')).waitUntilVisible();
    await systemBack();
    await $(shelf.name).waitUntilVisible();
    expect(find.byTooltip('Exit selection'), findsNothing);
    await systemBack();
    await $(find.byType(ShelvesPage)).waitUntilExists();
    await $(shelf.name).waitUntilVisible();
  });
}
