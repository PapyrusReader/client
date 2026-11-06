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
      _email.text = auth.pendingVerification?.email ?? '';

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

  Future<void> _resend() async {
    if (_busy || _wrongServer || _secondsUntil(_auth!.resendAt) > 0 || _secondsUntil(_auth!.retryAt) > 0) {
      return;
    }

    if (!validateAndFocusForm(_formKey.currentState!)) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final message = await _auth!.resendVerification(_email.text.trim());

    if (!mounted || _wrongServer) {
      return;
    }

    setState(() {
      _busy = false;
      _message = message == null ? null : 'Check your inbox and spam folder for a new link. It may take a few minutes.';
    });
  }

  void _signIn() {
    _auth!.cancelAuthentication();
    context.go('/login');
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
      heading = 'Request a new link';
      subtitle = 'This link cannot be used. Request a new one, or sign in if you have already verified your email.';
    } else {
      heading = 'Check your email';
      subtitle = 'Open the verification link in your email, then return here to sign in.';
    }

    final resendLabel = switch (remaining) {
      _ when _busy => 'Requesting link…',
      > 0 => 'Resend in ${remaining}s',
      _ => 'Resend verification email',
    };
    const buttonSize = Size.fromHeight(ComponentSizes.buttonHeightMobile);

    final form = Column(
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
        if (auth.error != null && !_verified && !_wrongServer && auth.errorCode != 'VERIFICATION_TOKEN_INVALID') ...[
          Semantics(
            liveRegion: true,
            child: Text(auth.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          const SizedBox(height: Spacing.md),
        ],
        if (retry > 0) ...[
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
        if (!_verified && !_wrongServer && !hasVerificationToken) ...[
          const SizedBox(height: Spacing.md),
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
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: buttonSize),
            onPressed: _busy || remaining > 0 || retry > 0 ? null : _resend,
            child: Text(resendLabel),
          ),
          const SizedBox(height: Spacing.lg),
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
        const SizedBox(height: Spacing.sm),
        TextButton(onPressed: () => navigateToOffline(context), child: const Text('Continue offline')),
        if (auth.hasOfflineAccount)
          TextButton(
            onPressed: () {
              auth.cancelAuthentication();
              context.goNamed('LIBRARY');
            },
            child: const Text('Read downloaded books'),
          ),
      ],
    );

    return ResponsiveBuilder(
      mobile: (context) =>
          MobileAuthLayout(heading: heading, subtitle: subtitle, announceSubtitle: true, form: form, footer: const []),
      desktop: (context) =>
          DesktopAuthLayout(heading: heading, subtitle: subtitle, announceSubtitle: true, form: form, footer: const []),
    );
  }
}
