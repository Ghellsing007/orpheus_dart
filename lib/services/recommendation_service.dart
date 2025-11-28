import '../repositories/user_repository.dart';
import '../services/youtube_service.dart';

class RecommendationService {
  RecommendationService(
    this._users,
    this._yt, {
    this.globalPlaylistId = 'PLgzTt0k8mXzEk586ze4BjvDXR7c-TUSnx',
  });

  final UserRepository _users;
  final YoutubeService _yt;
  final String globalPlaylistId;

  Future<List<Map<String, dynamic>>> recommendations(
    String userId, {
    bool defaultRecommendations = false,
  }) async {
    final user = await _users.getUser(userId);
    final recently = List<Map<String, dynamic>>.from(
      user['recentlyPlayed'] ?? [],
    );

    if (defaultRecommendations && recently.isNotEmpty) {
      return _fromRecentlyPlayed(recently);
    }

    return _mixed(user);
  }

  Future<List<Map<String, dynamic>>> _fromRecentlyPlayed(
    List<Map<String, dynamic>> recently,
  ) async {
    final recent = recently.take(3).toList();

    final futures = recent.map((songData) async {
      try {
        final related = await _yt.getRelatedSongs(songData['ytid']);
        return related.take(3).toList();
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    }).toList();

    final results = await Future.wait(futures);
    final playlistSongs = results.expand((list) => list).take(15).toList()
      ..shuffle();
    return playlistSongs;
  }

  Future<List<Map<String, dynamic>>> _mixed(
    Map<String, dynamic> user,
  ) async {
    final playlistSongs = <Map<String, dynamic>>[
      ...List<Map<String, dynamic>>.from(user['likedSongs'] ?? []),
      ...List<Map<String, dynamic>>.from(user['recentlyPlayed'] ?? []),
    ];

    // global
    try {
      final global = await _yt.getPlaylistSongs(globalPlaylistId);
      playlistSongs.addAll(global.take(10));
    } catch (_) {}

    // custom
    final custom = List<Map<String, dynamic>>.from(
      user['customPlaylists'] ?? [],
    );
    for (final pl in custom) {
      final list = List<Map<String, dynamic>>.from(pl['list'] ?? []);
      list.shuffle();
      playlistSongs.addAll(list.take(5));
    }

    return _deduplicateAndShuffle(playlistSongs);
  }

  List<Map<String, dynamic>> _deduplicateAndShuffle(
    List<Map<String, dynamic>> playlistSongs,
  ) {
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];

    playlistSongs.shuffle();
    for (final song in playlistSongs) {
      final id = song['ytid']?.toString();
      if (id != null && seen.add(id)) {
        unique.add(song);
        if (unique.length >= 15) break;
      }
    }
    return unique;
  }
}
