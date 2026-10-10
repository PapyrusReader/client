import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/data/repositories/tracking_repository.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/goals/goal_controls.dart';
import 'package:papyrus/widgets/book_details/book_cover_image.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/app_date_picker.dart';
import 'package:papyrus/widgets/shared/searchable_book_field.dart';

class LogReadingSheet extends StatefulWidget {
  const LogReadingSheet({super.key, required this.provider, this.book, this.correcting});
  final GoalsProvider provider;
  final Book? book;
  final ReadingActivity? correcting;

  static Future<void> show(
    BuildContext context, {
    required GoalsProvider provider,
    Book? book,
    ReadingActivity? correcting,
  }) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: AppMotion.animationStyle(context),
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => LogReadingSheet(provider: provider, book: book, correcting: correcting),
  );

  @override
  State<LogReadingSheet> createState() => _LogReadingSheetState();
}

class _LogReadingSheetState extends State<LogReadingSheet> {
  final _form = GlobalKey<FormState>();
  final _minutes = TextEditingController();
  final _pages = TextEditingController();
  final _note = TextEditingController();
  late final TrackingRepository? _repository;
  String? _bookId;
  DateTime _end = DateTime.now();
  bool _finished = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.provider.store.trackingRepository;
    _bookId = widget.book?.id ?? widget.correcting?.bookId;
    final original = widget.correcting;
    _minutes.text = original == null ? '' : '${original.seconds ~/ 60}';
    _pages.text = original == null ? '' : '${original.pages}';
    _note.text = original?.note ?? '';

    if (original != null) {
      _end = original.endTime.toLocal();
      _finished = original.kind == 'completion';
    }
  }

  @override
  void dispose() {
    _minutes.dispose();
    _pages.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _nonNegative(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final n = int.tryParse(value);
    return n == null || n < 0 || n > 100000 ? 'Enter a number from 0 to 100,000.' : null;
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.provider.store.books;

    return GoalControls(
      child: AppBottomSheet(
        title: widget.correcting == null ? 'Log reading' : 'Correct reading entry',
        canClose: !_saving,
        onClose: () => Navigator.pop(context),
        body: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.correcting != null)
                _ReadingBookHeader(
                  book: widget.provider.store.getBook(_bookId!),
                  fallbackTitle: widget.correcting!.bookTitle,
                )
              else
                SearchableBookField(
                  key: ValueKey('log-book-$_bookId'),
                  books: books,
                  value: _bookId,
                  enabled: !_saving,
                  onChanged: (value) => setState(() => _bookId = value),
                ),
              if (books.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: Spacing.sm),
                  child: Text('Add a digital or physical book to your library before logging reading.'),
                ),
              const SizedBox(height: Spacing.lg),
              Wrap(
                spacing: Spacing.md,
                runSpacing: Spacing.sm,
                children: [
                  _dateControl(
                    label: 'Date',
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final date = await showAppDatePicker(
                                context: context,
                                initialDate: _end,
                                firstDate: DateTime(1900),
                                lastDate: DateTime.now(),
                              );

                              if (date != null && mounted) {
                                setState(
                                  () => _end = DateTime(date.year, date.month, date.day, _end.hour, _end.minute),
                                );
                              }
                            },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(DateFormat.yMMMd().format(_end)),
                    ),
                  ),
                  _dateControl(
                    label: 'Finished at',
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final time = await showDialog<TimeOfDay>(
                                context: context,
                                animationStyle: AppMotion.animationStyle(context),
                                builder: (_) => TimePickerDialog(initialTime: TimeOfDay.fromDateTime(_end)),
                              );

                              if (time != null && mounted) {
                                setState(
                                  () => _end = DateTime(_end.year, _end.month, _end.day, time.hour, time.minute),
                                );
                              }
                            },
                      icon: const Icon(Icons.schedule),
                      label: Text(DateFormat.Hm().format(_end)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              LayoutBuilder(
                builder: (context, constraints) {
                  final enlarged = MediaQuery.textScalerOf(context).scale(16) > 24;

                  final width = enlarged
                      ? constraints.maxWidth
                      : ((constraints.maxWidth - Spacing.md) / 2).clamp(0, 220).toDouble();

                  return Wrap(
                    spacing: Spacing.md,
                    runSpacing: Spacing.md,
                    children: [
                      SizedBox(
                        width: width,
                        child: TextFormField(
                          controller: _minutes,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Minutes read'),
                          validator: _nonNegative,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: TextFormField(
                          controller: _pages,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Pages read'),
                          validator: _nonNegative,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: Spacing.md),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('I finished this book'),
                value: _finished,
                onChanged: _saving ? null : (value) => setState(() => _finished = value!),
              ),
              const SizedBox(height: Spacing.md),
              TextFormField(
                controller: _note,
                maxLength: 10000,
                maxLines: 3,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(labelText: 'Note (optional)', alignLabelWithHint: true),
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
        footer: BottomSheetFormActions(
          onCancel: _saving ? null : () => Navigator.pop(context),
          onSave: _saving || books.isEmpty ? null : _save,
          saveLabel: _saving ? 'Saving…' : 'Save reading',
        ),
      ),
    );
  }

  Widget _dateControl({required String label, required Widget child}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: Spacing.sm),
      child,
    ],
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }

    final book = widget.provider.store.getBook(_bookId!);

    if (book == null) {
      setState(() => _error = 'This book no longer exists.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.provider.logReading(
        book: book,
        end: _end.toUtc(),
        minutes: int.tryParse(_minutes.text) ?? 0,
        pages: int.tryParse(_pages.text) ?? 0,
        finished: _finished,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        correcting: widget.correcting,
        repository: _repository,
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }
}

/// Plain book context for entries whose book identity cannot be changed.
class _ReadingBookHeader extends StatelessWidget {
  const _ReadingBookHeader({required this.book, required this.fallbackTitle, this.details = const []});
  final Book? book;
  final String fallbackTitle;
  final List<Widget> details;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(
        child: CoverImagePreview(
          bookId: book?.id,
          imageUrl: book?.coverUrl,
          mediaId: book?.coverMediaId,
          size: BookCoverSize.listThumbnail,
        ),
      ),
      const SizedBox(width: Spacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book?.title ?? fallbackTitle, style: Theme.of(context).textTheme.titleLarge),
            if (book != null && book!.allAuthors.trim().isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                book!.allAuthors,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            ...details,
          ],
        ),
      ),
    ],
  );
}

