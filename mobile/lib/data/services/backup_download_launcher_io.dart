import 'dart:io';

import 'package:flutter/services.dart';

const _backupDownloadChannel = MethodChannel(
  'com.privatereader.private_reader_mobile/backup_downloads',
);

Future<void> startSystemBackupDownload(String url, String fileName) async {
  if (!Platform.isAndroid) {
    throw UnsupportedError('The system downloader is only used on Android');
  }
  await _backupDownloadChannel.invokeMethod<int>('enqueue', {
    'url': url,
    'fileName': fileName,
  });
}
