import 'backup_upload_file.dart';

bool supportsNativeBackupUpload(BackupUploadFile file) => false;

Future<NativeBackupUploadResponse> uploadBackupWithNativeMultipart({
  required String baseUrl,
  required String accessToken,
  required String endpoint,
  required BackupUploadFile file,
  String? operationId,
  String? requestJson,
  void Function(int sent, int total)? onSendProgress,
}) {
  throw UnsupportedError('Native browser backup upload is unavailable');
}