/// Book titles and dates belong to groups; individual entries retain their audit actions.
class ReadingActivityList extends StatelessWidget {
  const ReadingActivityList({
    super.key,
    required this.activities,
    required this.provider,
    this.correctedIds = const {},
    this.contributionLabel,
  });

  final String? Function(ReadingActivity)? contributionLabel;
  final List<ReadingActivity> activities;
  final GoalsProvider provider;
  final Set<String> correctedIds;

  @override
  Widget build(BuildContext context) {
    final entries = [...activities]..sort((left, right) => right.endTime.compareTo(left.endTime));
    final groups = <String, List<ReadingActivity>>{};

    for (final entry in entries) {
      final day = DateFormat('yyyy-MM-dd').format(entry.endTime.toLocal());
      groups.putIfAbsent('${entry.bookId}:$day', () => []).add(entry);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, group) in groups.values.indexed) ...[
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : Spacing.md, bottom: Spacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: group.first.bookTitle,
                  child: Text(
                    group.first.bookTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  DateFormat.yMMMd().format(group.first.endTime.toLocal()),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          for (final activity in group)
            ReadingActivityTile(
              activity: activity,
              provider: provider,
              corrected: correctedIds.contains(activity.id),
              showBookTitle: false,
              contributionLabel: contributionLabel?.call(activity),
            ),
        ],
      ],
    );
  }
}

class ReadingActivityTile extends StatelessWidget {
  const ReadingActivityTile({
    super.key,
    required this.activity,
    required this.provider,
    this.corrected = false,
    this.showBookTitle = true,
    this.contributionLabel,
  });

  final String? contributionLabel;
  final ReadingActivity activity;
  final GoalsProvider provider;
  final bool corrected;
  final bool showBookTitle;

