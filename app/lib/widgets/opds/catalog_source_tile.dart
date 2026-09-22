import 'package:flutter/material.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';

class CatalogSourceTile extends StatelessWidget {
  const CatalogSourceTile({
    super.key,
    required this.catalog,
    required this.onOpen,
    required this.onEdit,
    required this.onRemove,
  });

  final OpdsCatalog catalog;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall;
    final colors = Theme.of(context).colorScheme;
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
      title: Text(catalog.name),
      subtitle: Text(catalog.uri.host),
      onTap: onOpen,
      trailing: mobile
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Catalog options',
              onSelected: (value) => value == 'edit' ? onEdit() : onRemove(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'remove', child: Text('Remove')),
              ],
            ),
    );
    if (!mobile) return tile;

    return ClipRect(
      child: Dismissible(
        key: ValueKey(catalog.id),
        direction: DismissDirection.horizontal,
        movementDuration: AppMotion.duration(context, const Duration(milliseconds: 200)),
        resizeDuration: null,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            onEdit();
          } else {
            onRemove();
          }
          // Swipes open a sheet; only its explicit confirmation may remove a source.
          return false;
        },
        background: _swipeBackground(
          context,
          label: 'Edit',
          icon: Icons.edit_outlined,
          color: colors.secondaryContainer,
          foreground: colors.onSecondaryContainer,
        ),
        secondaryBackground: _swipeBackground(
          context,
          label: 'Delete',
          icon: Icons.delete_outline,
          color: colors.errorContainer,
          foreground: colors.onErrorContainer,
          trailing: true,
        ),
        child: Material(color: colors.surface, child: tile),
      ),
    );
  }

  Widget _swipeBackground(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required Color foreground,
    bool trailing = false,
  }) => ColoredBox(
    color: color,
    child: Align(
      alignment: trailing ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(height: Spacing.xs),
            Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foreground)),
          ],
        ),
      ),
    ),
  );
}
