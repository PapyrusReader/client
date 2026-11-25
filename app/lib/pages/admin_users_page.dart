import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/admin/user_directory.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_page_bar.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:provider/provider.dart';

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SyncSettingsProvider>();

    if (!auth.canAdminister(settings)) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppPageBar(
        context: context,
        title: const Text('Users'),
        automaticallyImplyLeading: false,
        leading: MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall
            ? BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/library/books'))
            : null,
      ),
      body: SafeArea(
        child: _Directory(
          key: ValueKey((settings.activeProfileKey, auth.serverKey, auth.user!.userId)),
          load: auth.adminUsers,
        ),
      ),
    );
  }
}

class _Directory extends StatefulWidget {
  const _Directory({super.key, required this.load});
  final Future<UserDirectory> Function(int) load;

  @override
  State<_Directory> createState() => _DirectoryState();
}

class _DirectoryState extends State<_Directory> {
  int page = 1;
  late Future<UserDirectory> request = widget.load(page);

  void showPage(int next) {
    setState(() {
      page = next;
      request = widget.load(page);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserDirectory>(
      future: request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: AppCircularProgressIndicator(semanticsLabel: 'Loading users'));
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Couldn’t load users.'),
                TextButton(onPressed: () => showPage(page), child: const Text('Retry')),
              ],
            ),
          );
        }

        final directory = snapshot.requireData;

        return LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final wide = constraints.maxWidth >= Breakpoints.desktopSmall * scale;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    key: ValueKey(page),
                    padding: const EdgeInsets.all(Spacing.md),
                    children: [
                      if (directory.users.isEmpty)
                        const Text('No users on this page.')
                      else if (wide)
                        _directoryTable(context, directory)
                      else
                        for (final user in directory.users) _compactAccount(context, user, directory.quotaBytes),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: Spacing.sm,
                    children: [
                      Text(
                        directory.users.isEmpty ? '${directory.total} users' : rangeLabel(directory),
                      ),
                      TextButton(
                        onPressed: page > 1 ? () => showPage((page - 1).clamp(1, directory.lastPage)) : null,
                        child: const Text('Previous'),
                      ),
                      TextButton(
                        onPressed: page < directory.lastPage ? () => showPage(page + 1) : null,
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String rangeLabel(UserDirectory directory) {
    final first = directory.offset + 1;
    final last = directory.offset + directory.users.length;
    final range = first == last ? '$first' : '$first–$last';
    return '$range of ${directory.total} ${directory.total == 1 ? 'user' : 'users'}';
  }

  static const headings = ['Account', 'Joined', 'Last sign-in', 'Books', 'Server storage', 'Average per book'];

  List<Widget> _cells(BuildContext context, DirectoryUser user, int quota) {
    final signIn = user.lastSignIn;
    final fraction = quota > 0 ? user.usedBytes / quota : 0.0;
    final percentage = quota > 0 ? ' · ${(fraction * 100).round()}%' : '';
    final label = '${_bytes(user.usedBytes)} of ${_bytes(quota)}$percentage';

    return [
      Column(
        key: ValueKey(user.id),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.name, style: Theme.of(context).textTheme.titleSmall),
          if (user.email != null) Text(user.email!),
          Text('${user.isAdmin ? 'Admin' : 'User'} · ${user.status}', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      Text(DateFormat.yMMMd().format(user.joined)),
      Text(signIn == null ? 'No sign-in recorded' : DateFormat.yMMMd().add_jm().format(signIn)),
      Text('${user.bookCount}'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: Spacing.xs),
          ExcludeSemantics(child: LinearProgressIndicator(value: fraction.clamp(0, 1))),
        ],
      ),
      Text(_bytes(user.averageBytes)),
    ];
  }

  Widget _directoryTable(BuildContext context, UserDirectory directory) {
    TableRow row(List<Widget> cells) => TableRow(
      children: [
        for (final cell in cells) Padding(padding: const EdgeInsets.all(Spacing.sm), child: cell),
      ],
    );

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        2: FlexColumnWidth(1.3),
        3: FlexColumnWidth(.6),
        4: FlexColumnWidth(1.7),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(horizontalInside: BorderSide(color: Theme.of(context).dividerColor)),
      children: [
        row([
          for (final heading in headings)
            Semantics(header: true, child: Text(heading, style: Theme.of(context).textTheme.labelLarge)),
        ]),
        for (final user in directory.users) row(_cells(context, user, directory.quotaBytes)),
      ],
    );
  }

  Widget _compactAccount(BuildContext context, DirectoryUser user, int quota) {
    final cells = _cells(context, user, quota);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cells.first,
        for (var index = 1; index < cells.length; index++)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: Text(headings[index], style: Theme.of(context).textTheme.labelMedium)),
                const SizedBox(width: Spacing.sm),
                Expanded(flex: 3, child: cells[index]),
              ],
            ),
          ),
        const Divider(height: Spacing.xl),
      ],
    );
  }

  String _bytes(int? bytes) {
    if (bytes == null) {
      return '—';
    }

    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var size = bytes.toDouble();
    var unit = 0;

    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }

    return '${NumberFormat('0.##').format(size)} ${units[unit]}';
  }
}
