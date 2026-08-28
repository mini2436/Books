import 'package:flutter_test/flutter_test.dart';
import 'package:qingyue/data/services/api_client.dart';

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

  group('ApiException authentication classification', () {
    test('refreshes only for unauthorized responses', () {
      expect(
        const ApiException('expired', statusCode: 401).isAuthenticationFailure,
        isTrue,
      );
      expect(
        const ApiException(
          'forbidden',
          statusCode: 403,
        ).isAuthenticationFailure,
        isFalse,
      );
    });
  });
}
