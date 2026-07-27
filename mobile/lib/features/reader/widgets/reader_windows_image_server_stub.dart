import 'dart:typed_data';

class WindowsReaderImageServer {
  const WindowsReaderImageServer();

  String urlFor(String fileName) => '';

  void put(String fileName, String mediaType, Uint8List bytes) {}

  Future<void> dispose() async {}
}

Future<WindowsReaderImageServer?> createWindowsReaderImageServer() async =>
    null;
