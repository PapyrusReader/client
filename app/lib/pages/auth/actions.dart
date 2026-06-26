import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:provider/provider.dart';

void navigateToLogin(BuildContext context) {
  context.go('/login');
}

void navigateToRegister(BuildContext context) {
  context.go('/register');
}

void navigateToOffline(BuildContext context) {
  context.read<AuthProvider>().setOfflineMode(true);
  context.goNamed('LIBRARY');
}
