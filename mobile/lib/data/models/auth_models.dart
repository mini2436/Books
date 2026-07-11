import 'user_role.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.hasAvatar,
    required this.avatarVersion,
  });

  final int id;
  final String username;
  final String? displayName;
  final String role;
  final bool hasAvatar;
  final String? avatarVersion;

  String get displayLabel {
    final normalized = displayName?.trim();
    return normalized == null || normalized.isEmpty ? username : normalized;
  }

  UserRole get userRole => UserRole.fromValue(role);

  bool get canAccessAdmin => userRole.canAccessAdmin;

  bool get canManageAdminUsers => userRole.canManageAdminUsers;

  String get initials {
    final trimmed = displayLabel.trim();
    if (trimmed.isEmpty) {
      return 'PR';
    }
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String?,
      role: json['role'] as String? ?? UserRole.reader.value,
      hasAvatar: json['hasAvatar'] as bool? ?? false,
      avatarVersion: json['avatarVersion']?.toString(),
    );
  }

  AuthUser copyWith({
    String? displayName,
    bool clearDisplayName = false,
    bool? hasAvatar,
    String? avatarVersion,
  }) => AuthUser(
    id: id,
    username: username,
    displayName: clearDisplayName ? null : displayName ?? this.displayName,
    role: role,
    hasAvatar: hasAvatar ?? this.hasAvatar,
    avatarVersion: avatarVersion ?? this.avatarVersion,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'displayName': displayName,
    'role': role,
    'hasAvatar': hasAvatar,
    'avatarVersion': avatarVersion,
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
