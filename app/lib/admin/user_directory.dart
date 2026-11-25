class UserDirectory {
  const UserDirectory({
    required this.users,
    required this.quotaBytes,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<DirectoryUser> users;
  final int quotaBytes;
  final int page;
  final int limit;
  final int total;

  int get offset => (page - 1) * limit;
  int get lastPage => total == 0 ? 1 : (total + limit - 1) ~/ limit;

  factory UserDirectory.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>;

    return UserDirectory(
      users: (json['users'] as List).cast<Map<String, dynamic>>().map(DirectoryUser.fromJson).toList(growable: false),
      quotaBytes: json['quota_bytes'] as int,
      page: pagination['page'] as int,
      limit: pagination['limit'] as int,
      total: pagination['total'] as int,
    );
  }
}

class DirectoryUser {
  const DirectoryUser({
    required this.id,
    required this.name,
    required this.email,
    required this.isAdmin,
    required this.status,
    required this.joined,
    required this.lastSignIn,
    required this.bookCount,
    required this.usedBytes,
  });

  final String id;
  final String name;
  final String? email;
  final bool isAdmin;
  final String status;
  final DateTime joined;
  final DateTime? lastSignIn;
  final int bookCount;
  final int usedBytes;

  int? get averageBytes => bookCount == 0 ? null : (usedBytes / bookCount).round();

  factory DirectoryUser.fromJson(Map<String, dynamic> json) {
    final signIn = json['last_sign_in_at'] as String?;

    return DirectoryUser(
      id: json['user_id'] as String,
      name: json['display_name'] as String,
      email: json['email'] as String?,
      isAdmin: json['role'] == 'admin',
      status: switch (json['status']) {
        'active' => 'Active',
        'unverified' => 'Awaiting verification',
        'disabled' => 'Disabled',
        'pending_deletion' => 'Pending deletion',
        _ => 'Unknown',
      },
      joined: DateTime.parse(json['created_at'] as String).toLocal(),
      lastSignIn: signIn == null ? null : DateTime.parse(signIn).toLocal(),
      bookCount: json['book_count'] as int,
      usedBytes: json['used_bytes'] as int,
    );
  }
}
