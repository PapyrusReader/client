import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/themes/app_motion.dart';

bool usesBookBackGesture(BuildContext context) =>
    !kIsWeb && Theme.of(context).platform == TargetPlatform.iOS && !AppMotion.disabled(context);

Page<void> bookNavigationPage(BuildContext context, {required LocalKey key, required Widget child}) {
  if (usesBookBackGesture(context)) {
    return MaterialPage<void>(key: key, child: child);
  }

  return NoTransitionPage<void>(key: key, child: child);
}

/// Records which in-app URL preceded a browser entry without copying its query parameters.
class AppPageHistory extends PathUrlStrategy {
  static const _previous = 'papyrus.previous';
  String _fingerprint(String path) => sha256.convert(utf8.encode(path)).toString();

  @override
  void pushState(Object? state, String title, String url) {
    super.pushState(state is Map ? {...state, _previous: _fingerprint(getPath())} : state, title, url);
  }

  @override
  void replaceState(Object? state, String title, String url) {
    final previous = getState();
    super.replaceState(
      state is Map && previous is Map && previous.containsKey(_previous)
          ? {...state, _previous: previous[_previous]}
          : state,
      title,
      url,
    );
  }

  bool _canGoBackTo(Uri uri) {
    final state = getState();
    return state is Map && state[_previous] == _fingerprint(uri.toString());
  }
}

/// Use browser Back only when it leads to the same page as popping the app route.
bool _backInBrowser(BuildContext context) {
  final strategy = urlStrategy;

  if (strategy is! AppPageHistory) {
    return false;
  }

  final configuration = GoRouter.maybeOf(context)?.routerDelegate.currentConfiguration;
  final page = ModalRoute.of(context)?.settings;

  if (configuration == null || configuration.isEmpty || page is! Page || page.key != configuration.last.pageKey) {
    return false;
  }

  final previous = configuration.remove(configuration.last);

  if (previous.isEmpty) {
    return false;
  }

  final destination = switch (previous.last) {
    final ImperativeRouteMatch match => match.matches.uri,
    _ => previous.uri,
  };

  if (!strategy._canGoBackTo(destination)) {
    return false;
  }

  strategy.go(-1);
  return true;
}

void popAppPage(BuildContext context) {
  if (!_backInBrowser(context)) {
    context.pop();
  }
}

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key});

  @override
  Widget build(BuildContext context) => BackButton(
    onPressed: () {
      if (!_backInBrowser(context)) {
        Navigator.of(context).maybePop();
      }
    },
  );
}
