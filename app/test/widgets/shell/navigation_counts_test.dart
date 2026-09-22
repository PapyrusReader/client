import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/opds/opds_catalog_store.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/providers/sidebar_provider.dart';
import 'package:papyrus/widgets/shell/adaptive_app_shell.dart';
import 'package:papyrus/widgets/shell/nav_item_count.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../opds/catalog_store_test.dart' show MemorySecrets;

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('navigation hides empty counts and tracks saved catalogs at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final catalogs = OpdsCatalogs(OpdsCatalogStore(await SharedPreferences.getInstance(), secrets: MemorySecrets()))
        ..setScope('guest');
      addTearDown(catalogs.dispose);
      final router = GoRouter(
        initialLocation: '/library/catalogs',
        routes: [
          ShellRoute(
            builder: (_, _, child) => AdaptiveAppShell(child: child),
            routes: [GoRoute(path: '/library/catalogs', builder: (_, _) => const Text('Page content'))],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => DataStore()),
            ChangeNotifierProvider(create: (_) => SidebarProvider()),
            ChangeNotifierProvider.value(value: catalogs),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      if (width < 840) {
        tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
        await tester.pumpAndSettle();
      }
      expect(find.text('Catalogs'), findsOneWidget);
      expect(find.byType(NavItemCount), findsNothing);
      expect(find.text('0'), findsNothing);

      await catalogs.save(OpdsCatalog(id: 'one', name: 'One', uri: Uri.parse('https://one.test/feed')));
      await tester.pumpAndSettle();
      expect(tester.widget<NavItemCount>(find.byType(NavItemCount)).count, 1);
      expect(tester.widget<NavItemCount>(find.byType(NavItemCount)).selected, isTrue);

      await catalogs.save(OpdsCatalog(id: 'two', name: 'Two', uri: Uri.parse('https://two.test/feed')));
      await tester.pumpAndSettle();
      expect(tester.widget<NavItemCount>(find.byType(NavItemCount)).count, 2);

      await catalogs.remove('one');
      await tester.pumpAndSettle();
      expect(tester.widget<NavItemCount>(find.byType(NavItemCount)).count, 1);

      catalogs.setScope('another-account');
      await tester.pumpAndSettle();
      expect(find.byType(NavItemCount), findsNothing);
      catalogs.setScope('guest');
      await tester.pumpAndSettle();
      expect(tester.widget<NavItemCount>(find.byType(NavItemCount)).count, 1);

      await catalogs.remove('two');
      await tester.pumpAndSettle();
      expect(find.byType(NavItemCount), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
