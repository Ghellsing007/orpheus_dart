import 'package:uuid/uuid.dart';

import '../services/mongo_service.dart';

class UserRepository {
  UserRepository(this._mongo);

  final MongoService _mongo;
  static const _collection = 'users';
  static const recentLimit = 50;
  final _uuid = const Uuid();

  Future<Map<String, dynamic>> getUser(String userId) async {
    final coll = await _mongo.collection(_collection);
    final existing = await coll.findOne({'_id': userId});
    if (existing != null) return Map<String, dynamic>.from(existing);
    final doc = _emptyUser(userId);
    await coll.insert(doc);
    return doc;
  }

  Future<Map<String, dynamic>> _save(String userId, Map<String, dynamic> doc) async {
    final coll = await _mongo.collection(_collection);
    await coll.replaceOne({'_id': userId}, doc, upsert: true);
    return doc;
  }

  Map<String, dynamic> _emptyUser(String userId) => {
        '_id': userId,
        'likedSongs': <Map<String, dynamic>>[],
        'likedPlaylists': <Map<String, dynamic>>[],
        'recentlyPlayed': <Map<String, dynamic>>[],
        'customPlaylists': <Map<String, dynamic>>[],
        'playlistFolders': <Map<String, dynamic>>[],
        'youtubePlaylists': <String>[],
      };

  Future<Map<String, dynamic>> likeSong(
    String userId,
    Map<String, dynamic> song, {
    required bool add,
  }) async {
    final user = await getUser(userId);
    final liked = List<Map<String, dynamic>>.from(user['likedSongs'] ?? []);
    if (add) {
      if (!liked.any((s) => s['ytid'] == song['ytid'])) liked.add(song);
    } else {
      liked.removeWhere((s) => s['ytid'] == song['ytid']);
    }
    user['likedSongs'] = liked;
    return _save(userId, user);
  }

  Future<Map<String, dynamic>> likePlaylist(
    String userId,
    Map<String, dynamic> playlist, {
    required bool add,
  }) async {
    final user = await getUser(userId);
    final liked = List<Map<String, dynamic>>.from(user['likedPlaylists'] ?? []);
    if (add) {
      if (!liked.any((p) => p['ytid'] == playlist['ytid'])) liked.add(playlist);
    } else {
      liked.removeWhere((p) => p['ytid'] == playlist['ytid']);
    }
    user['likedPlaylists'] = liked;
    return _save(userId, user);
  }

  Future<Map<String, dynamic>> addRecentlyPlayed(
    String userId,
    Map<String, dynamic> song,
  ) async {
    final user = await getUser(userId);
    final recent = List<Map<String, dynamic>>.from(user['recentlyPlayed'] ?? []);
    recent.removeWhere((s) => s['ytid'] == song['ytid']);
    recent.insert(0, song);
    if (recent.length > recentLimit) {
      recent.removeRange(recentLimit, recent.length);
    }
    user['recentlyPlayed'] = recent;
    return _save(userId, user);
  }

  Future<Map<String, dynamic>> addUserPlaylistId(
    String userId,
    String playlistId,
  ) async {
    final user = await getUser(userId);
    final ids = List<String>.from(user['youtubePlaylists'] ?? []);
    if (!ids.contains(playlistId)) ids.add(playlistId);
    user['youtubePlaylists'] = ids;
    return _save(userId, user);
  }

  Future<Map<String, dynamic>> removeUserPlaylistId(
    String userId,
    String playlistId,
  ) async {
    final user = await getUser(userId);
    final ids = List<String>.from(user['youtubePlaylists'] ?? []);
    ids.removeWhere((id) => id == playlistId);
    user['youtubePlaylists'] = ids;
    return _save(userId, user);
  }

  Future<Map<String, dynamic>> createCustomPlaylist(
    String userId, {
    required String title,
    String? image,
  }) async {
    final user = await getUser(userId);
    final custom = List<Map<String, dynamic>>.from(user['customPlaylists'] ?? []);
    final playlist = {
      'ytid': 'custom-${_uuid.v4()}',
      'title': title,
      'source': 'user-created',
      if (image != null) 'image': image,
      'list': <Map<String, dynamic>>[],
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    custom.add(playlist);
    user['customPlaylists'] = custom;
    return _save(userId, user);
  }

  Future<Map<String, dynamic>?> findCustomPlaylist(
    String userId,
    String playlistId,
  ) async {
    final user = await getUser(userId);
    final custom = List<Map<String, dynamic>>.from(user['customPlaylists'] ?? []);
    return custom.firstWhere(
      (p) => p['ytid'] == playlistId,
      orElse: () => {},
    );
  }

  Future<Map<String, dynamic>> addSongToCustomPlaylist(
    String userId, {
    required String playlistId,
    required Map<String, dynamic> song,
  }) async {
    final user = await getUser(userId);
    final custom = List<Map<String, dynamic>>.from(user['customPlaylists'] ?? []);
    final index = custom.indexWhere((p) => p['ytid'] == playlistId);
    if (index == -1) return user;
    final playlist = Map<String, dynamic>.from(custom[index]);
    final list = List<Map<String, dynamic>>.from(playlist['list'] ?? []);
    if (!list.any((s) => s['ytid'] == song['ytid'])) list.add(song);
    playlist['list'] = list;
    custom[index] = playlist;
    user['customPlaylists'] = custom;
    return _save(userId, user);
  }

  Future<Map<String, dynamic>> removeSongFromCustomPlaylist(
    String userId, {
    required String playlistId,
    required String songId,
  }) async {
    final user = await getUser(userId);
    final custom = List<Map<String, dynamic>>.from(user['customPlaylists'] ?? []);
    final index = custom.indexWhere((p) => p['ytid'] == playlistId);
    if (index == -1) return user;
    final playlist = Map<String, dynamic>.from(custom[index]);
    final list = List<Map<String, dynamic>>.from(playlist['list'] ?? []);
    list.removeWhere((s) => s['ytid'] == songId);
    playlist['list'] = list;
    custom[index] = playlist;
    user['customPlaylists'] = custom;
    return _save(userId, user);
  }

  Future<Map<String, dynamic>> setPlaylistFolders(
    String userId,
    List<Map<String, dynamic>> folders,
  ) async {
    final user = await getUser(userId);
    user['playlistFolders'] = folders;
    return _save(userId, user);
  }
}
