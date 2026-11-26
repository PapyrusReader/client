import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/admin/user_directory.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/goals/activity_pagination.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
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

    final compact = MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LibraryPageHeader(
              title: 'Users',
              compact: compact,
              leading: compact
                  ? BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/library/books'))
                  : null,
            ),
            Expanded(
              child: _Directory(
                key: ValueKey((settings.activeProfileKey, auth.serverKey, auth.user!.userId)),
                load: auth.adminUsers,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Directory extends StatefulWidget {
  const _Directory({super.key, required this.load});

  final Future<UserDirectory> Function(int page, DirectoryColumn column, bool descending) load;

  @override
  State<_Directory> createState() => _DirectoryState();
}

typedef _DirectoryQuery = ({int page, DirectoryColumn column, bool descending});

class _DirectoryState extends State<_Directory> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController(keepScrollOffset: false);
  static const _initialQuery = (page: 1, column: DirectoryColumn.name, descending: false);
  _DirectoryQuery _requested = _initialQuery;
  _DirectoryQuery _displayed = _initialQuery;
  UserDirectory? _directory;
  int _requestId = 0;
  bool _loading = true;
  bool _failed = false;

  DirectoryColumn get _column => (_loading ? _requested : _displayed).column;
  bool get _descending => (_loading ? _requested : _displayed).descending;

  @override
  void initState() {
    super.initState();
    _load(_initialQuery);
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  Future<void> _load(_DirectoryQuery query) async {
    final requestId = ++_requestId;
    UserDirectory directory;

    try {
      directory = await widget.load(query.page, query.column, query.descending);

      if (mounted && requestId == _requestId && query.page > directory.lastPage) {
        directory = await widget.load(directory.lastPage, query.column, query.descending);
      }
    } catch (_) {
      if (mounted && requestId == _requestId) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }

      return;
    }

    if (!mounted || requestId != _requestId) {
      return;
    }

    setState(() {
      _directory = directory;
      _displayed = query;
      _loading = false;
    });

    if (_vertical.hasClients) {
      _vertical.jumpTo(0);
    }
  }

  void _showPage(int page, DirectoryColumn column, bool descending) {
    final query = (page: page, column: column, descending: descending);

    setState(() {
      _requested = query;
      _loading = true;
      _failed = false;
    });

    _load(query);
  }

  Widget _retry() => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: Spacing.sm,
    children: [
      const Text('Couldn’t load users.'),
      TextButton(
        onPressed: () => _showPage(_requested.page, _requested.column, _requested.descending),
        child: const Text('Retry'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final directory = _directory;

    if (directory == null) {
      return Center(child: _failed ? _retry() : const AppCircularProgressIndicator(semanticsLabel: 'Loading users'));
    }

    final padding = libraryPageHorizontalPadding(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_failed) _retry(),
        SizedBox(
          height: 2,
          child: _loading ? const AppLinearProgressIndicator(semanticsLabel: 'Updating users') : null,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  MediaQuery.sizeOf(context).width >= Breakpoints.desktopSmall &&
                  constraints.maxWidth >= Breakpoints.tablet * MediaQuery.textScalerOf(context).scale(1);
              final contentWidth = constraints.maxWidth - 2 * padding;

              return ListView(
                controller: _vertical,
                padding: EdgeInsets.fromLTRB(padding, wide ? Spacing.lg : Spacing.xs, padding, Spacing.lg),
                children: [
                  if (wide)
                    Text(directory.rangeLabel)
                  else
                    _compactToolbar(context, directory.rangeLabel, contentWidth),
                  SizedBox(height: wide ? Spacing.md : Spacing.sm),
                  if (directory.users.isEmpty)
                    const Text('No users on this page.')
                  else if (wide)
                    _table(directory, contentWidth)
                  else
                    for (final user in directory.users) _compactAccount(context, user, directory.quotaBytes),
                  if (directory.lastPage > 1) ...[
                    const SizedBox(height: Spacing.md),
                    ActivityPagination(
                      page: directory.page - 1,
                      pageCount: directory.lastPage,
                      previousLabel: 'Previous page',
                      nextLabel: 'Next page',
                      onChanged: (index) => _showPage(index + 1, _column, _descending),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _compactToolbar(BuildContext context, String rangeLabel, double width) => Row(
    children: [
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width * 0.4),
        child: Text(rangeLabel),
      ),
      const SizedBox(width: Spacing.sm),
      Expanded(
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: PopupMenuButton<DirectoryColumn>(
            tooltip: 'Sort users by',
            popUpAnimationStyle: AppMotion.animationStyle(context),
            initialValue: _column,
            onSelected: (column) => _showPage(1, column, column == _column && _descending),
            itemBuilder: (_) => [
              for (final column in DirectoryColumn.values) PopupMenuItem(value: column, child: Text(column.label)),
            ],
            child: Padding(
              padding: const EdgeInsets.all(Spacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text('Sort by ${_column.label}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: _descending ? 'Sort ascending' : 'Sort descending',
        onPressed: () => _showPage(1, _column, !_descending),
        icon: Icon(_descending ? Icons.arrow_downward : Icons.arrow_upward),
      ),
    ],
  );

  Widget _table(UserDirectory directory, double width) => Scrollbar(
    controller: _horizontal,
    thumbVisibility: true,
    child: SingleChildScrollView(
      key: const PageStorageKey('admin-users-columns'),
      controller: _horizontal,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width),
        child: DataTable(
          sortColumnIndex: _column.index,
          sortAscending: !_descending,
          horizontalMargin: Spacing.sm,
          columnSpacing: Spacing.lg,
          columns: [
            for (final column in DirectoryColumn.values)
              DataColumn(
                label: Text(column.label),
                numeric:
                    column == DirectoryColumn.books ||
                    column == DirectoryColumn.storage ||
                    column == DirectoryColumn.average,
                onSort: (_, ascending) => _showPage(1, column, !ascending),
              ),
          ],
          rows: [
            for (final user in directory.users)
              DataRow(
                key: ValueKey(user.id),
                cells: [
                  for (final column in DirectoryColumn.values)
                    DataCell(_value(column, user, directory.quotaBytes, showQuotaBar: true)),
                ],
              ),
          ],
        ),
      ),
    ),
  );

  Widget _compactAccount(BuildContext context, DirectoryUser user, int quota) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      key: ValueKey(user.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(user.name, style: textTheme.titleMedium)),
        for (final column in DirectoryColumn.values.where((column) => column != DirectoryColumn.name))
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: Text(column.label, style: textTheme.labelMedium)),
                const SizedBox(width: Spacing.sm),
                Expanded(flex: 3, child: _value(column, user, quota)),
              ],
            ),
          ),
        const Divider(height: Spacing.xl),
      ],
    );
  }

  Widget _value(DirectoryColumn column, DirectoryUser user, int quota, {bool showQuotaBar = false}) {
    final signIn = user.lastSignIn;

    return switch (column) {
      DirectoryColumn.name => Text(user.name),
      DirectoryColumn.email => Text(user.email ?? '—'),
      DirectoryColumn.status => Text(user.status),
      DirectoryColumn.joined => Text(DateFormat.yMMMd().format(user.joined)),
      DirectoryColumn.signIn => Text(
        signIn == null ? 'No sign-in recorded' : DateFormat.yMMMd().add_jm().format(signIn),
      ),
      DirectoryColumn.books => Text('${user.bookCount}'),
      DirectoryColumn.storage => Text(_bytes(user.usedBytes)),
      DirectoryColumn.quota => _quotaUsage(user.usedBytes, quota, showBar: showQuotaBar),
      DirectoryColumn.average => Text(_bytes(user.averageBytes)),
    };
  }

  Widget _quotaUsage(int bytes, int quota, {required bool showBar}) {
    if (quota <= 0) {
      return const Text('—');
    }

    final fraction = bytes / quota;
    final percentage = Text('${(fraction * 100).round()}%');

    if (!showBar) {
      return percentage;
    }

    return SizedBox(
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          percentage,
          const SizedBox(height: Spacing.xs),
          ExcludeSemantics(child: LinearProgressIndicator(value: fraction.clamp(0, 1))),
        ],
      ),
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
