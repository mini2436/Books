import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_models.dart';

class SessionStorage {
  SessionStorage() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _sessionKey = 'private_reader_session';
  static const String _loginCredentialsKey = 'qingyue_login_credentials';

  Future<Session?> readSession() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSession(Session session) async {
    await _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));
  }

  Future<void> clear() => _storage.delete(key: _sessionKey);

  Future<LoginCredentials?> readLoginCredentials() async {
    final raw = await _storage.read(key: _loginCredentialsKey);
    if (raw == null || raw.isEmpty) return null;
    return LoginCredentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveLoginCredentials(LoginCredentials credentials) =>
      _storage.write(
        key: _loginCredentialsKey,
        value: jsonEncode(credentials.toJson()),
      );

  Future<void> clearLoginCredentials() =>
      _storage.delete(key: _loginCredentialsKey);
}

class LoginCredentials {
  const LoginCredentials({required this.username, required this.password});

  final String username;
  final String password;

  factory LoginCredentials.fromJson(Map<String, dynamic> json) =>
      LoginCredentials(
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'username': username, 'password': password};
}
