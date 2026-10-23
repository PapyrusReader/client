import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/shared/app_motion_control.dart';

class LicensesPage extends StatefulWidget {
  const LicensesPage({super.key});

  @override
  State<LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends State<LicensesPage> {
  late Future<Map<String, List<LicenseEntry>>> _licenses = _loadLicenses();
  String? _selectedPackage;

  Future<Map<String, List<LicenseEntry>>> _loadLicenses() async {
    final packages = <String, List<LicenseEntry>>{};

    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        (packages[package] ??= []).add(entry);
      }
    }

    return packages;
  }

  @override
  Widget build(BuildContext context) {
    return _LicenseMotionScope(
      child: _LicenseScaffold(
        title: 'Licenses',
        child: FutureBuilder<Map<String, List<LicenseEntry>>>(
          future: _licenses,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () => setState(() => _licenses = _loadLicenses()),
                  child: const Text('Could not load licenses. Retry'),
                ),
              );
            }

            final packages = snapshot.data;

            if (packages == null) {
              return const Center(child: Text('Loading licenses…'));
            }

            if (packages.isEmpty) {
              return const Center(child: Text('No licenses registered.'));
            }

            final names = packages.keys.toList()
              ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
            final selected = _selectedPackage ?? names.first;

            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= Breakpoints.tablet;

                final list = ListView.builder(
                  key: const PageStorageKey('license-packages'),
                  padding: const EdgeInsets.all(Spacing.md),
                  itemCount: names.length,
                  itemBuilder: (context, index) {
                    final name = names[index];
                    final entries = packages[name]!;

                    return AppMotionControl(
                      value: wide && name == selected,
                      builder: (focusNode) => ListTile(
                        focusNode: focusNode,
                        title: Text(name),
                        subtitle: Text('${entries.length} ${entries.length == 1 ? 'license' : 'licenses'}'),
                        selected: wide && name == selected,
                        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
                        selectedColor: Theme.of(context).colorScheme.onSecondaryContainer,
                        onTap: () {
                          setState(() => _selectedPackage = name);

                          if (!wide) {
                            Navigator.of(context).push(
                              PageRouteBuilder<void>(
                                transitionDuration: Duration.zero,
                                reverseTransitionDuration: Duration.zero,
                                pageBuilder: (context, animation, secondaryAnimation) => _LicenseMotionScope(
                                  child: _LicenseScaffold(
                                    title: name,
                                    child: _LicenseDetails(package: name, entries: entries),
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                );

                if (!wide) {
                  return list;
                }

                return Row(
                  children: [
                    SizedBox(width: 280, child: list),
                    VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outline),
                    Expanded(
                      child: _LicenseDetails(package: selected, entries: packages[selected]!),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _LicenseScaffold extends StatelessWidget {
  const _LicenseScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LibraryPageHeader(title: title, leading: const BackButton(), compact: compact),
            if (compact) const Divider(height: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _LicenseMotionScope extends StatelessWidget {
  const _LicenseMotionScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AppMotionScope(
    reduceAnimations: true,
    child: Theme(
      data: Theme.of(context).copyWith(splashFactory: NoSplash.splashFactory, highlightColor: Colors.transparent),
      child: child,
    ),
  );
}

class _LicenseDetails extends StatelessWidget {
  const _LicenseDetails({required this.package, required this.entries});

  final String package;
  final List<LicenseEntry> entries;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      key: ValueKey(package),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(package, style: textTheme.titleLarge),
                const SizedBox(height: Spacing.lg),
                for (var index = 0; index < entries.length; index++) ...[
                  if (index > 0) Divider(height: Spacing.xl, color: Theme.of(context).colorScheme.outline),
                  for (final paragraph in entries[index].paragraphs)
                    Padding(
                      padding: EdgeInsets.only(
                        left: paragraph.indent > 0 ? paragraph.indent.clamp(0, 4) * Spacing.md : 0,
                        bottom: Spacing.sm,
                      ),
                      child: Text(
                        paragraph.text,
                        textAlign: paragraph.indent == LicenseParagraph.centeredIndent
                            ? TextAlign.center
                            : TextAlign.start,
                        style: textTheme.bodyMedium,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
