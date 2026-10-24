import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/platform/web_redirect.dart';
import 'package:papyrus/widgets/profile/account_deletion_dialog.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

class OAuthCallbackPage extends StatefulWidget {
  final Uri callbackUri;

  const OAuthCallbackPage({super.key, required this.callbackUri});

  @override
  State<OAuthCallbackPage> createState() => _OAuthCallbackPageState();
}

class _OAuthCallbackPageState extends State<OAuthCallbackPage> {
  String? _errorMessage;
  bool _showingConfirmation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _completeSignIn());
  }

  Future<void> _completeSignIn() async {
    final authProvider = context.read<AuthProvider>();
    clearBrowserQuery();

    final success = await authProvider.completeGoogleSignIn(widget.callbackUri);

    if (!mounted) {
      return;
    }

    if (success) {
      context.goNamed('LIBRARY');
      return;
    }

    final recovery = authProvider.takePendingRecovery();

    if (recovery != null) {
      setState(() => _showingConfirmation = true);
      await showAccountDeletionDialog(context, authorization: recovery);

      if (mounted && !authProvider.isSignedIn) {
        context.go('/login');
      }

      return;
    }

    setState(() {
      _errorMessage = authProvider.error ?? 'Google sign-in failed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_showingConfirmation) {
      return Scaffold(
        body: SizedBox.expand(
          child: Image.asset(
            'assets/images/welcome-illustration.png',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage == null) ...[
                  const AppCircularProgressIndicator(),
                  const SizedBox(height: Spacing.lg),
                  Text('Completing sign-in...', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                ] else ...[
                  Icon(Icons.error_outline, color: theme.colorScheme.error, size: IconSizes.large),
                  const SizedBox(height: Spacing.md),
                  Text(_errorMessage!, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                  const SizedBox(height: Spacing.lg),
                  FilledButton(onPressed: () => context.go('/login'), child: const Text('Back to sign in')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
