import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/book_details/note_card.dart';
import 'package:papyrus/widgets/goals/log_reading_sheet.dart';
import 'package:papyrus/widgets/shared/searchable_book_field.dart';
import 'package:patrol/patrol.dart';

import 'journey_support.dart';

void main() {
  patrolTest('a corrected reading entry updates Goals and Statistics after reopening', ($) async {
    await $.startGuest();
    final book = await $.seedBook('Reading ledger');
    await $.visit('/goals');
    await $(find.byTooltip('New goal')).tap();
    await $('Pages read').tap();
    await $.fill('Target', '10');
    await $('Create goal').tap();
    await $('0 of 10 pages').waitUntilExists();
    await $(find.byTooltip('Log reading')).tap();
    await $(find.byType(SearchableBookField)).tap();
    await $(book.title).tap();
    await $.fill('Pages read', '12');
    await $('Save reading').tap();

    Future<void> checkTotals(int goal, int pages) async {
      await $.visit('/goals');
      await $('$goal of 10 pages').waitUntilExists();
      expect(find.text('Target reached'), goal == 10 ? findsWidgets : findsNothing);
      await $.visit('/statistics');
      final metric = find.ancestor(of: find.text('Pages read'), matching: find.byType(Column)).first;
      await $(find.descendant(of: metric, matching: find.text('$pages'))).waitUntilExists();
    }

    await checkTotals(10, 12);
    await $('Activity').tap();
    await $(book.title).tap();
    final entry = find.byType(ReadingActivityTile);
    await $(entry).waitUntilExists();
    await $.tester.ensureVisible(entry);
    await $(entry).tap();
    await $('Correct entry').tap();
    await $.fill('Pages read', '7');
    await $('Save reading').tap();
    await checkTotals(7, 7);
    await $.reopenGuest();
    await checkTotals(7, 7);
  });

  patrolTest('editing and deleting a book note keeps its sibling on the other book', ($) async {
    await $.startGuest();
    final first = await $.seedBook('First notebook');
    final second = await $.seedBook('Second notebook');

    Future<void> openNotes(String id) async {
      await $.visit('/library/details/$id');
      final tab = find.textContaining(RegExp(r'^Notes \(\d+\)$'));
      await $(tab).waitUntilExists();
      await $.tester.ensureVisible(tab);
      await $(tab).tap();
    }

    Future<void> createNote(String id, String body) async {
      await openNotes(id);
      await $(find.byType(FloatingActionButton).hitTestable()).tap();
      await $.fill('Title', 'Field notes');
      await $.fill('Content', body);
      await $('Save').tap();
      await $(body).waitUntilExists();
    }

    await createNote(first.id, 'Northern trail');
    await createNote(second.id, 'Southern trail');
    await $.visit('/library/notes');
    await $('Northern trail').tap();
    await $.fill('Content', 'Revised northern trail');
    await $('Save').tap();
    await openNotes(first.id);
    await $('Revised northern trail').waitUntilExists();
    expect(find.text('Southern trail'), findsNothing);
    await openNotes(second.id);
    await $('Southern trail').waitUntilExists();
    expect(find.text('Revised northern trail'), findsNothing);
    await $.visit('/library/notes');
    await $.tester.longPress(find.widgetWithText(NoteCard, 'Revised northern trail'));
    await $('Delete note').tap();
    await $('Delete').tap();
    await $.reopenGuest();
    await $.visit('/library/notes');
    await $('Southern trail').waitUntilExists();
    expect(find.byType(NoteCard), findsOneWidget);
    await $.tester.enterText(find.byType(TextField).first, 'Southern');
    await $.tester.pumpAndSettle();
    expect(find.text('Southern trail'), findsOneWidget);
  });
}
