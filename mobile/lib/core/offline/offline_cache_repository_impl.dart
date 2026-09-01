import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/playlists/domain/entities/playlist_track.dart';
import 'entities/cached_track_status.dart';
import 'entities/offline_playlist_summary.dart';
import 'offline_cache_repository.dart';
import 'offline_database.dart';

class OfflineCacheRepositoryImpl implements OfflineCacheRepository {
  OfflineCacheRepositoryImpl(this._database);

  final OfflineDatabase _database;
  String? _cacheRoot;

  Future<String> _getCacheRoot() async {
    if (_cacheRoot != null) return _cacheRoot!;
    final dir = await getApplicationDocumentsDirectory();
    _cacheRoot = p.join(dir.path, 'streampulse_cache', 'tracks');
    await Directory(_cacheRoot!).create(recursive: true);
    return _cacheRoot!;
  }

  @override
  Future<Set<String>> offlinePlaylistIds() async {
    final db = await _database.database;
    final rows = await db.query('offline_playlists', columns: ['playlist_id']);
    return rows.map((r) => r['playlist_id'] as String).toSet();
  }

  @override
  Future<List<OfflinePlaylistSummary>> offlinePlaylists() async {
    final db = await _database.database;
    // Nombre de pistes par playlist via LEFT JOIN : une playlist téléchargée
    // vide (cas limite) reste listée avec un compteur à 0.
    final rows = await db.rawQuery('''
      SELECT p.playlist_id AS id,
             p.name        AS name,
             COUNT(t.track_id) AS track_count
      FROM offline_playlists p
      LEFT JOIN cached_tracks t ON t.playlist_id = p.playlist_id
      GROUP BY p.playlist_id, p.name, p.enabled_at
      ORDER BY p.enabled_at DESC
    ''');
    return rows
        .map((r) => OfflinePlaylistSummary(
              id: r['id'] as String,
              name: r['name'] as String,
              trackCount: (r['track_count'] as int?) ?? 0,
            ))
        .toList();
  }

  @override
  Future<bool> isOffline(String playlistId) async {
    final db = await _database.database;
    final rows = await db.query(
      'offline_playlists',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> enableOffline(
    String playlistId,
    String name,
    List<PlaylistTrack> tracks,
  ) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.insert('offline_playlists', {
        'playlist_id': playlistId,
        'name': name,
        'enabled_at': DateTime.now().toIso8601String(),
      });
      for (final track in tracks) {
        final existing = await txn.query(
          'cached_tracks',
          columns: ['status'],
          where: 'track_id = ? AND status = ?',
          whereArgs: [track.id, 'done'],
          limit: 1,
        );
        await txn.insert('cached_tracks', {
          'track_id': track.id,
          'playlist_id': playlistId,
          'title': track.title,
          'artist': track.artist,
          'duration_s': track.durationS,
          'position': track.position,
          'status': existing.isNotEmpty ? 'done' : 'pending',
          'file_path': existing.isNotEmpty
              ? '${track.id}.audio'
              : null,
        });
      }
    });
  }

  @override
  Future<void> disableOffline(String playlistId) async {
    final db = await _database.database;
    final tracks = await db.query(
      'cached_tracks',
      columns: ['track_id'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );

    await db.delete(
      'cached_tracks',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    await db.delete(
      'offline_playlists',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );

    final root = await _getCacheRoot();
    for (final row in tracks) {
      final trackId = row['track_id'] as String;
      final remaining = await db.query(
        'cached_tracks',
        columns: ['track_id'],
        where: 'track_id = ?',
        whereArgs: [trackId],
        limit: 1,
      );
      if (remaining.isEmpty) {
        final file = File(p.join(root, '$trackId.audio'));
        if (await file.exists()) await file.delete();
        final tmp = File(p.join(root, '$trackId.tmp'));
        if (await tmp.exists()) await tmp.delete();
      }
    }
  }

  @override
  Future<List<PlaylistTrack>> cachedTracks(String playlistId) async {
    final db = await _database.database;
    final rows = await db.query(
      'cached_tracks',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position ASC',
    );
    return rows
        .map((r) => PlaylistTrack(
              id: r['track_id'] as String,
              title: r['title'] as String,
              artist: r['artist'] as String?,
              durationS: r['duration_s'] as int?,
              position: r['position'] as int,
            ))
        .toList();
  }

  @override
  Future<List<CachedTrackStatus>> downloadStatuses(String playlistId) async {
    final db = await _database.database;
    final rows = await db.query(
      'cached_tracks',
      columns: ['track_id', 'status'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position ASC',
    );
    return rows
        .map((r) => CachedTrackStatus(
              trackId: r['track_id'] as String,
              status: _parseStatus(r['status'] as String),
              progress: (r['status'] as String) == 'done' ? 1.0 : 0.0,
            ))
        .toList();
  }

  @override
  Future<void> updateTrackStatus(
    String trackId,
    String playlistId, {
    required TrackCacheStatus status,
    String? filePath,
    int? fileSize,
  }) async {
    final db = await _database.database;
    final values = <String, Object?>{'status': status.name};
    if (filePath != null) values['file_path'] = filePath;
    if (fileSize != null) values['file_size'] = fileSize;

    await db.update(
      'cached_tracks',
      values,
      where: 'track_id = ? AND playlist_id = ?',
      whereArgs: [trackId, playlistId],
    );

    if (status == TrackCacheStatus.done && filePath != null) {
      await db.update(
        'cached_tracks',
        {'status': 'done', 'file_path': filePath},
        where: 'track_id = ? AND status != ?',
        whereArgs: [trackId, 'done'],
      );
    }
  }

  @override
  Future<String?> cachedFilePath(String trackId) async {
    final db = await _database.database;
    final rows = await db.query(
      'cached_tracks',
      columns: ['file_path'],
      where: 'track_id = ? AND status = ?',
      whereArgs: [trackId, 'done'],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['file_path'] == null) return null;
    final root = await _getCacheRoot();
    final path = p.join(root, rows.first['file_path'] as String);
    if (!await File(path).exists()) return null;
    return path;
  }

  @override
  Future<int> totalCacheSize() async {
    final root = await _getCacheRoot();
    final dir = Directory(root);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  @override
  Future<void> clearAll() async {
    final db = await _database.database;
    await db.delete('offline_playlists');
    final root = await _getCacheRoot();
    final dir = Directory(root);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
  }

  TrackCacheStatus _parseStatus(String s) => switch (s) {
        'downloading' => TrackCacheStatus.downloading,
        'done' => TrackCacheStatus.done,
        'error' => TrackCacheStatus.error,
        _ => TrackCacheStatus.pending,
      };
}
