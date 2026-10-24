import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/providers/sidebar_provider.dart';
import 'package:papyrus/widgets/shell/desktop_sidebar.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('logo stays centered in the collapsed rail without moving', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SidebarProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [DesktopSidebar(items: const [], currentPath: '/', onNavigate: (_) {})],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final logo = find.byType(SvgPicture);
    final expandedBounds = tester.getRect(logo);
    await tester.tap(find.bySemanticsLabel('Collapse sidebar'));
    await tester.pumpAndSettle();
    final collapsedBounds = tester.getRect(logo);
    expect(collapsedBounds, expandedBounds);
    expect(collapsedBounds.center.dx, tester.getRect(find.byType(DesktopSidebar)).center.dx);
    await tester.tap(find.bySemanticsLabel('Expand sidebar'));
    await tester.pumpAndSettle();
    expect(tester.getRect(logo), expandedBounds);
    expect(tester.takeException(), isNull);
  });
}
