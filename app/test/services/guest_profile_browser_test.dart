@TestOn('browser')
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:papyrus/services/guest_profile_store.dart';
import 'package:papyrus/services/profile_photo.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_web/shared_preferences_web.dart';

void main() {
  test('saved guest photo decodes after real browser storage reload', () async {
    SharedPreferencesPlugin.registerWith(null);
    final prefs = await SharedPreferences.getInstance();
    final store = GuestProfileStore(prefs);
    addTearDown(store.clear);
    final original = prepareProfilePhoto(image.encodePng(image.Image(width: 80, height: 100)));
    await store.save(displayName: 'Browser test', photoBytes: original);
    await _expectDecodable(store);
    await prefs.reload();
    final restored = GuestProfileStore(prefs);
    expect(restored.displayName, 'Browser test');
    expect(restored.photoBytes, original);
    await _expectDecodable(restored);
  });
}

Future<void> _expectDecodable(GuestProfileStore store) async {
  final codec = await ui.instantiateImageCodec(store.photoBytes!);

  try {
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 80);
    expect(frame.image.height, 100);
    frame.image.dispose();
  } finally {
    codec.dispose();
  }
}