  @override
  Widget build(BuildContext context) {
    final label = switch (activity.kind == 'completion') {
      true => 'Finished book',
      false when activity.kind == 'reversal' => 'Correction',
      false => [
        if (activity.seconds > 0) activity.seconds < 60 ? '${activity.seconds} sec' : '${activity.seconds ~/ 60} min',
        if (activity.pages > 0) '${activity.pages} pages',
        if (activity.coverage.isNotEmpty) activity.isEstimated ? 'Estimated pages' : 'PDF pages',
      ].join(' · '),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        switch (activity.kind == 'completion') {
          true => Icons.check_circle_outline,
          false when activity.source == 'reader' => Icons.auto_stories_outlined,
          false => Icons.edit_outlined,
        },
      ),
      dense: !showBookTitle,
      title: Text(
        showBookTitle
            ? activity.bookTitle
            : '$label · ${activity.source == 'reader' ? 'Reader' : 'Manual'}${corrected ? ' · Corrected' : ''}',
        maxLines: showBookTitle ? 2 : null,
        overflow: showBookTitle ? TextOverflow.ellipsis : null,
      ),
      subtitle: switch (showBookTitle) {
        true => Text(
          '$label · ${activity.source == 'reader' ? 'Reader' : 'Manual'}${corrected ? ' · Corrected' : ''}\n${DateFormat.yMMMd().add_Hm().format(activity.startTime.toLocal())}',
        ),
        false when contributionLabel == null => null,
        false => Text(contributionLabel!),
      },
      trailing: showBookTitle
          ? null
          : Text(DateFormat.Hm().format(activity.startTime.toLocal()), style: Theme.of(context).textTheme.bodySmall),
      isThreeLine: showBookTitle,
      onTap: () => _details(context),
    );
  }

  Future<void> _details(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 640),
    sheetAnimationStyle: AppMotion.animationStyle(context),
    builder: (sheetContext) => _ActivityDetails(provider: provider, activity: activity, corrected: corrected),
  );
}

class _ActivityDetails extends StatefulWidget {
  const _ActivityDetails({required this.provider, required this.activity, required this.corrected});
  final GoalsProvider provider;
  final ReadingActivity activity;
  final bool corrected;

  @override
  State<_ActivityDetails> createState() => _ActivityDetailsState();
}

class _ActivityDetailsState extends State<_ActivityDetails> {
  late final TrackingRepository? _repository = widget.provider.store.trackingRepository;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    final book = widget.provider.store.getBook(activity.bookId);

    return GoalControls(
      child: AppBottomSheet(
        title: 'Reading activity',
        canClose: !_saving,
        onClose: () => Navigator.pop(context),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReadingBookHeader(
              book: book,
              fallbackTitle: activity.bookTitle,
              details: [
                const SizedBox(height: Spacing.sm),
                if (activity.kind == 'completion')
                  _detailLine(context, Icons.check_circle_outline, 'Finished book')
                else if (activity.kind == 'reversal')
                  _detailLine(context, Icons.undo, 'Entry undone')
                else
                  Text(_readingSummary(activity), style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: Spacing.xs),
                Text(
                  '${DateFormat.yMMMd().add_Hm().format(activity.endTime.toLocal())} · ${activity.source == 'reader' ? 'Reader' : 'Manual entry'}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            if (activity.note?.trim().isNotEmpty == true) ...[
              const SizedBox(height: Spacing.lg),
              Text('Note', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: Spacing.xs),
              Text(activity.note!),
            ],
            if (widget.corrected) ...[
              const SizedBox(height: Spacing.lg),
              _detailLine(context, Icons.history, 'This entry was corrected and no longer contributes.'),
            ],
            if (book == null) ...[
              const SizedBox(height: Spacing.md),
              Text('This book is no longer in your library.', style: Theme.of(context).textTheme.bodySmall),
            ],
            if (!widget.corrected && activity.kind != 'reversal') ...[
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  if (activity.source == 'manual' && book != null)
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () {
                              final parent = Navigator.of(context, rootNavigator: true).context;
                              Navigator.pop(context);
                              LogReadingSheet.show(parent, provider: widget.provider, book: book, correcting: activity);
                            },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Correct entry'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _undo,
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo this entry'),
                  ),
                ],
              ),
            ],
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
        footer: BottomSheetActions(
          primary: FilledButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Done')),
        ),
      ),
    );
  }

  String _duration(int seconds) {
    if (seconds < 60) {
      return '$seconds sec';
    }

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainder = seconds % 60;
    return [if (hours > 0) '${hours}h', if (minutes > 0) '${minutes}m', if (remainder > 0) '${remainder}s'].join(' ');
  }

  String _readingSummary(ReadingActivity activity) {
    final parts = [
      if (activity.seconds > 0) _duration(activity.seconds),
      if (activity.pages > 0) '${activity.pages} ${activity.pages == 1 ? 'page' : 'pages'}',
      if (activity.coverage.isNotEmpty) activity.isEstimated ? 'Estimated EPUB pages' : 'PDF pages',
    ];

    return parts.isEmpty ? 'No reading time or pages recorded.' : parts.join(' · ');
  }

  Widget _detailLine(BuildContext context, IconData icon, String label) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: IconSizes.small, color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(width: Spacing.xs),
      Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
    ],
  );

  Future<void> _undo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.animationStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('Undo reading entry?'),
        content: const Text(
          'This removes its contribution from goals and statistics. The original entry stays in your history.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Undo entry')),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _saving = true);

    try {
      await widget.provider.reverseActivity(widget.activity, repository: _repository);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }
}
