import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/opds/opds_sheet.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

/// Opens transfer details without consuming space in the catalog feed.
class OpdsDownloadsButton extends StatelessWidget {
  const OpdsDownloadsButton({super.key, required this.downloads, required this.onRetry, this.compact});

  final OpdsDownloads downloads;
  final ValueChanged<OpdsDownloadJob> onRetry;
  final bool? compact;

  void _show(BuildContext context) {
    showOpdsSheet<void>(
      context,
      title: 'Downloads',
      scrollable: false,
      child: _DownloadsList(downloads: downloads, onRetry: onRetry),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: downloads,
    builder: (context, _) {
      final active = downloads.jobs.where((job) => job.isActive).length;
      final failed = downloads.jobs.any((job) => job.status == OpdsDownloadStatus.failed);
      final icon = Badge(
        isLabelVisible: active > 0,
        label: Text('$active'),
        child: Icon(
          failed ? Icons.error_outline : Icons.downloading_outlined,
          color: failed ? Theme.of(context).colorScheme.error : null,
        ),
      );
      if (compact ?? MediaQuery.sizeOf(context).width < 600) {
        return IconButton(tooltip: 'Downloads', onPressed: () => _show(context), icon: icon);
      }
      return Tooltip(
        message: 'Downloads',
        child: TextButton.icon(onPressed: () => _show(context), icon: icon, label: const Text('Downloads')),
      );
    },
  );
}

class _DownloadsList extends StatelessWidget {
  const _DownloadsList({required this.downloads, required this.onRetry});
  final OpdsDownloads downloads;
  final ValueChanged<OpdsDownloadJob> onRetry;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: downloads,
    builder: (context, _) {
      final jobs = downloads.jobs;
      if (jobs.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.xl),
          child: Text('No downloads yet'),
        );
      }
      return ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: jobs.length,
        separatorBuilder: (_, _) => const Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.sm),
          child: Divider(),
        ),
        itemBuilder: (context, index) => _job(context, jobs[index]),
      );
    },
  );

  Widget _job(BuildContext context, OpdsDownloadJob job) {
    final theme = Theme.of(context);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(job.publication.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        Text(
          job.error ?? opdsDownloadStatus(job),
          style: theme.textTheme.bodySmall?.copyWith(
            color: job.error == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.error,
          ),
        ),
      ],
    );
    return Column(
      key: ValueKey(job.key),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (!job.isCancellable && job.isActive) return info;
            final actions = _actions(context, job);
            if (job.isCancellable || constraints.maxWidth >= 300 * MediaQuery.textScalerOf(context).scale(1)) {
              return Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: Spacing.md),
                  actions,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: Spacing.sm),
                Align(alignment: AlignmentDirectional.centerEnd, child: actions),
              ],
            );
          },
        ),
        if (job.isActive) ...[
          const SizedBox(height: Spacing.sm),
          AppLinearProgressIndicator(value: job.status == OpdsDownloadStatus.downloading ? job.progress : null),
        ],
      ],
    );
  }

  Widget _actions(BuildContext context, OpdsDownloadJob job) => Wrap(
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: Spacing.xs,
    children: [
      if (job.isCancellable)
        IconButton(
          tooltip: 'Cancel download',
          onPressed: () => downloads.cancel(job.key),
          icon: const Icon(Icons.close),
        ),
      if (!job.isActive) ...[
        if (job.status == OpdsDownloadStatus.complete)
          TextButton(
            style: TextButton.styleFrom(textStyle: Theme.of(context).textTheme.labelLarge),
            onPressed: job.bookId == null
                ? null
                : () {
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.go('/library/details/${job.bookId}');
                  },
            child: const Text('Open book'),
          )
        else
          TextButton(
            style: TextButton.styleFrom(textStyle: Theme.of(context).textTheme.labelLarge),
            onPressed: () => onRetry(job),
            child: const Text('Retry'),
          ),
        IconButton(
          tooltip: 'Dismiss download',
          onPressed: () => downloads.dismiss(job.key),
          icon: const Icon(Icons.close, size: IconSizes.small),
        ),
      ],
    ],
  );
}

String opdsDownloadStatus(OpdsDownloadJob job) => switch (job.status) {
  OpdsDownloadStatus.downloading =>
    job.total == null
        ? 'Downloading · ${job.received ~/ 1024} KB'
        : 'Downloading · ${(100 * (job.progress ?? 0)).round()}%',
  OpdsDownloadStatus.importing => 'Importing…',
  OpdsDownloadStatus.committing => 'Adding to library…',
  OpdsDownloadStatus.complete => 'Added to library',
  OpdsDownloadStatus.failed => 'Download failed',
  OpdsDownloadStatus.cancelled => 'Cancelled',
};
