import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/sync_models.dart';

class OfflineQueueService extends ChangeNotifier {
  OfflineQueueService({String? databasePathOverride})
    : _databasePathOverride = databasePathOverride;

  static const String _webStorageKey = 'private_reader_pending_operations';

  final String? _databasePathOverride;

  Future<Database> get _database async {
    _databaseFuture ??= _open();
    return _databaseFuture!;
  }

  Future<Database>? _databaseFuture;
  Future<void> _webOperation = Future<void>.value();

  @visibleForTesting
  Future<void> close() async {
    final database = await _databaseFuture;
    await database?.close();
    _databaseFuture = null;
  }

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
      notifyListeners();
      return;
    }
    final db = await _database;
    await db.insert(
      'pending_operations',
      operation.toDatabaseRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<List<PendingOperation>> loadPending({
    required String serverKey,
    required int userId,
  }) async {
    if (kIsWeb) {
      return (await _readWebOperations())
          .where((operation) {
            final belongsToScope =
                operation.serverKey == serverKey && operation.userId == userId;
            final isLegacy =
                operation.serverKey.isEmpty && operation.userId < 0;
            return belongsToScope || isLegacy;
          })
          .map((operation) {
            if (operation.serverKey.isNotEmpty || operation.userId >= 0) {
              return operation;
            }
            return PendingOperation(
              id: operation.id,
              serverKey: serverKey,
              userId: userId,
              entityType: operation.entityType,
              payload: operation.payload,
              createdAt: operation.createdAt,
            );
          })
          .toList();
    }
    final db = await _database;
    await db.update('pending_operations', {
      'server_key': serverKey,
      'user_id': userId,
    }, where: "server_key = '' AND user_id < 0");
    final rows = await db.query(
      'pending_operations',
      where: 'server_key = ? AND user_id = ?',
      whereArgs: [serverKey, userId],
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingOperation.fromDatabaseRow).toList();
  }

  Future<int> pendingCount({
    required String serverKey,
    required int userId,
  }) async {
    if (kIsWeb) {
      return (await loadPending(serverKey: serverKey, userId: userId)).length;
    }
    final db = await _database;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM pending_operations WHERE server_key = ? AND user_id = ?',
            [serverKey, userId],
          ),
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
      notifyListeners();
      return;
    }

    final db = await _database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      'pending_operations',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    notifyListeners();
  }

  Future<Database> _open() async {
    final path = await _databasePath();
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pending_operations (
            id TEXT PRIMARY KEY,
            server_key TEXT NOT NULL,
            user_id INTEGER NOT NULL,
            entity_type TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE pending_operations ADD COLUMN server_key TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            'ALTER TABLE pending_operations ADD COLUMN user_id INTEGER NOT NULL DEFAULT -1',
          );
        }
      },
    );
  }

  Future<String> _databasePath() async {
    if (_databasePathOverride != null) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      return _databasePathOverride;
    }
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
