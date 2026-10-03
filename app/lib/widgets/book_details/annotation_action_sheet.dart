import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/models/annotation.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/themes/app_motion.dart';

/// Result of annotation action sheet selection.
enum AnnotationAction { edit, delete }

/// Bottom sheet for annotation actions (edit, delete).
class AnnotationActionSheet extends StatelessWidget {
  final Annotation annotation;

  const AnnotationActionSheet({super.key, required this.annotation});

  /// Shows the action sheet and returns the selected action.
  static Future<AnnotationAction?> show(BuildContext context, {required Annotation annotation}) async {
    return showModalBottomSheet<AnnotationAction>(
      sheetAnimationStyle: AppMotion.animationStyle(context),
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AnnotationActionSheet(annotation: annotation),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppBottomSheet(
      header: Text(
        annotation.location.shortLocation,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Edit annotation action
          ListTile(
            leading: Icon(Icons.edit_outlined, color: colorScheme.onSurface),
            title: const Text('Edit annotation'),
            onTap: () => Navigator.of(context).pop(AnnotationAction.edit),
          ),

          // Delete action
          ListTile(
            leading: Icon(Icons.delete_outline, color: colorScheme.error),
            title: Text('Delete annotation', style: TextStyle(color: colorScheme.error)),
            onTap: () => Navigator.of(context).pop(AnnotationAction.delete),
          ),

          const SizedBox(height: Spacing.sm),
        ],
      ),
    );
  }
}
