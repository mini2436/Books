import 'dart:typed_data';

abstract interface class BackupUploadFile {
  String get name;

  int get size;

  String? get path;

  Uint8List? get bytes;
}

class NativeBackupUploadResponse {
  const NativeBackupUploadResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
}
