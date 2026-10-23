import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:provider/provider.dart';

Future<void> showAccountDeletionDialog(
  BuildContext context, {
  AccountDeletionAuthorization? authorization,
}) async {
  final auth = context.read<AuthProvider>();
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final animationStyle = AppMotion.animationStyle(context);

  final message = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    animationStyle: animationStyle,
    builder: (_) => AccountDeletionDialog(
      auth: auth,
      authorization: authorization,
    ),
  );

  if (message == null) {
    return;
  }

  if (authorization != null) {
    router.goNamed('LIBRARY');
    return;
  }

  router.go('/login');

  messenger.showSnackBar(
    snackBarAnimationStyle: animationStyle,
    SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
  );
}

class AccountDeletionDialog extends StatefulWidget {
  final AuthProvider auth;
  final AccountDeletionAuthorization? authorization;

  const AccountDeletionDialog({
    super.key,
    required this.auth,
    this.authorization,
  });

  @override
  State<AccountDeletionDialog> createState() => _AccountDeletionDialogState();
}

class _AccountDeletionDialogState extends State<AccountDeletionDialog> {
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final authorization = widget.authorization;
    String? message;

    if (authorization != null) {
      if (await widget.auth.recoverAccount(authorization)) {
        message = 'Account kept.';
      }
    } else {
      final deadline = await widget.auth.deleteAccount();

      if (deadline != null) {
        message =
            'Account deletion scheduled for ${DateFormat.yMMMd().format(deadline.toLocal())}. '
            'Sign in before then to keep your account.';
      }
    }

    if (mounted) {
      Navigator.pop(context, message);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await action();
    } catch (error) {
      if (mounted) {
        _error = error is AuthApiException ? error.message : 'Unable to connect. Please try again.';
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authorization = widget.authorization;
    final recovering = authorization?.deletionPending ?? false;
    final deadline = authorization == null
        ? null
        : '${DateFormat.yMMMd().format(authorization.deletionDueAt.toLocal())} at '
              '${DateFormat.jm().format(authorization.deletionDueAt.toLocal())}';

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.all(Spacing.lg),
        title: Text(recovering ? 'Keep your account?' : 'Delete account?'),
        content: SizedBox(
          width: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (recovering)
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Your account is scheduled for deletion on '),
                      TextSpan(
                        text: deadline,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: '. Keep your account to cancel deletion.'),
                    ],
                  ),
                )
              else
                const Text(
                  'Your account, synced library and reading data will be permanently deleted after 30 days. '
                  'You’ll be signed out immediately. You can cancel deletion by signing in before then.',
                ),

              if (_error != null) ...[
                const SizedBox(height: Spacing.md),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(recovering ? 'Not now' : 'Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _run(_submit),
            style: !recovering
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  )
                : null,
            child: _busy
                ? const SizedBox.square(dimension: 20, child: AppCircularProgressIndicator(strokeWidth: 2))
                : Text(recovering ? 'Keep account' : 'Delete account'),
          ),
        ],
      ),
    );
  }
}
