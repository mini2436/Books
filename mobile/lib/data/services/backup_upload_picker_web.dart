import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'backup_upload_file.dart';

Future<BackupUploadFile?> pickBackupUploadFile() {
  final completer = Completer<BackupUploadFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.zip,application/zip'
    ..multiple = false
    ..style.display = 'none';
  web.document.body?.appendChild(input);

  StreamSubscription<web.Event>? changeSubscription;
  late final JSFunction focusListener;
  var completed = false;

  Future<void> finish(BackupUploadFile? file) async {
    if (completed) return;
    completed = true;
    await changeSubscription?.cancel();
    web.window.removeEventListener('focus', focusListener);
    input.remove();
    completer.complete(file);
  }

  changeSubscription = input.onChange.listen((_) {
    final file = input.files?.item(0);
    finish(file == null ? null : WebBackupUploadFile(file));
  });
  focusListener = ((web.Event _) {
    Future<void>.delayed(const Duration(milliseconds: 800), () async {
      if (!completed && (input.files?.length ?? 0) == 0) {
        await finish(null);
      }
    });
  }).toJS;
  web.window.addEventListener('focus', focusListener);

  input.click();
  return completer.future;
}

class WebBackupUploadFile implements BackupUploadFile {
  const WebBackupUploadFile(this.file);

  final web.File file;

  @override
  String get name => file.name;

  @override
  int get size => file.size;

  @override
  String? get path => null;

  @override
  Uint8List? get bytes => null;
}
