import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/services/api_client.dart';

void main() {
  group('ApiException.userFacingMessage', () {
    test('keeps the normalized API message', () {
      expect(
        ApiException.userFacingMessage(const ApiException('用户名或密码不正确，请重试。')),
        '用户名或密码不正确，请重试。',
      );
    });

    test('hides unexpected implementation errors', () {
      expect(
        ApiException.userFacingMessage(
          StateError('socket implementation detail'),
          fallback: '操作失败，请稍后重试。',
        ),
        '操作失败，请稍后重试。',
      );
    });
  });
}
