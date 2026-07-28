import 'dart:typed_data';

const supportedLibraryExtensions = <String>{
  '.txt',
  '.epub',
  '.pdf',
  '.cbz',
  '.fb2',
  '.mobi',
};

const localLibraryUploadChunkSizeBytes = 16 * 1024 * 1024;

class LocalLibraryFileSummary {
  const LocalLibraryFileSummary({
    required this.handle,
    required this.relativePath,
    required this.fileName,
    required this.sizeBytes,
    required this.lastModifiedMillis,
  });

  final String handle;
  final String relativePath;
  final String fileName;
  final int sizeBytes;
  final int lastModifiedMillis;

  Map<String, dynamic> toJson() => {
    'relativePath': relativePath,
    'sizeBytes': sizeBytes,
    'lastModifiedMillis': lastModifiedMillis,
  };
}

class PickedLocalLibraryFolder {
  const PickedLocalLibraryFolder({
    required this.displayName,
    required this.displayPath,
    required this.files,
  });

  final String displayName;
  final String displayPath;
  final List<LocalLibraryFileSummary> files;

  int get totalSizeBytes => files.fold(0, (sum, file) => sum + file.sizeBytes);
}

abstract interface class LocalLibraryFileReader {
  Future<Uint8List> readFileChunk(
    LocalLibraryFileSummary file, {
    required int offsetBytes,
    required int lengthBytes,
  });
}

class LocalFolderPickerException implements Exception {
  const LocalFolderPickerException(this.message);

  final String message;

  @override
  String toString() => message;
}
