import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/services/app_info_base_url_stub.dart'
    if (dart.library.js_interop) 'package:papyrus/services/app_info_base_url_web.dart';

// Use the document's base URL on web, including when opened on a nested route.
Future<PackageInfo> loadAppInfo() => PackageInfo.fromPlatform(baseUrl: appInfoBaseUrl);
