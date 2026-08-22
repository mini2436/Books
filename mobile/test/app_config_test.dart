import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/shared/config/app_config.dart';

void main() {
  test('the default server uses the local loopback address', () {
    expect(AppConfig.defaultApiBaseUrl, 'http://127.0.0.1:8080');
  });

  test('server addresses without a scheme keep the development API port', () {
    expect(
      AppConfig.normalizeBaseUrl('192.168.1.10'),
      'http://192.168.1.10:8080',
    );
  });

  test(
    'explicit HTTPS server addresses keep their scheme and standard port',
    () {
      expect(
        AppConfig.normalizeBaseUrl('https://qingyue.my-home.uno'),
        'https://qingyue.my-home.uno',
      );
    },
  );

  test('explicit server paths and custom ports are preserved', () {
    expect(
      AppConfig.normalizeAddress(
        'https://reader.example.com:9443/private-reader-api',
      ),
      'https://reader.example.com:9443/private-reader-api',
    );
  });
}
