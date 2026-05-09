import 'package:flutter/material.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:provider/provider.dart';

/// Greeting section for the dashboard displaying time-based greeting.
class DashboardGreeting extends StatelessWidget {
  /// Time-based greeting (e.g., "Good morning").
  final String greeting;

  /// Called when the notifications icon is tapped.
  final VoidCallback? onNotificationsTap;

  /// Whether to use desktop styling.
  final bool isDesktop;

  const DashboardGreeting({super.key, required this.greeting, this.onNotificationsTap, this.isDesktop = false});

  /// Returns the current user's first name, or "reader" as fallback.
  String _userName(BuildContext context) {
    final displayName = context.watch<AuthProvider>().user?.displayName ?? 'reader';
    return displayName.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final greetingStyle = isDesktop ? textTheme.headlineMedium : textTheme.titleLarge;

    return Padding(
      padding: isDesktop ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Row(
        children: [
          Expanded(child: Text('$greeting, ${_userName(context)}!', style: greetingStyle)),
          IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: onNotificationsTap),
        ],
      ),
    );
  }
}
