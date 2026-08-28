import 'package:flutter_test/flutter_test.dart';
import 'package:qingyue/data/services/session_storage.dart';

void main() {
  test('remembered login credentials round-trip without losing characters', () {
    const credentials = LoginCredentials(
      username: 'reader@example.com',
      password: '复杂 password! 123',
    );

    final restored = LoginCredentials.fromJson(credentials.toJson());

    expect(restored.username, credentials.username);
    expect(restored.password, credentials.password);
  });
}
