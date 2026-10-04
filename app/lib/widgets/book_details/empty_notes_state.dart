import 'package:flutter/material.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';

/// Empty state widget for when a book has no notes.
class EmptyNotesState extends StatelessWidget {
  final VoidCallback? onAddNote;

  const EmptyNotesState({super.key, this.onAddNote});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      alignment: Alignment.topCenter,
      icon: Icons.note_outlined,
      title: 'No notes yet',
      subtitle: 'Create notes to capture your thoughts about this book.',
      action: EmptyStateAction(onPressed: onAddNote, icon: Icons.add, label: 'Add note'),
    );
  }
}
