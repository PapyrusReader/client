import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:provider/provider.dart';

class OfflineModeLink extends StatelessWidget {
  final bool center;

  const OfflineModeLink({super.key, required this.center});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.center,
      child: TextButton(
        onPressed: () {
          context.read<AuthProvider>().setOfflineMode(true);
          context.goNamed('LIBRARY');
        },
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          textStyle: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text('Continue offline'), Icon(Icons.arrow_right_alt)],
        ),
      ),
    );
  }
}
