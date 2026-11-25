import 'package:flutter/material.dart';

class ActivityPagination extends StatelessWidget {
  const ActivityPagination({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onChanged,
    this.previousLabel = 'Newer entries',
    this.nextLabel = 'Older entries',
  });
  final String previousLabel;
  final String nextLabel;
  final int page;
  final int pageCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: previousLabel,
        icon: const Icon(Icons.chevron_left),
        onPressed: page == 0 ? null : () => onChanged(page - 1),
      ),
      Flexible(child: Text('Page ${page + 1} of $pageCount')),
      IconButton(
        tooltip: nextLabel,
        icon: const Icon(Icons.chevron_right),
        onPressed: page + 1 == pageCount ? null : () => onChanged(page + 1),
      ),
    ],
  );
}
