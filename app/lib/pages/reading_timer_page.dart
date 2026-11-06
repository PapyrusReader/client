import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/providers/reading_timer_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/library/library_drawer.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/shared/app_drawer.dart';
import 'package:papyrus/widgets/shared/app_page_bar.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:papyrus/widgets/shared/searchable_book_field.dart';
import 'package:papyrus/widgets/timer/reading_timer_clock.dart';
import 'package:papyrus/widgets/timer/reading_timer_history.dart';
import 'package:provider/provider.dart';

class ReadingTimerPage extends StatefulWidget {
  const ReadingTimerPage({super.key}) : focusMode = false, initialBookId = null, initialTargetSeconds = null;

  const ReadingTimerPage._focus({required this.initialBookId, required this.initialTargetSeconds}) : focusMode = true;

  final bool focusMode;
  final String? initialBookId;
  final int? initialTargetSeconds;

  @override
  State<ReadingTimerPage> createState() => _ReadingTimerPageState();
}

class _ReadingTimerPageState extends State<ReadingTimerPage> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _form = GlobalKey<FormState>();
  final _minutes = TextEditingController(text: '30');
  String? _bookId;
  String? _sessionId;
  Object? _library;
  bool _countdown = false;
  bool _customDuration = false;
  bool _saveDialogOpen = false;
  bool _focusOpen = false;

  @override
  void initState() {
    super.initState();
    _library = context.read<ReadingTimerProvider>().libraryIdentity;
    _bookId = widget.initialBookId;
    _countdown = widget.initialTargetSeconds != null;

    if (widget.initialTargetSeconds != null) {
      _minutes.text = '${widget.initialTargetSeconds! ~/ 60}';
    }
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timer = context.watch<ReadingTimerProvider>();
    final books = context.watch<DataStore>().books;
    final centered = context.select<PreferencesProvider, bool>((preferences) => preferences.pageAlignment == 'center');

    if (!identical(_library, timer.libraryIdentity)) {
      _library = timer.libraryIdentity;
      _bookId = null;
    }

    if (_sessionId != timer.session?.id) {
      _sessionId = timer.session?.id;

      if (timer.session != null) {
        _bookId = timer.session!.bookId;
        final minutes = timer.session!.targetSeconds;

        _countdown = minutes != null;

        if (minutes != null) {
          _minutes.text = '${minutes ~/ 60}';
          _customDuration = ![15, 30, 60].contains(minutes ~/ 60);
        }
      }
    }

    final book = books.where((book) => book.id == (timer.session?.bookId ?? _bookId)).firstOrNull;
    final padding = libraryPageHorizontalPadding(context);

    if (widget.focusMode) {
      return _focusView(context, timer, book);
    }

    return Scaffold(
      key: _scaffold,
      drawer: const LibraryDrawer(currentPath: '/library/timer'),
      body: SafeArea(
        child: Column(
          children: [
            LibraryCollectionHeader(
              title: 'Timer',
              onMenuPressed: () => openAppDrawer(context, _scaffold.currentState),
              actions: [
                TextButton.icon(
                  onPressed: timer.available && !timer.busy && (book != null || timer.session != null)
                      ? () => _openFocus(timer, book)
                      : null,
                  icon: const Icon(Icons.fullscreen_rounded),
                  label: const Text('Focus'),
                ),
              ],
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, viewport) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.all(padding),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (timer.loading) const AppLinearProgressIndicator(),
                          if (timer.error != null && !_saveDialogOpen)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Spacing.md),
                              child: Semantics(
                                liveRegion: true,
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: Spacing.sm,
                                  children: [
                                    Text(timer.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                                    TextButton(onPressed: timer.busy ? null : timer.reload, child: const Text('Retry')),
                                  ],
                                ),
                              ),
                            ),
                          _session(
                            context,
                            timer,
                            books,
                            book,
                            centered: centered,
                            minimumHeight: (viewport.maxHeight - 2 * padding).clamp(0, double.infinity),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _session(
    BuildContext context,
    ReadingTimerProvider timer,
    List<Book> books,
    Book? book, {
    required bool centered,
    required double minimumHeight,
  }) {
    final theme = Theme.of(context);
    final shape = theme.cardTheme.shape;
    final session = timer.session;
    final countdown = session == null ? _countdown : session.targetSeconds != null;
    final editable = session == null && timer.available && !timer.busy;

    final settings = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Mode', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: Spacing.sm),
        SegmentedButton<bool>(
          key: ValueKey(MediaQuery.textScalerOf(context).scale(16) > 24),
          expandedInsets: MediaQuery.textScalerOf(context).scale(16) > 24 ? null : EdgeInsets.zero,
          direction: MediaQuery.textScalerOf(context).scale(16) > 24 ? Axis.vertical : Axis.horizontal,
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled) ? theme.colorScheme.onSurfaceVariant : null,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled) && states.contains(WidgetState.selected)
                  ? theme.colorScheme.surfaceContainerHighest
                  : null,
            ),
          ),
          segments: const [
            ButtonSegment(value: false, label: Text('Stopwatch'), icon: Icon(Icons.timer_outlined)),
            ButtonSegment(value: true, label: Text('Countdown'), icon: Icon(Icons.hourglass_empty_rounded)),
          ],
          selected: {countdown},
          showSelectedIcon: false,
          onSelectionChanged: editable ? (selection) => setState(() => _countdown = selection.single) : null,
        ),
        if (_countdown)
          Visibility(
            visible: countdown,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Spacing.md),
                Text(
                  'Duration',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.sm),
                _duration(timer, editable && countdown),
              ],
            ),
          ),
      ],
    );

    final controls = Column(
      key: const ValueKey('timer-controls-column'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchableBookField(
          key: ValueKey((_library, book?.id)),
          books: books,
          value: book?.id,
          enabled: editable,
          showDetails: true,
          onChanged: (id) => setState(() => _bookId = id),
        ),
        if (books.isEmpty && session == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.go('/library/books'),
              child: const Text('Go to library'),
            ),
          ),
        const SizedBox(height: Spacing.xl),
        _instrument(context, timer, book),
        const SizedBox(height: Spacing.lg),
        settings,
      ],
    );

    return LayoutBuilder(
      key: const ValueKey('timer-panel-layout'),
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960 && MediaQuery.textScalerOf(context).scale(16) <= 24;

        return Container(
          key: const ValueKey('reading-session'),
          constraints: BoxConstraints(minHeight: minimumHeight),
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: ShapeDecoration(
            shape: shape is OutlinedBorder
                ? shape.copyWith(
                    side: BorderSide(color: theme.colorScheme.outlineVariant, width: shape.side.width),
                  )
                : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
          ),
          child: Align(
            alignment: centered ? Alignment.topCenter : Alignment.topLeft,
            child: ConstrainedBox(
              key: const ValueKey('timer-content'),
              constraints: BoxConstraints(maxWidth: wide ? 1040 : 520 - 2 * Spacing.lg),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 520 - 2 * Spacing.lg, child: controls),
                        const SizedBox(width: Spacing.xxl),
                        const Expanded(child: ReadingTimerHistory()),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        controls,
                        const SizedBox(height: Spacing.xl),
                        const Divider(height: 1),
                        const SizedBox(height: Spacing.lg),
                        const ReadingTimerHistory(),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _instrument(BuildContext context, ReadingTimerProvider timer, Book? book) {
    final session = timer.session;
    final countdown = session == null ? _countdown : session.targetSeconds != null;
    final target = session?.targetSeconds ?? (int.tryParse(_minutes.text) ?? 30).clamp(1, 1440) * 60;
    final elapsed = timer.elapsed;
    final remaining = Duration(seconds: (target - elapsed.inSeconds).clamp(0, target));

    final status = switch (session) {
      null => 'Ready',
      _ when timer.goalReached => 'Goal reached',
      _ when timer.finished => 'Finished',
      _ when timer.running => 'Reading',
      _ => 'Paused',
    };

    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.focusMode ? 380 : 360),
          child: ReadingTimerClock(
            key: const ValueKey('timer-clock'),
            digitSize: widget.focusMode ? 88 : 64,
            time: countdown ? remaining : elapsed,
            progress: countdown ? remaining.inSeconds / target : elapsed.inSeconds % 60 / 60,
            countdown: countdown,
            status: status,
          ),
        ),
        const SizedBox(height: Spacing.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: _controls(context, timer, book),
        ),
      ],
    );
  }

  Future<void> _openFocus(ReadingTimerProvider timer, Book? book) async {
    if (_focusOpen || (timer.session == null && !_form.currentState!.validate())) {
      return;
    }

    _focusOpen = true;

    try {
      await Navigator.of(context, rootNavigator: true).push<void>(
        _TimerFocusRoute(
          builder: (context) => ReadingTimerPage._focus(
            initialBookId: book?.id,
            initialTargetSeconds: _countdown ? (int.tryParse(_minutes.text) ?? 30).clamp(1, 1440) * 60 : null,
          ),
        ),
      );
    } finally {
      _focusOpen = false;
    }
  }

  Widget _focusView(BuildContext context, ReadingTimerProvider timer, Book? book) {
    final theme = Theme.of(context);
    final actions = [
      TextButton.icon(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.fullscreen_exit_rounded),
        label: const Text('Exit focus'),
      ),
    ];

    final header = MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall
        ? AppPageToolbar(actions: actions)
        : Padding(
            padding: const EdgeInsets.only(top: Spacing.lg, left: Spacing.lg, right: Spacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
              child: LibraryToolbar(actions: actions),
            ),
          );

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: const ValueKey('timer-focus'),
          body: SafeArea(
            child: Column(
              children: [
                header,
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(Spacing.lg),
                            child: SizedBox(
                              width: 480,
                              child: Form(
                                key: _form,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      book?.title ?? timer.session?.bookTitle ?? 'No book selected',
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: Spacing.xl),
                                    _instrument(context, timer, book),
                                    if (timer.error != null && !_saveDialogOpen) ...[
                                      const SizedBox(height: Spacing.md),
                                      Semantics(
                                        liveRegion: true,
                                        child: Text(timer.error!, style: TextStyle(color: theme.colorScheme.error)),
                                      ),
                                      TextButton(
                                        onPressed: timer.busy ? null : timer.reload,
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _duration(ReadingTimerProvider timer, bool editable) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: Spacing.sm,
          children: [
            for (final minutes in [15, 30, 60])
              ChoiceChip(
                showCheckmark: false,
                labelPadding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
                label: Text('$minutes min'),
                selected: !_customDuration && _minutes.text == '$minutes',
                onSelected: !editable
                    ? null
                    : (_) => setState(() {
                        _minutes.text = '$minutes';
                        _customDuration = false;
                      }),
              ),
            ChoiceChip(
              showCheckmark: false,
              labelPadding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
              label: const Text('Custom'),
              selected: _customDuration,
              onSelected: editable ? (_) => setState(() => _customDuration = true) : null,
            ),
          ],
        ),
      ),
      if (_customDuration) ...[
        const SizedBox(height: Spacing.sm),
        TextFormField(
          controller: _minutes,
          enabled: editable,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Minutes', suffixText: 'min'),
          onChanged: (_) => setState(() {}),
          validator: (value) {
            if (!_countdown || timer.session != null) {
              return null;
            }

            final minutes = int.tryParse(value ?? '');
            return minutes == null || minutes < 1 || minutes > 1440 ? 'Enter 1 to 1,440 minutes.' : null;
          },
        ),
      ],
    ],
  );

  Widget _controls(BuildContext context, ReadingTimerProvider timer, Book? book) {
    final session = timer.session;
    final enabled = timer.available;
    final theme = Theme.of(context);
    final shape = theme.outlinedButtonTheme.style?.shape?.resolve({});
    final buttonStyle = ButtonStyle(
      visualDensity: VisualDensity.standard,
      minimumSize: const WidgetStatePropertyAll(Size(0, 56)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm)),
      shape: WidgetStatePropertyAll(shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
      textStyle: WidgetStatePropertyAll(theme.textTheme.labelLarge),
    );

    final primaryLabel = switch (session) {
      null => 'Start',
      _ when timer.finished => 'Save',
      _ when timer.running => 'Pause',
      _ => 'Resume',
    };

    final primaryIcon = switch (session) {
      _ when timer.finished => Icons.check_rounded,
      _ when timer.running => Icons.pause_rounded,
      _ => Icons.play_arrow_rounded,
    };

    final primary = FilledButton.icon(
      key: const ValueKey('timer-primary-action'),
      style: buttonStyle,
      onPressed: !enabled || (session == null && book == null)
          ? null
          : () {
              if (timer.busy) {
                return;
              }

              if (session == null) {
                if (_form.currentState!.validate()) {
                  timer.start(book!, targetSeconds: _countdown ? int.parse(_minutes.text) * 60 : null);
                }
              } else if (timer.finished) {
                _save(timer, book);
              } else if (timer.running) {
                timer.pause();
              } else {
                timer.resume();
              }
            },
      icon: Icon(primaryIcon),
      label: Text(primaryLabel),
    );

    final reset = IconButton.outlined(
      tooltip: 'Reset timer',
      style: buttonStyle,
      onPressed: enabled && session != null
          ? () {
              if (!timer.busy) {
                _reset(timer);
              }
            }
          : null,
      icon: const Icon(Icons.restart_alt_rounded),
    );

    final secondary = IconButton.outlined(
      key: const ValueKey('timer-secondary-action'),
      tooltip: timer.finished ? 'Resume' : 'Finish',
      style: buttonStyle,
      onPressed: !enabled || session == null
          ? null
          : () async {
              if (timer.busy) {
                return;
              }

              if (timer.finished) {
                await timer.resume();
              } else if (await timer.pause(finish: true) && mounted) {
                await _save(timer, book);
              }
            },
      icon: Icon(timer.finished ? Icons.play_arrow_rounded : Icons.stop_rounded),
    );

    if (MediaQuery.textScalerOf(context).scale(16) > 24) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          const SizedBox(height: Spacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 56, height: 56, child: reset),
              const SizedBox(width: Spacing.md),
              SizedBox(width: 56, height: 56, child: secondary),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(width: 56, height: 56, child: reset),
        const SizedBox(width: Spacing.sm),
        Expanded(child: primary),
        const SizedBox(width: Spacing.sm),
        SizedBox(width: 56, height: 56, child: secondary),
      ],
    );
  }

  Future<void> _reset(ReadingTimerProvider timer) async {
    final session = timer.session;
    final reset = await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.animationStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('Reset timer?'),
        content: const Text('This session’s reading time won’t be saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );

    if (reset == true && mounted && timer.session?.id == session?.id) {
      await timer.discard();
    }
  }

  Future<void> _save(ReadingTimerProvider timer, Book? book) async {
    if (_saveDialogOpen) {
      return;
    }

    if (timer.elapsed.inSeconds < 1) {
      await timer.discard();
      return;
    }

    final sessionId = timer.session!.id;
    setState(() => _saveDialogOpen = true);

    try {
      final saved = await showDialog<bool>(
        context: context,
        animationStyle: AppMotion.animationStyle(context),
        builder: (_) => _SaveSessionDialog(timer: timer, book: book, sessionId: sessionId),
      );

      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reading session saved')));
      }
    } finally {
      if (mounted) {
        setState(() => _saveDialogOpen = false);
      }
    }
  }
}

