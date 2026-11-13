import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/pages/auth/actions.dart';
import 'package:papyrus/platform/web_redirect.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/utils/responsive.dart';
import 'package:papyrus/widgets/auth/auth_page_layouts.dart';
import 'package:papyrus/widgets/input/email_input.dart';
import 'package:papyrus/widgets/input/validated_text_form_field.dart';
import 'package:provider/provider.dart';

class VerificationPage extends StatefulWidget {
  final String? token;
  final bool isLink;

  const VerificationPage({super.key, this.token, this.isLink = false});

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  Timer? _timer;
  AuthProvider? _auth;
  String? _serverKey;
  String? _token;
  String? _message;
  String? _recipient;
  bool _busy = false;
  bool _verified = false;
  bool _verificationFailed = false;
  bool _invalidLink = false;
  bool _serverChanged = false;

  @override
  void initState() {
    super.initState();
    _token = widget.token;
    _invalidLink = widget.isLink && (_token == null || _token!.isEmpty);

    if (widget.isLink) {
      clearBrowserQuery();
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    _auth = auth;

    if (_serverKey == null) {
      _serverKey = auth.serverKey;
      _recipient = auth.pendingVerification?.email;
      _email.text = _recipient ?? '';

      if (widget.isLink && !_invalidLink) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _verify();
          }
        });
      }
    } else if (_serverKey != auth.serverKey) {
      _token = null;
      _email.clear();
      _recipient = null;
      _serverChanged = true;
      _message = null;
    }
  }

  @override
  void dispose() {
    _token = null;

    if (_busy) {
      _auth?.cancelAuthentication(notify: false);
    }

    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  int _secondsUntil(DateTime? deadline) {
    if (deadline == null) {
      return 0;
    }

    return (deadline.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(0, 86400);
  }

  bool get _wrongServer =>
      _serverChanged ||
      (widget.isLink && kIsWeb && _auth?.serverKey != '${PapyrusApiConfig.fromEnvironment().apiBaseUri}');

  Future<void> _verify() async {
    if (_busy || _wrongServer || _token == null) {
      return;
    }

    if (_secondsUntil(_auth!.retryAt) > 0) {
      setState(() => _verificationFailed = true);
      return;
    }

    setState(() => _busy = true);
    final message = await _auth!.verifyEmail(_token!);

    if (!mounted || _wrongServer) {
      return;
    }

    setState(() {
      _busy = false;
      _verified = message != null;
      _verificationFailed = message == null;
      _message = message;
      _invalidLink = _auth!.errorCode == 'VERIFICATION_TOKEN_INVALID';

      if (_verified || _invalidLink) {
        _token = null;
      }
    });
  }

  bool get _needsEmail => _recipient == null;

  Future<void> _resend() async {
    if (_busy || _wrongServer || _secondsUntil(_auth!.resendAt) > 0 || _secondsUntil(_auth!.retryAt) > 0) {
      return;
    }

    if (_needsEmail && !validateAndFocusForm(_formKey.currentState!)) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final recipient = _email.text.trim();
    final message = await _auth!.resendVerification(recipient);

    if (!mounted || _wrongServer) {
      return;
    }

    setState(() {
      _busy = false;
      _message = message == null ? null : 'New link requested. Check your inbox.';

      if (message != null) {
        _recipient = recipient;
        _email.text = recipient;
        _invalidLink = false;
      }
    });
  }

  void _signIn() {
    _auth!.cancelAuthentication();
    context.go('/login');
  }

  Widget _buildDeliveryForm(AuthProvider auth, int remaining, int retry) {
    final theme = Theme.of(context);
    final needsEmail = _needsEmail;
    final blocked = _busy || remaining > 0 || retry > 0;
    final seconds = remaining > retry ? remaining : retry;
    final actionLabel = switch (seconds) {
      _ when _busy => 'Requesting link…',
      > 0 => 'Resend in ${seconds}s',
      _ => needsEmail ? 'Send verification link' : 'Resend email',
    };
    final heading = needsEmail ? 'Request a new link' : 'Check your email';
    const guidance = 'Enter your email to get a verification link.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(heading, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: Spacing.sm),
        if (needsEmail) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              guidance,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Form(
            key: _formKey,
            child: EmailInput(
              labelText: 'Email address',
              controller: _email,
              textInputAction: TextInputAction.done,
              onEditingComplete: _resend,
            ),
          ),
          const SizedBox(height: Spacing.md),
        ] else ...[
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Open the link sent to '),
                TextSpan(
                  text: _recipient!,
                  style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                ),
                const TextSpan(text: '. Check your spam folder if it hasn’t arrived.'),
              ],
            ),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (_message != null) ...[
            const SizedBox(height: Spacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _message!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
        if (auth.error != null &&
            auth.errorCode != 'VERIFICATION_TOKEN_INVALID' &&
            auth.errorCode != 'EMAIL_VERIFICATION_REQUIRED') ...[
          const SizedBox(height: Spacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(auth.error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        ],
        const SizedBox(height: Spacing.md),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(ComponentSizes.buttonHeightMobile),
            disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
          ),
          onPressed: blocked ? null : _resend,
          child: Text(actionLabel),
        ),
        const SizedBox(height: Spacing.sm),
        OutlinedButton(
          onPressed: _signIn,
          child: const Text('Back to sign in'),
        ),
        if (auth.hasOfflineAccount) ...[
          const SizedBox(height: Spacing.sm),
          OutlinedButton(
            onPressed: () {
              auth.cancelAuthentication();
              context.goNamed('LIBRARY');
            },
            child: const Text('Read downloaded books'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final remaining = _secondsUntil(auth.resendAt);
    final retry = _secondsUntil(auth.retryAt);
    final hasVerificationToken = widget.isLink && !_verified && !_invalidLink && !_wrongServer;
    final String heading;
    final String subtitle;

    if (_verified) {
      heading = 'Email verified';
      subtitle = 'You can now sign in to Papyrus.';
    } else if (hasVerificationToken) {
      heading = _verificationFailed && !_busy ? 'Verification failed' : 'Verifying your email';
      subtitle = _verificationFailed && !_busy ? 'Please try again.' : 'Please wait…';
    } else if (_invalidLink) {
      heading = 'Link unavailable';
      subtitle = 'This link has expired or is no longer valid.';
    } else {
      heading = 'Check your email';
      subtitle = 'Open the verification link in your email, then return here to sign in.';
    }

    const buttonSize = Size.fromHeight(ComponentSizes.buttonHeightMobile);

    final deliveryView = !_verified && !_invalidLink && !_wrongServer && !hasVerificationToken;
    final form = deliveryView
        ? _buildDeliveryForm(auth, remaining, retry)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_wrongServer)
                const Text(
                  'This link is for a different server. Open it in the Papyrus app for that server.',
                ),
              if (_message != null && !_verified) ...[
                Semantics(liveRegion: true, child: Text(_message!)),
                const SizedBox(height: Spacing.md),
              ],
              if (auth.error != null &&
                  !_verified &&
                  !_wrongServer &&
                  auth.errorCode != 'VERIFICATION_TOKEN_INVALID') ...[
                Semantics(
                  liveRegion: true,
                  child: Text(auth.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
                const SizedBox(height: Spacing.md),
              ],
              if (retry > 0 && !_invalidLink) ...[
                Text('Try again in ${retry}s.'),
                const SizedBox(height: Spacing.md),
              ],
              if (hasVerificationToken && _verificationFailed && !_busy) ...[
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: buttonSize),
                  autofocus: true,
                  onPressed: _busy || retry > 0 ? null : _verify,
                  child: const Text('Try again'),
                ),
                const SizedBox(height: Spacing.md),
              ],
              if (hasVerificationToken)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: buttonSize),
                  onPressed: _signIn,
                  child: const Text('Back to sign in'),
                )
              else
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: buttonSize),
                  onPressed: _signIn,
                  child: Text(_verified ? 'Sign in' : 'Back to sign in'),
                ),
              if (!_invalidLink) ...[
                const SizedBox(height: Spacing.sm),
                OutlinedButton(onPressed: () => navigateToOffline(context), child: const Text('Continue offline')),
              ],
              if (auth.hasOfflineAccount && !_invalidLink) ...[
                const SizedBox(height: Spacing.sm),
                OutlinedButton(
                  onPressed: () {
                    auth.cancelAuthentication();
                    context.goNamed('LIBRARY');
                  },
                  child: const Text('Read downloaded books'),
                ),
              ],
            ],
          );

    final theme = Theme.of(context);
    final buttonShape = theme.filledButtonTheme.style?.shape ?? const WidgetStatePropertyAll(StadiumBorder());

    return OutlinedButtonTheme(
      data: OutlinedButtonThemeData(
        style: (theme.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(shape: buttonShape),
      ),
      child: ResponsiveBuilder(
        mobile: (context) => MobileAuthLayout(
          heading: heading,
          headingIcon: _verified ? Icons.check_circle_outline : null,
          subtitle: subtitle,
          showHeader: !deliveryView,
          announceSubtitle: true,
          headerBottomSpacing: Spacing.md,
          form: form,
          footer: const [],
        ),
        desktop: (context) => DesktopAuthLayout(
          heading: heading,
          headingIcon: _verified ? Icons.check_circle_outline : null,
          subtitle: subtitle,
          showHeader: !deliveryView,
          announceSubtitle: true,
          headerBottomSpacing: Spacing.md,
          form: form,
          footer: const [],
        ),
      ),
    );
  }
}
