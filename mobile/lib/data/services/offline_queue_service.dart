import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/sync_models.dart';

class OfflineQueueService {
  static const String _webStorageKey = 'private_reader_pending_operations';

  Future<Database> get _database async {
    _databaseFuture ??= _open();
    return _databaseFuture!;
  }

  Future<Database>? _databaseFuture;
  Future<void> _webOperation = Future<void>.value();

  Future<void> enqueue(PendingOperation operation) async {
    if (kIsWeb) {
      await _withWebStorage((operations) {
        operations.removeWhere((item) => item.id == operation.id);
        operations.add(operation);
        operations.sort(
          (left, right) => left.createdAt.compareTo(right.createdAt),
        );
        return operations;
      });
      return;
    }
    final db = await _database;
    await db.insert(
      'pending_operations',
      operation.toDatabaseRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PendingOperation>> loadPending() async {
    if (kIsWeb) {
      return _readWebOperations();
    }
    final db = await _database;
    final rows = await db.query(
      'pending_operations',
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingOperation.fromDatabaseRow).toList();
  }

  Future<int> pendingCount() async {
    if (kIsWeb) {
      return (await _readWebOperations()).length;
    }
    final db = await _database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM pending_operations'),
        ) ??
        0;
  }

  Future<void> deleteByIds(List<String> ids) async {
    if (ids.isEmpty) {
      return;
    }

    if (kIsWeb) {
      final deletedIds = ids.toSet();
      await _withWebStorage((operations) {
        operations.removeWhere((item) => deletedIds.contains(item.id));
        return operations;
      });
      return;
    }

    final db = await _database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      'pending_operations',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<Database> _open() async {
    final path = await _databasePath();
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pending_operations (
            id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<String> _databasePath() async {
    if (_usesFfiDatabase) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final supportDirectory = await getApplicationSupportDirectory();
      return p.join(supportDirectory.path, 'private_reader_mobile.db');
    }
    return p.join(await getDatabasesPath(), 'private_reader_mobile.db');
  }

  bool get _usesFfiDatabase =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<List<PendingOperation>> _readWebOperations() {
    return _serializeWebOperation(() async {
      final preferences = await SharedPreferences.getInstance();
      return _decodeWebOperations(preferences.getString(_webStorageKey));
    });
  }

  Future<void> _withWebStorage(
    List<PendingOperation> Function(List<PendingOperation> operations) update,
  ) {
    return _serializeWebOperation(() async {
      final preferences = await SharedPreferences.getInstance();
      final operations = _decodeWebOperations(
        preferences.getString(_webStorageKey),
      );
      final updated = update(operations);
      await preferences.setString(
        _webStorageKey,
        jsonEncode(updated.map((item) => item.toDatabaseRow()).toList()),
      );
    });
  }

  Future<T> _serializeWebOperation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _webOperation = _webOperation.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @visibleForTesting
  static List<PendingOperation> decodeWebOperations(String? raw) =>
      _decodeWebOperations(raw);

  static List<PendingOperation> _decodeWebOperations(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <PendingOperation>[];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (row) => PendingOperation.fromDatabaseRow(
              Map<String, Object?>.from(row as Map),
            ),
          )
          .toList()
        ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    } catch (_) {
      return <PendingOperation>[];
    }
  }
}
