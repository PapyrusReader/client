import 'package:flutter/material.dart';
import 'package:papyrus/reader/reader_library.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

class ReaderBookmarkButton extends StatefulWidget {
  const ReaderBookmarkButton({
    super.key,
    required this.library,
    required this.snapshot,
    this.isBusy = false,
    this.floating = false,
  });

  final ReaderLibrary library;
  final ReaderSnapshot snapshot;
  final bool isBusy;
  final bool floating;

  @override
  State<ReaderBookmarkButton> createState() => _ReaderBookmarkButtonState();
}

class _ReaderBookmarkButtonState extends State<ReaderBookmarkButton> {
  String? _pendingLabel;

  Future<void> _toggle() async {
    if (_pendingLabel != null) {
      return;
    }

    final saved = widget.library.bookmarkAt(widget.snapshot) != null;
    setState(() => _pendingLabel = saved ? 'Removing bookmark…' : 'Saving bookmark…');

    try {
      await widget.library.toggleBookmark(context, widget.snapshot);
    } finally {
      if (mounted) {
        setState(() => _pendingLabel = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library.store,
    builder: (context, _) {
      final saved = widget.library.bookmarkAt(widget.snapshot) != null;
      final enabled =
          _pendingLabel == null && !widget.isBusy && widget.library.isCurrent && widget.snapshot.locator != null;
      final label = _pendingLabel ?? (saved ? 'Remove bookmark' : 'Add bookmark');
      final icon = Icon(
        saved ? Icons.bookmark : Icons.bookmark_add_outlined,
        color: saved ? Theme.of(context).colorScheme.primary : null,
      );

      return Semantics(
        selected: saved,
        liveRegion: true,
        child: widget.floating
            ? FloatingActionButton(
                heroTag: null,
                tooltip: saved || _pendingLabel != null ? label : 'Bookmark this location',
                onPressed: enabled ? _toggle : null,
                child: icon,
              )
            : IconButton(
                tooltip: label,
                onPressed: enabled ? _toggle : null,
                icon: icon,
              ),
      );
    },
  );
}
