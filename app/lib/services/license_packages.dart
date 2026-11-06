import 'package:flutter/foundation.dart';

typedef LicensePackages = Map<String, List<LicenseEntry>>;

Future<LicensePackages> loadLicensePackages() async {
  final packages = <String, List<LicenseEntry>>{};

  await for (final entry in LicenseRegistry.licenses) {
    for (final package in entry.packages) {
      (packages[package] ??= []).add(entry);
    }
  }

  return packages;
}
