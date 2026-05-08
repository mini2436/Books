import 'user_role.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.role,
  });

  final int id;
  final String username;
  final String role;

  UserRole get userRole => UserRole.fromValue(role);

  bool get canAccessAdmin => userRole.canAccessAdmin;

  bool get canManageAdminUsers => userRole.canManageAdminUsers;

  String get initials {
    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      return 'PR';
    }
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String? ?? '',
      role: json['role'] as String? ?? UserRole.reader.value,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'role': role,
  };
}

class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'user': user.toJson(),
  };
}
