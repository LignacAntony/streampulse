import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class OfflineDatabase {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'streampulse_cache.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_playlists (
            playlist_id TEXT PRIMARY KEY,
            name        TEXT NOT NULL,
            enabled_at  TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_tracks (
            track_id    TEXT NOT NULL,
            playlist_id TEXT NOT NULL,
            title       TEXT NOT NULL,
            artist      TEXT,
            duration_s  INTEGER,
            position    INTEGER NOT NULL,
            file_path   TEXT,
            file_size   INTEGER DEFAULT 0,
            status      TEXT NOT NULL DEFAULT 'pending',
            PRIMARY KEY (track_id, playlist_id),
            FOREIGN KEY (playlist_id) REFERENCES offline_playlists(playlist_id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
