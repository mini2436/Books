import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'backup_upload_file.dart';
import 'backup_upload_picker_web.dart';

bool supportsNativeBackupUpload(BackupUploadFile file) =>
    file is WebBackupUploadFile;

Future<NativeBackupUploadResponse> uploadBackupWithNativeMultipart({
  required String baseUrl,
  required String accessToken,
  required String endpoint,
  required BackupUploadFile file,
  String? operationId,
  String? requestJson,
  void Function(int sent, int total)? onSendProgress,
}) {
  if (file is! WebBackupUploadFile) {
    throw ArgumentError('Web backup upload requires a browser File object');
  }

  final normalizedBaseUrl = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  var uri = Uri.parse('$normalizedBaseUrl$endpoint');
  if (operationId != null) {
    uri = uri.replace(queryParameters: {'operationId': operationId});
  }

  final xhr = web.XMLHttpRequest();
  final completer = Completer<NativeBackupUploadResponse>();
  xhr.open('POST', uri.toString());
  xhr.setRequestHeader('Authorization', 'Bearer $accessToken');
  xhr.setRequestHeader('Accept', 'application/json');

  void completeError(String message) {
    if (!completer.isCompleted) {
      completer.completeError(StateError(message));
    }
  }

  xhr.onLoad.first.then((_) {
    if (!completer.isCompleted) {
      completer.complete(
        NativeBackupUploadResponse(
          statusCode: xhr.status,
          body: xhr.responseText,
        ),
      );
    }
  });
  xhr.onError.first.then((_) => completeError('浏览器上传备份文件失败'));
  final abortListener = ((web.Event _) {
    completeError('备份文件上传已取消');
  }).toJS;
  final timeoutListener = ((web.Event _) {
    completeError('备份文件上传超时');
  }).toJS;
  xhr.addEventListener('abort', abortListener);
  xhr.addEventListener('timeout', timeoutListener);
  if (onSendProgress != null) {
    final progressListener = ((web.ProgressEvent event) {
      onSendProgress(event.loaded, event.lengthComputable ? event.total : 0);
    }).toJS;
    xhr.upload.addEventListener('progress', progressListener);
  }

  final formData = web.FormData();
  formData.append('file', file.file, file.name);
  if (requestJson != null) {
    final requestBlob = web.Blob(
      <JSAny>[requestJson.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    );
    formData.append('request', requestBlob, 'request.json');
  }
  xhr.send(formData);
  return completer.future;
}
