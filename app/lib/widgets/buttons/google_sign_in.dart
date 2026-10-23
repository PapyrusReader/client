import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/widgets/buttons/google_auth_button.dart';
import 'package:papyrus/widgets/profile/account_deletion_dialog.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/themes/app_motion.dart';

/// A Google Sign-in button with loading state and error handling.
class GoogleSignInButton extends StatefulWidget {
  /// Button text
  final String title;

  /// Optional callback when sign-in is successful
  final VoidCallback? onSuccess;

  /// Optional callback when sign-in fails
  final VoidCallback? onError;

  const GoogleSignInButton({super.key, required this.title, this.onSuccess, this.onError});

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _isSigningIn = false;

  Future<void> _handleSignIn() async {
    if (_isSigningIn) {
      return;
    }

    setState(() => _isSigningIn = true);

    try {
      final provider = Provider.of<AuthProvider>(context, listen: false);
      final result = await provider.signInWithGoogle();

      if (!mounted) {
        return;
      }

      if (result) {
        widget.onSuccess?.call();
        context.goNamed('LIBRARY');
      } else {
        final recovery = provider.takePendingRecovery();

        if (recovery != null) {
          setState(() => _isSigningIn = false);
          await showAccountDeletionDialog(context, authorization: recovery);
          return;
        }

        if (provider.error == null) {
          return;
        }

        widget.onError?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          snackBarAnimationStyle: AppMotion.animationStyle(context),
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text(provider.error!),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      widget.onError?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        snackBarAnimationStyle: AppMotion.animationStyle(context),
        SnackBar(
          duration: const Duration(seconds: 5),
          content: const Text('Failed to sign in with Google account.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GoogleAuthButton(
      title: widget.title,
      isLoading: _isSigningIn,
      onPressed: _isSigningIn ? null : _handleSignIn,
    );
  }
}
