import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_models.dart';

class SessionStorage {
  SessionStorage() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _sessionKey = 'private_reader_session';

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
}
