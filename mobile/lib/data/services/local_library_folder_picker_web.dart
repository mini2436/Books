import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:web/web.dart' as web;

import 'local_library_folder_models.dart';

class LocalLibraryFolderPicker implements LocalLibraryFileReader {
  final Map<String, web.File> _selectedFiles = {};

  Future<PickedLocalLibraryFolder?> pickFolder() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..multiple = true
      ..accept = supportedLibraryExtensions.join(',');
    input.setAttribute('webkitdirectory', '');
    input.style.display = 'none';
    web.document.body?.append(input);

    final completer = Completer<PickedLocalLibraryFolder?>();
    void finish(web.Event _) {
      final fileList = input.files;
      if (fileList == null || fileList.length == 0) {
        completer.complete(null);
        input.remove();
        return;
      }
      _selectedFiles.clear();
      final summaries = <LocalLibraryFileSummary>[];
      String? folderName;
      for (var index = 0; index < fileList.length; index++) {
        final file = fileList.item(index);
        if (file == null) continue;
        final browserPath = file.webkitRelativePath.replaceAll('\\', '/');
        final relativeParts = browserPath.split('/');
        folderName ??= relativeParts.length > 1 ? relativeParts.first : '所选目录';
        final relativePath = relativeParts.length > 1
            ? relativeParts.skip(1).join('/')
            : file.name;
        if (!supportedLibraryExtensions.contains(
          path.extension(file.name).toLowerCase(),
        )) {
          continue;
        }
        final handle = '$index:$browserPath';
        _selectedFiles[handle] = file;
        summaries.add(
          LocalLibraryFileSummary(
            handle: handle,
            relativePath: relativePath,
            fileName: file.name,
            sizeBytes: file.size,
            lastModifiedMillis: file.lastModified,
          ),
        );
      }
      summaries.sort(
        (left, right) => left.relativePath.compareTo(right.relativePath),
      );
      completer.complete(
        PickedLocalLibraryFolder(
          displayName: folderName ?? '所选目录',
          displayPath: folderName ?? '所选目录',
          files: summaries,
        ),
      );
      input.remove();
    }

    void cancel(web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
      input.remove();
    }

    input.addEventListener('change', finish.toJS);
    input.addEventListener('cancel', cancel.toJS);
    input.click();
    return completer.future;
  }

  @override
  Future<Uint8List> readFileChunk(
    LocalLibraryFileSummary file, {
    required int offsetBytes,
    required int lengthBytes,
  }) async {
    final browserFile = _selectedFiles[file.handle];
    if (browserFile == null) {
      throw const LocalFolderPickerException('浏览器目录授权已失效，请重新选择目录');
    }
    final endBytes = offsetBytes + lengthBytes;
    if (offsetBytes < 0 || lengthBytes <= 0 || endBytes > browserFile.size) {
      throw const LocalFolderPickerException('读取的文件分块范围无效，请重新选择目录');
    }
    final buffer = await browserFile
        .slice(offsetBytes, endBytes)
        .arrayBuffer()
        .toDart;
    return buffer.toDart.asUint8List();
  }
}
