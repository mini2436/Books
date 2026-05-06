import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

class FlutterSecureStorageWindows extends FlutterSecureStoragePlatform {
  FlutterSecureStorageWindows() : _storage = _DpapiJsonFileMapStorage();

  final _DpapiJsonFileMapStorage _storage;

  static void registerWith() {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWindows();
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    final map = await _storage.load();
    return map.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    final map = await _storage.load();
    if (!map.containsKey(key)) {
      return;
    }
    map.remove(key);
    await _storage.save(map);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) {
    return _storage.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    final map = await _storage.load();
    return map[key];
  }

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) {
    return _storage.load();
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    final map = await _storage.load();
    map[key] = value;
    await _storage.save(map);
  }
}

class _DpapiJsonFileMapStorage {
  static const String _encryptedJsonFileName = 'flutter_secure_storage.dat';

  Future<String> _getJsonFilePath() async {
    final appDataDirectory = await getApplicationSupportDirectory();
    return path.canonicalize(
      path.join(appDataDirectory.path, _encryptedJsonFileName),
    );
  }

  Future<Map<String, String>> load() async {
    final file = File(await _getJsonFilePath());
    if (!file.existsSync()) {
      return {};
    }

    late final Uint8List encryptedText;
    try {
      encryptedText = await file.readAsBytes();
    } on FileSystemException catch (error) {
      debugPrint('Secure storage file disappeared while reading: $error');
      return {};
    }

    late final String plainText;
    try {
      plainText = using((alloc) {
        final pEncryptedText = alloc<Uint8>(encryptedText.length);
        pEncryptedText
            .asTypedList(encryptedText.length)
            .setAll(0, encryptedText);

        final encryptedTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(
          sizeOf<CRYPT_INTEGER_BLOB>(),
        );
        encryptedTextBlob.ref
          ..cbData = encryptedText.length
          ..pbData = pEncryptedText;

        final plainTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(
          sizeOf<CRYPT_INTEGER_BLOB>(),
        );
        if (CryptUnprotectData(
              encryptedTextBlob,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              0,
              plainTextBlob,
            ) ==
            0) {
          throw WindowsException(
            GetLastError(),
            message: 'Failure on CryptUnprotectData()',
          );
        }

        if (plainTextBlob.ref.pbData.address == NULL) {
          throw WindowsException(
            ERROR_OUTOFMEMORY,
            message: 'Failure on CryptUnprotectData()',
          );
        }

        try {
          return utf8.decoder.convert(
            plainTextBlob.ref.pbData.asTypedList(plainTextBlob.ref.cbData),
          );
        } finally {
          if (plainTextBlob.ref.pbData.address != NULL &&
              LocalFree(plainTextBlob.ref.pbData).address != NULL) {
            debugPrint(
              'Secure storage LocalFree failed: '
              '0x${GetLastError().toHexString(32)}',
            );
          }
        }
      });
    } on FormatException catch (error) {
      await _deleteCorruptFile(file, 'decrypt', error);
      return {};
    } on WindowsException catch (error) {
      await _deleteCorruptFile(file, 'decrypt', error);
      return {};
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(plainText);
    } on FormatException catch (error) {
      await _deleteCorruptFile(file, 'parse', error);
      return {};
    }

    if (decoded is! Map) {
      await _deleteCorruptFile(file, 'parse', 'JSON root is not an object');
      return {};
    }

    return {
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  Future<void> save(Map<String, String> data) async {
    final file = File(await _getJsonFilePath());
    final plainText = utf8.encode(jsonEncode(data));

    await using<Future<void>>((alloc) async {
      final pPlainText = alloc<Uint8>(plainText.length);
      pPlainText.asTypedList(plainText.length).setAll(0, plainText);

      final plainTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(
        sizeOf<CRYPT_INTEGER_BLOB>(),
      );
      plainTextBlob.ref
        ..cbData = plainText.length
        ..pbData = pPlainText;

      final encryptedTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(
        sizeOf<CRYPT_INTEGER_BLOB>(),
      );
      if (CryptProtectData(
            plainTextBlob,
            nullptr,
            nullptr,
            nullptr,
            nullptr,
            0,
            encryptedTextBlob,
          ) ==
          0) {
        throw WindowsException(
          GetLastError(),
          message: 'Failure on CryptProtectData()',
        );
      }

      if (encryptedTextBlob.ref.pbData.address == NULL) {
        throw WindowsException(
          ERROR_OUTOFMEMORY,
          message: 'Failure on CryptProtectData()',
        );
      }

      try {
        final encryptedText = encryptedTextBlob.ref.pbData.asTypedList(
          encryptedTextBlob.ref.cbData,
        );
        await (await file.create(
          recursive: true,
        ))
            .writeAsBytes(encryptedText, flush: true);
      } finally {
        if (encryptedTextBlob.ref.pbData.address != NULL &&
            LocalFree(encryptedTextBlob.ref.pbData).address != NULL) {
          debugPrint(
            'Secure storage LocalFree failed: '
            '0x${GetLastError().toHexString(32)}',
          );
        }
      }
    });
  }

  Future<void> clear() async {
    final file = File(await _getJsonFilePath());
    if (!file.existsSync()) {
      return;
    }
    try {
      await file.delete();
    } on FileSystemException catch (error) {
      debugPrint('Secure storage file disappeared while deleting: $error');
    }
  }

  Future<void> _deleteCorruptFile(File file, String phase, Object error) async {
    debugPrint('Failed to $phase secure storage data: $error');
    try {
      await file.delete();
    } on FileSystemException {
      // If another process already removed it, the next load will recreate it.
    }
  }
}
