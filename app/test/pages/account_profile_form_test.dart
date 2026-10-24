import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as image;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/widgets/profile/account_settings_section.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider_test.dart' show FakeAuthRepository;
import '../helpers/support_file_picker.dart';

class _Repository extends FakeAuthRepository {
  String? savedName;
  bool fail = false;
  Uint8List? savedPhoto;
  int photoDownloads = 0;

  @override
  Future<PapyrusUser> updateCurrentUser({String? displayName, String? avatarUrl}) async {
    if (fail) {
      throw StateError('Offline');
    }

    savedName = displayName;
    return _user(displayName!);
  }

  @override
  Future<PapyrusUser> uploadProfilePhoto(Uint8List bytes, {required String displayName}) async {
    if (fail) {
      throw StateError('Offline');
    }

    savedName = displayName;
    savedPhoto = bytes;
    return _user(displayName, avatarUrl: '/users/me/avatar/11111111-1111-1111-1111-111111111111');
  }

  @override
  Future<Uint8List> downloadProfilePhoto(String avatarUrl) async {
    photoDownloads++;
    return savedPhoto!;
  }
}

PapyrusUser _user(String name, {String? avatarUrl}) => PapyrusUser(
  userId: 'reader',
  email: 'reader@example.com',
  displayName: name,
  avatarUrl: avatarUrl,
  emailVerified: true,
  createdAt: null,
  lastLoginAt: null,
);

void main() {
  for (final guest in [false, true]) {
    for (final width in [320.0, 390.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('Account settings saves inline at $width, scale $scale, guest $guest', (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({'offline_mode': guest});

          final repository = _Repository()
            ..bootstrapResult = AuthTokens(
              accessToken: 'access',
              refreshToken: 'refresh',
              tokenType: 'Bearer',
              expiresIn: 3600,
              user: _user('Reader'),
            );

          final auth = AuthProvider(
            await SharedPreferences.getInstance(),
            repository: repository,
            bootstrapOnCreate: false,
          );

          await auth.bootstrap();
          addTearDown(auth.dispose);

          final app = ChangeNotifierProvider.value(
            value: auth,
            child: MaterialApp(
              theme: AppTheme.dark.copyWith(visualDensity: VisualDensity.compact),
              home: Scaffold(
                body: SingleChildScrollView(child: AccountSettingsSection(isDesktop: width >= 840)),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
          );
          await tester.pumpWidget(app);

          await tester.pumpAndSettle();
          expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
          expect(find.text('Change photo'), findsNothing);
          expect(find.text('Email'), guest ? findsNothing : findsOneWidget);
          expect(find.text('No email provided'), findsNothing);
          final avatarCrop = find.descendant(of: find.byTooltip('Change photo'), matching: find.byType(ClipOval));
          final cropSize = tester.getSize(avatarCrop);
          expect(cropSize.width, cropSize.height);
          expect(tester.getCenter(avatarCrop), tester.getCenter(find.byTooltip('Change photo')));
          final name = find.widgetWithText(TextFormField, 'Display name');
          await tester.ensureVisible(name);
          await tester.enterText(name, 'Updated Reader');
          await tester.pump();
          await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
          expect(find.widgetWithText(FilledButton, 'Save').hitTestable(), findsOneWidget);
          final picker = SupportFilePicker();
          FilePicker.platform = picker;
          await tester.ensureVisible(find.byTooltip('Change photo'));
          await tester.tap(find.byTooltip('Change photo'));
          await tester.pumpAndSettle();
          expect(repository.savedPhoto, isNull);
          final photo = image.encodePng(image.Image(width: 8, height: 8));
          picker.result = FilePickerResult([PlatformFile(name: 'photo.png', size: photo.length, bytes: photo)]);

          await tester.runAsync(() async {
            await tester.tap(find.byTooltip('Change photo'));
            await tester.pump();
            while (find.byTooltip('Opening photo…').evaluate().isNotEmpty) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              await tester.pump();
            }
          });

          await tester.pumpAndSettle();
          expect(repository.savedPhoto, isNull);
          await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
          if (!guest && width == 390 && scale == 1) {
            repository.fail = true;
            await tester.tap(find.widgetWithText(FilledButton, 'Save'));
            await tester.pumpAndSettle();
            expect(repository.savedName, isNull);
            expect(find.text('Updated Reader'), findsOneWidget);
            expect(find.textContaining('Please try again.'), findsOneWidget);
            repository.fail = false;
          }

          final avatarImage = find.descendant(of: find.byTooltip('Change photo'), matching: find.byType(Image));
          final preview = tester.widget<Image>(avatarImage).image;
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
          await tester.pump();
          expect(tester.widget<Image>(avatarImage).image, preview);
          await tester.pumpAndSettle();
          expect(tester.widget<Image>(avatarImage).image, preview);
          if (guest) {
            expect(repository.savedName, isNull);
            expect(repository.savedPhoto, isNull);
            expect(repository.photoDownloads, 0);
            expect(auth.profileDisplayName, 'Updated Reader');
            expect(image.decodeJpg(auth.profilePhotoBytes!), isNotNull);
            final prefs = await SharedPreferences.getInstance();
            await prefs.reload();
            final restarted = AuthProvider(prefs, repository: _Repository(), bootstrapOnCreate: false);
            addTearDown(restarted.dispose);
            expect(restarted.profileDisplayName, 'Updated Reader');
            expect(restarted.profilePhotoBytes, auth.profilePhotoBytes);
          } else {
            expect(repository.savedName, 'Updated Reader');
            expect(repository.savedPhoto, isNotNull);
            expect(repository.photoDownloads, 0);
            expect(image.decodeJpg(repository.savedPhoto!), isNotNull);
          }
          expect(find.byType(AccountSettingsSection), findsOneWidget);
          expect(find.text('Profile saved.'), findsNothing);
          expect(find.text('Edit profile'), findsNothing);
          expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(app);
          await tester.pumpAndSettle();
          expect(avatarImage, findsOneWidget);
          final renderedAvatar = find.descendant(of: avatarImage, matching: find.byType(RawImage));

          for (var attempt = 0; attempt < 100 && tester.widget<RawImage>(renderedAvatar).image == null; attempt++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
            await tester.pump();
          }

          expect(tester.widget<RawImage>(renderedAvatar).image, isNotNull);
          expect(repository.photoDownloads, guest ? 0 : 1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
