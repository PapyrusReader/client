import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

/// Continue/submit button with loading state for auth pages.
class AuthContinueButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;
  final bool isDesktop;
  final DateTime? retryAt;

  const AuthContinueButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
    required this.isDesktop,
    this.retryAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonHeight = isDesktop ? ComponentSizes.buttonHeightDesktop : ComponentSizes.buttonHeightMobile;

    return StreamBuilder<DateTime>(
      stream: retryAt == null ? null : Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
      builder: (context, snapshot) {
        final remaining = retryAt == null
            ? 0
            : (retryAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(0, 86400);

        return ElevatedButton(
          onPressed: isLoading || remaining > 0 ? null : onPressed,
          style: ElevatedButton.styleFrom(
            minimumSize: Size.fromHeight(buttonHeight),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            elevation: AppElevation.level2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.buttonPaddingHorizontal,
              vertical: Spacing.buttonPaddingVertical,
            ),
          ),
          child: remaining > 0
              ? Text('Try again in ${remaining}s')
              : isLoading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: AppCircularProgressIndicator(
                    semanticsLabel: 'Please wait',
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Flexible(
                      child: Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Icon(Icons.arrow_forward, size: IconSizes.medium, color: theme.colorScheme.onPrimary),
                  ],
                ),
        );
      },
    );
  }
}
