import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/sync_models.dart';

class OfflineQueueService {
  Future<Database> get _database async {
    _databaseFuture ??= _open();
    return _databaseFuture!;
  }

  Future<Database>? _databaseFuture;

  Future<void> enqueue(PendingOperation operation) async {
    final db = await _database;
    await db.insert(
      'pending_operations',
      operation.toDatabaseRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PendingOperation>> loadPending() async {
    final db = await _database;
    final rows = await db.query(
      'pending_operations',
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingOperation.fromDatabaseRow).toList();
  }

  Future<int> pendingCount() async {
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

    final db = await _database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      'pending_operations',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'private_reader_mobile.db');
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
}
