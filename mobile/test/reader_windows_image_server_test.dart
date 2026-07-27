import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/features/reader/widgets/reader_windows_image_server_io.dart';

void main() {
  test(
    'Windows reader image server serves registered resources locally',
    () async {
      final server = await createWindowsReaderImageServer();
      addTearDown(() => server?.dispose());
      final expected = Uint8List.fromList([1, 2, 3, 4]);
      server!.put('sample.jpg', 'image/jpeg', expected);

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse(server.urlFor('sample.jpg')),
      );
      final response = await request.close();
      final actual = await response.fold<List<int>>(
        [],
        (all, bytes) => all..addAll(bytes),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'image/jpeg');
      expect(actual, expected);
    },
  );
}
