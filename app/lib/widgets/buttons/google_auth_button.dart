import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

class GoogleAuthButton extends StatelessWidget {
  final String title;
  final bool isLoading;
  final VoidCallback? onPressed;

  const GoogleAuthButton({super.key, required this.title, required this.onPressed, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(ComponentSizes.buttonHeightMobile),
        side: BorderSide(width: BorderWidths.thin, color: theme.colorScheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.googleButton)),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.buttonPaddingVertical),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 24,
            child: isLoading
                ? AppCircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                    semanticsLabel: 'Signing in with Google',
                  )
                : const Image(image: AssetImage('assets/images/google_logo.png'), fit: BoxFit.contain),
          ),
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
