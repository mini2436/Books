import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

import 'local_library_folder_models.dart';

class LocalLibraryFolderPicker implements LocalLibraryFileReader {
  Future<PickedLocalLibraryFolder?> pickFolder() async {
    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择需要手动扫描的图书目录',
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) return null;

    final directory = Directory(selectedPath);
    if (!await directory.exists()) {
      throw const LocalFolderPickerException('所选目录当前不可访问，请重新选择');
    }
    final files = <LocalLibraryFileSummary>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File ||
          !supportedLibraryExtensions.contains(
            path.extension(entity.path).toLowerCase(),
          )) {
        continue;
      }
      final stat = await entity.stat();
      files.add(
        LocalLibraryFileSummary(
          handle: entity.path,
          relativePath: path
              .relative(entity.path, from: directory.path)
              .replaceAll('\\', '/'),
          fileName: path.basename(entity.path),
          sizeBytes: stat.size,
          lastModifiedMillis: stat.modified.millisecondsSinceEpoch,
        ),
      );
    }
    files.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    return PickedLocalLibraryFolder(
      displayName: path.basename(directory.path),
      displayPath: directory.path,
      files: files,
    );
  }

  @override
  Future<Uint8List> readFile(LocalLibraryFileSummary file) =>
      File(file.handle).readAsBytes();
}
