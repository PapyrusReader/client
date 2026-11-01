class UpdateRelease {
  final String tag;
  final String version;
  final int buildNumber;
  final Map<String, dynamic> assets;

  const UpdateRelease({required this.tag, required this.version, required this.buildNumber, required this.assets});

  factory UpdateRelease.fromJson(Map<String, dynamic> json) {
    final tag = json['tag'];
    final version = json['version'];
    final build = json['build_number'];

    if (tag is! String ||
        version is! String ||
        build is! int ||
        build < 1 ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        tag != 'v$version+$build' ||
        json['assets'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid update release');
    }

    return UpdateRelease(
      tag: tag,
      version: version,
      buildNumber: build,
      assets: json['assets'] as Map<String, dynamic>,
    );
  }

  UpdateAsset asset(String key) {
    final suffix = switch (key) {
      'android_apk' => 'android-universal.apk',
      'installer' => 'windows-x64-setup.exe',
      'appimage' => 'linux-x64.AppImage',
      _ => throw const FormatException('Unsupported update package'),
    };

    final entry = assets[key];
    final name = 'papyrus-$tag-$suffix';

    if (entry is! Map ||
        entry['name'] != name ||
        entry['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry['sha256'] as String)) {
      throw const FormatException('Invalid update package');
    }

    return UpdateAsset(
      name: name,
      sha256: entry['sha256'] as String,
      uri: Uri.https('github.com', '/PapyrusReader/client/releases/download/$tag/$name'),
    );
  }
}

class UpdateAsset {
  final String name;
  final String sha256;
  final Uri uri;

  const UpdateAsset({required this.name, required this.sha256, required this.uri});
}

enum UpdateChannel { play, apk, windows, appImage, apt, web, manual }
