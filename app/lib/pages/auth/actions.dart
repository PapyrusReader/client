import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:provider/provider.dart';

void navigateToLogin(BuildContext context) {
  context.push('/login');
}

void navigateToRegister(BuildContext context) {
  context.push('/register');
}

void navigateToOffline(BuildContext context) {
  context.read<AuthProvider>().setOfflineMode(true);
  context.goNamed('LIBRARY');
}
