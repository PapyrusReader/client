import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/data/repositories/tracking_repository.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/app_date_picker.dart';

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
    if (value == null || value.isEmpty) return null;
    final n = int.tryParse(value);
    return n == null || n < 0 || n > 100000 ? 'Enter a number from 0 to 100,000.' : null;
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.provider.store.books;
    return AppBottomSheet(
      title: widget.correcting == null ? 'Log reading' : 'Correct reading entry',
      canClose: !_saving,
      onClose: () => Navigator.pop(context),
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: books.any((book) => book.id == _bookId) ? _bookId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Book'),
              items: [
                for (final book in books)
                  DropdownMenuItem(
                    value: book.id,
                    child: Text(book.title, overflow: TextOverflow.ellipsis),
                  ),
              ],
              validator: (value) => value == null ? 'Choose a book.' : null,
              onChanged: _saving || widget.correcting != null ? null : (value) => setState(() => _bookId = value),
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
                OutlinedButton.icon(
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
                            setState(() => _end = DateTime(date.year, date.month, date.day, _end.hour, _end.minute));
                          }
                        },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(DateFormat.yMMMd().format(_end)),
                ),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final time = await showDialog<TimeOfDay>(
                            context: context,
                            animationStyle: AppMotion.animationStyle(context),
                            builder: (_) => TimePickerDialog(initialTime: TimeOfDay.fromDateTime(_end)),
                          );
                          if (time != null && mounted) {
                            setState(() => _end = DateTime(_end.year, _end.month, _end.day, time.hour, time.minute));
                          }
                        },
                  icon: const Icon(Icons.schedule),
                  label: Text(DateFormat.Hm().format(_end)),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            TextFormField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minutes read',
                helperText: 'The session ends at the time above.',
              ),
              validator: _nonNegative,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _pages,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pages read'),
              validator: _nonNegative,
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
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: Spacing.md),
            const Text(
              'Manual entries count toward matching goals. Reading before a goal was created stays in your history but does not count toward that goal.',
            ),
            if (widget.correcting != null)
              const Padding(
                padding: EdgeInsets.only(top: Spacing.md),
                child: Text('The original entry is retained as corrected in your activity history.'),
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
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
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
      if (mounted) Navigator.pop(context);
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

class ReadingActivityTile extends StatelessWidget {
  const ReadingActivityTile({super.key, required this.activity, required this.provider, this.corrected = false});
  final ReadingActivity activity;
  final GoalsProvider provider;
  final bool corrected;
  @override
  Widget build(BuildContext context) {
    final label = activity.kind == 'completion'
        ? 'Finished book'
        : activity.kind == 'reversal'
        ? 'Correction'
        : [
            if (activity.seconds > 0)
              activity.seconds < 60 ? '${activity.seconds} sec' : '${activity.seconds ~/ 60} min',
            if (activity.pages > 0) '${activity.pages} pages',
            if (activity.coverage.isNotEmpty) activity.isEstimated ? 'Estimated pages' : 'PDF pages',
          ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        activity.kind == 'completion'
            ? Icons.check_circle_outline
            : activity.source == 'reader'
            ? Icons.auto_stories_outlined
            : Icons.edit_outlined,
      ),
      title: Text(activity.bookTitle),
      subtitle: Text(
        '$label · ${activity.source == 'reader' ? 'Reader' : 'Manual'}${corrected ? ' · Corrected' : ''}\n${DateFormat.yMMMd().add_Hm().format(activity.startTime.toLocal())}',
      ),
      isThreeLine: true,
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
    return AppBottomSheet(
      title: 'Reading activity',
      canClose: !_saving,
      onClose: () => Navigator.pop(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(activity.bookTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Spacing.md),
          Text(
            '${activity.source == 'reader' ? 'Recorded by the reader' : 'Logged manually'} · ${DateFormat.yMMMd().add_Hm().format(activity.startTime.toLocal())}',
          ),
          const SizedBox(height: Spacing.md),
          if (activity.kind == 'reading')
            Text(
              '${activity.seconds ~/ 60} minutes · ${activity.pages > 0
                  ? '${activity.pages} manual pages'
                  : activity.isEstimated
                  ? 'Estimated EPUB coverage'
                  : activity.coverage.isEmpty
                  ? 'No pages logged'
                  : 'PDF coverage'}',
            ),
          if (activity.kind == 'completion') const Text('Explicitly marked as finished.'),
          if (activity.note != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.md),
              child: Text(activity.note!),
            ),
          if (widget.corrected)
            const Padding(
              padding: EdgeInsets.only(top: Spacing.md),
              child: Text('This entry was corrected and no longer contributes.'),
            ),
          if (book == null)
            const Padding(
              padding: EdgeInsets.only(top: Spacing.md),
              child: Text('The book was removed. Its activity history is retained.'),
            ),
          if (!widget.corrected && activity.source == 'manual' && book != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.md),
              child: OutlinedButton.icon(
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
            ),
          if (!widget.corrected)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.md),
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _undo,
                icon: const Icon(Icons.undo),
                label: const Text('Undo this entry'),
              ),
            ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
      footer: BottomSheetFormActions(
        onCancel: null,
        onSave: _saving ? null : () => Navigator.pop(context),
        saveLabel: 'Done',
      ),
    );
  }

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
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.provider.reverseActivity(widget.activity, repository: _repository);
      if (mounted) Navigator.pop(context);
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
