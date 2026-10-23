import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutLinks {
  static final repository = Uri.https('github.com', '/PapyrusReader/client');
  static final issues = Uri.https('github.com', '/PapyrusReader/client/issues');
  static final releases = Uri.https('github.com', '/PapyrusReader/client/releases');

  static Uri release(PackageInfo info) {
    if (info.version.isEmpty || info.buildNumber.isEmpty) {
      return releases;
    }

    return repository.replace(
      pathSegments: ['PapyrusReader', 'client', 'releases', 'tag', 'v${info.version}+${info.buildNumber}'],
    );
  }

  static String versionLabel(PackageInfo info) =>
      info.buildNumber.isEmpty ? info.version : '${info.version} (${info.buildNumber})';

  static Future<void> open(BuildContext context, Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // The browser can reject the launch even when the platform supports HTTPS.
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $uri. Please try again.')),
      );
    }
  }
}