class _SaveSessionDialog extends StatefulWidget {
  const _SaveSessionDialog({required this.timer, required this.book, required this.sessionId});

  final ReadingTimerProvider timer;
  final Book? book;
  final String sessionId;

  @override
  State<_SaveSessionDialog> createState() => _SaveSessionDialogState();
}

class _SaveSessionDialogState extends State<_SaveSessionDialog> {
  final _page = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.timer,
    builder: (context, _) {
      final timer = widget.timer;
      final current = timer.session?.id == widget.sessionId;
      final saving = _saving || timer.busy;
      final error = timer.error ?? (!current && !_saving ? 'This session is no longer available.' : null);

      return AlertDialog(
        title: const Text('Save session'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _page,
                enabled: current && !saving && widget.book != null,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Current page (optional)'),
              ),
              if (error != null) ...[
                const SizedBox(height: Spacing.md),
                Semantics(
                  liveRegion: true,
                  child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: !current || saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    final saved = await timer.save(currentPage: int.tryParse(_page.text));

                    if (!context.mounted) {
                      return;
                    }

                    if (saved) {
                      Navigator.pop(context, true);
                    } else {
                      setState(() => _saving = false);
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}

class _TimerFocusRoute extends MaterialPageRoute<void> {
  _TimerFocusRoute({required super.builder}) : super(settings: const RouteSettings(name: '/library/timer/focus'));

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}
