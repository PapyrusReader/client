import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/powersync/papyrus_schema.dart';
import 'package:papyrus/powersync/library_row_mapper.dart';

void main() {
  test('guest books table is local-only', () {
    expect(papyrusGuestSchema.tables.map((table) => table.name), containsAll(libraryTableNames));
    expect(papyrusGuestSchema.tables.every((table) => table.localOnly), isTrue);
  });

  test('authenticated books table participates in synchronization', () {
    final tables = papyrusAccountSchema.tables.where(
      (table) => libraryTableNames.contains(table.name) && table.name != 'tracking_staging',
    );

    expect(tables.length, libraryTableNames.length - 1);
    expect(papyrusAccountSchema.tables.singleWhere((table) => table.name == 'tracking_staging').localOnly, isTrue);
    expect(tables.every((table) => !table.localOnly), isTrue);
  });
}
