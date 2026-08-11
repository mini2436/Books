import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'backup_upload_file.dart';

Future<BackupUploadFile?> pickBackupUploadFile() async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: '选择轻阅备份',
    type: FileType.custom,
    allowedExtensions: const ['zip'],
    allowMultiple: false,
    lockParentWindow: true,
  );
  if (result == null || result.files.isEmpty) return null;
  return _IoBackupUploadFile(result.files.single);
}

class _IoBackupUploadFile implements BackupUploadFile {
  const _IoBackupUploadFile(this.file);

  final PlatformFile file;

  @override
  String get name => file.name;

  @override
  int get size => file.size;

  @override
  String? get path => file.path;

  @override
  Uint8List? get bytes => file.bytes;
}
