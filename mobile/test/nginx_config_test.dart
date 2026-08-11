import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Docker Web proxy accepts and streams large backup uploads', () async {
    final configFile = File('nginx.conf');
    expect(await configFile.exists(), isTrue);

    final config = await configFile.readAsString();
    expect(config, contains(RegExp(r'client_max_body_size\s+1100m;')));
    expect(config, contains(RegExp(r'client_body_timeout\s+1h;')));
    expect(config, contains(RegExp(r'proxy_request_buffering\s+off;')));
    expect(config, contains(RegExp(r'proxy_send_timeout\s+1h;')));
    expect(config, contains(RegExp(r'proxy_read_timeout\s+1h;')));
  });
}
