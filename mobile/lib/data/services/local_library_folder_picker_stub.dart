import 'dart:typed_data';

import 'local_library_folder_models.dart';

class LocalLibraryFolderPicker implements LocalLibraryFileReader {
  Future<PickedLocalLibraryFolder?> pickFolder() async {
    throw const LocalFolderPickerException('当前平台不支持选择本地目录');
  }

  @override
  Future<Uint8List> readFile(LocalLibraryFileSummary file) async {
    throw const LocalFolderPickerException('当前平台无法读取本地目录文件');
  }
}
