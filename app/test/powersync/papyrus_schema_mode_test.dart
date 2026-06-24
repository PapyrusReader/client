import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/powersync/papyrus_schema.dart';

void main() {
  test('guest books table is local-only', () {
    final table = papyrusGuestSchema.tables.single;

    expect(table.name, 'books');
    expect(table.localOnly, isTrue);
  });

  test('authenticated books table participates in synchronization', () {
    final table = papyrusAccountSchema.tables.single;

    expect(table.name, 'books');
    expect(table.localOnly, isFalse);
  });
}
