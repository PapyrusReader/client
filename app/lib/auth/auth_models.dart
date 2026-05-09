enum AuthStatus { bootstrapping, signedOut, authenticating, signedIn, refreshing, authError }

class PapyrusUser {
  final String userId;
  final String? email;
  final String displayName;
  final String? avatarUrl;
  final bool emailVerified;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  const PapyrusUser({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.avatarUrl,
    required this.emailVerified,
    required this.createdAt,
    required this.lastLoginAt,
  });

  factory PapyrusUser.fromJson(Map<String, dynamic> json) {
    return PapyrusUser(
      userId: json['user_id'] as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String? ?? 'Papyrus User',
      avatarUrl: json['avatar_url'] as String?,
      emailVerified: json['email_verified'] as bool? ?? false,
      createdAt: _parseDateTime(json['created_at']),
      lastLoginAt: _parseDateTime(json['last_login_at']),
    );
  }
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final PapyrusUser user;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresIn: json['expires_in'] as int,
      user: PapyrusUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class PowerSyncToken {
  final String token;
  final int expiresIn;

  const PowerSyncToken({required this.token, required this.expiresIn});

  factory PowerSyncToken.fromJson(Map<String, dynamic> json) {
    return PowerSyncToken(token: json['token'] as String, expiresIn: json['expires_in'] as int);
  }
}

DateTime? _parseDateTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }

  return DateTime.tryParse(value);
}
