import 'dart:convert';

import 'package:orpheus_dart/config/env.dart';
import 'package:orpheus_dart/repositories/user_repository.dart';
import 'package:orpheus_dart/routes/api_router.dart';
import 'package:orpheus_dart/services/lyrics_service.dart';
import 'package:orpheus_dart/services/recommendation_service.dart';
import 'package:orpheus_dart/services/sponsorblock_service.dart';
import 'package:orpheus_dart/services/youtube_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  late Handler handler;
  late FakeUserRepository fakeUsers;

  setUp(() {
    final config = AppConfig.manual(
      port: 8080,
      mongoUri: 'mongodb://fake',
      proxyUrl: null,
      streamMode: 'redirect',
    );
    final youtube = FakeYoutubeService();
    fakeUsers = FakeUserRepository();
    final recommendations = FakeRecommendationService();
    final sponsor = FakeSponsorBlockService();
    final lyrics = FakeLyricsService();

    final router = ApiRouter(
      config: config,
      youtube: youtube,
      users: fakeUsers,
      recommendations: recommendations,
      sponsorBlock: sponsor,
      lyrics: lyrics,
    ).build();

    handler = const Pipeline().addHandler(router.call);
  });

  test('health returns ok', () async {
    final res = await handler(Request('GET', Uri.parse('http://localhost/health')));
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(res.statusCode, 200);
    expect(body['status'], 'ok');
  });

  test('search returns fake songs', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/search?q=test')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['items'], isA<List>());
    expect((body['items'] as List).first['ytid'], 'song-1');
  });

  test('playlists include curated and online results', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/playlists?query=top&online=true')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['items'], isA<List>());
    final titles = (body['items'] as List).map((e) => e['title']).toList();
    expect(titles, contains('Top 50 Global'));
    expect(titles, contains('Online Playlist'));
  });

  test('playlist detail falls back to youtube service', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/playlists/fake-playlist')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['ytid'], 'fake-playlist');
    expect(body['list'], isA<List>());
  });

  test('channel search returns channels', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/channel/search?q=taylor')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['items'], isA<List>());
    expect((body['items'] as List).first['ytid'], 'chan-1');
  });

  test('channel detail returns meta and songs', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/channel/chan-1')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['ytid'], 'chan-1');
    expect(body['topSongs'], isA<List>());
  });

  test('channel songs endpoint returns list', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/channel/chan-1/songs')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['items'], isA<List>());
    expect((body['items'] as List).first['ytid'], 'song-chan');
  });

  test('stream redirect returns 302 with location', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/songs/song-1/stream?mode=redirect')),
    );
    expect(res.statusCode, 302);
    expect(res.headers['location'], 'http://stream-url');
  });

  test('stream url mode returns json with url', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/songs/song-1/stream?mode=url')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['url'], 'http://stream-url');
    expect(body['mode'], 'url');
  });

  test('lyrics returns found', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/lyrics?artist=a&title=b')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['found'], true);
    expect(body['lyrics'], isNotEmpty);
  });

  test('sponsorblock returns segments', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/songs/song-1/segments')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['items'], isA<List>());
    expect((body['items'] as List).first['start'], 0);
  });

  test('like song updates user state', () async {
    final request = Request(
      'POST',
      Uri.parse('http://localhost/users/u1/likes/song'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'songId': 'song-1', 'add': true}),
    );
    final res = await handler(request);
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(res.statusCode, 200);
    expect(body['count'], 1);
  });

  test('add youtube playlist updates user state', () async {
    final request = Request(
      'POST',
      Uri.parse('http://localhost/users/u1/playlists/youtube'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'playlistId': 'pl-123'}),
    );
    final res = await handler(request);
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['youtubePlaylists'], contains('pl-123'));
  });

  test('custom playlist creation and add song', () async {
    final create = Request(
      'POST',
      Uri.parse('http://localhost/users/u1/playlists/custom'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'title': 'My List'}),
    );
    final resCreate = await handler(create);
    final bodyCreate = jsonDecode(await resCreate.readAsString()) as Map;
    final playlistId = (bodyCreate['customPlaylists'] as List).first['ytid'];

    final addSong = Request(
      'POST',
      Uri.parse('http://localhost/users/u1/playlists/custom/$playlistId/songs'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'songId': 'song-1'}),
    );
    final resAdd = await handler(addSong);
    final bodyAdd = jsonDecode(await resAdd.readAsString()) as Map;
    final list = (bodyAdd['customPlaylists'] as List).firstWhere(
      (p) => p['ytid'] == playlistId,
    )['list'] as List;
    expect(list.length, 1);
    expect(list.first['ytid'], 'song-1');
  });

  test('recently played updates list', () async {
    final req = Request(
      'POST',
      Uri.parse('http://localhost/users/u1/recently'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'songId': 'song-2'}),
    );
    final res = await handler(req);
    final body = jsonDecode(await res.readAsString()) as Map;
    expect((body['recentlyPlayed'] as List).first['ytid'], 'song-2');
  });

  test('recommendations with user id returns list', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/recommendations?userId=u1')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['items'], isA<List>());
    expect((body['items'] as List).first['ytid'], 'rec-1');
  });

  test('recommendations without user fall back to global playlist', () async {
    final res = await handler(Request('GET', Uri.parse('http://localhost/recommendations')));
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['items'], isA<List>());
    expect((body['items'] as List).first['ytid'], 'song-1');
  });
}

class FakeYoutubeService implements YoutubeService {
  @override
  String? get proxyUrl => null;

  @override
  String get defaultQuality => 'high';

  @override
  bool get proxyPoolEnabled => false;

  @override
  YoutubeExplode get clientForTests => YoutubeExplode();

  @override
  Future<void> dispose() async {}

  @override
  Future<List<Map<String, dynamic>>> getPlaylistSongs(String playlistId,
      {String? playlistImage, int minDurationSec = 60}) async {
    return [
      _song('song-1'),
      _song('song-2'),
    ];
  }

  @override
  Future<Map<String, dynamic>> getPlaylistInfo(String playlistId) async {
    return {
      'ytid': playlistId,
      'title': 'Fake Playlist',
      'image': null,
      'source': 'youtube',
      'list': await getPlaylistSongs(playlistId),
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getRelatedSongs(String songId) async =>
      [ _song('song-related') ];

  @override
  Future<Map<String, dynamic>> getSongDetails(String songId) async =>
      _song(songId);

  @override
  Future<List<Map<String, dynamic>>> searchChannels(String query) async => [
        {
          'id': 'chan-1',
          'ytid': 'chan-1',
          'title': 'Channel 1',
          'name': 'Channel 1',
          'image': 'img',
        }
      ];

  @override
  Future<Map<String, dynamic>> getChannelDetails(String channelId) async => {
        'id': channelId,
        'ytid': channelId,
        'title': 'Channel $channelId',
        'name': 'Channel $channelId',
        'image': 'img',
        'banner': 'banner',
        'description': 'desc',
        'topSongs': [
          _song('song-chan'),
        ],
        'playlists': [
          {
            'ytid': 'pl-chan',
            'title': 'Playlist chan',
            'source': 'youtube',
            'list': <Map<String, dynamic>>[],
          }
        ],
        'related': <Map<String, dynamic>>[],
      };

  @override
  Future<List<Map<String, dynamic>>> getChannelSongs(String channelId, {int limit = 30, int minDurationSec = 25, String? channelTitle}) async =>
      [_song('song-chan')];

  @override
  Future<String?> getSongUrl(String songId,
          {bool isLive = false, String? quality, bool useProxy = false}) async =>
      'http://stream-url';

  @override
  Future<List<String>> getSuggestions(String query) async => ['s1', 's2'];

  @override
  Future<List<Map<String, dynamic>>> searchPlaylistsOnline(String query) async =>
      [
        {
          'ytid': 'online-1',
          'title': 'Online Playlist',
          'source': 'youtube',
          'list': <Map<String, dynamic>>[],
        }
      ];

  @override
  Future<List<Map<String, dynamic>>> searchSongs(String query) async =>
      [_song('song-1')];

  Map<String, dynamic> _song(String id) => {
        'id': 0,
        'ytid': id,
        'title': 'Title $id',
        'artist': 'Artist',
        'image': 'img',
        'lowResImage': 'img',
        'highResImage': 'img',
        'duration': 120,
        'isLive': false,
      };
}

class FakeRecommendationService implements RecommendationService {
  @override
  String get globalPlaylistId => 'fake';

  @override
  Future<List<Map<String, dynamic>>> recommendations(String userId,
          {bool defaultRecommendations = false}) async =>
      [
        {'ytid': 'rec-1'}
      ];
}

class FakeSponsorBlockService implements SponsorBlockService {
  @override
  Future<List<Map<String, int>>> getSkipSegments(String videoId) async =>
      [
        {'start': 0, 'end': 10}
      ];
}

class FakeLyricsService implements LyricsService {
  @override
  Future<String?> fetchLyrics(String artistName, String title) async =>
      'la la la';

  @override
  String addCopyright(String input, String copyright) => '$input $copyright';
}

class FakeUserRepository implements UserRepository {
  final Map<String, Map<String, dynamic>> _store = {};

  Map<String, dynamic> _emptyUser(String id) => {
        '_id': id,
        'likedSongs': <Map<String, dynamic>>[],
        'likedPlaylists': <Map<String, dynamic>>[],
        'recentlyPlayed': <Map<String, dynamic>>[],
        'customPlaylists': <Map<String, dynamic>>[],
        'playlistFolders': <Map<String, dynamic>>[],
        'youtubePlaylists': <String>[],
      };

  @override
  Future<Map<String, dynamic>> addRecentlyPlayed(String userId, Map<String, dynamic> song) async {
    final u = await getUser(userId);
    final list = List<Map<String, dynamic>>.from(u['recentlyPlayed']);
    list.insert(0, song);
    u['recentlyPlayed'] = list;
    return u;
  }

  @override
  Future<Map<String, dynamic>> addSongToCustomPlaylist(String userId,
      {required String playlistId, required Map<String, dynamic> song}) async {
    final u = await getUser(userId);
    final customs = List<Map<String, dynamic>>.from(u['customPlaylists']);
    final idx = customs.indexWhere((e) => e['ytid'] == playlistId);
    if (idx != -1) {
      final list = List<Map<String, dynamic>>.from(customs[idx]['list']);
      list.add(song);
      customs[idx]['list'] = list;
    }
    u['customPlaylists'] = customs;
    return u;
  }

  @override
  Future<Map<String, dynamic>> addUserPlaylistId(String userId, String playlistId) async {
    final u = await getUser(userId);
    final ids = List<String>.from(u['youtubePlaylists']);
    if (!ids.contains(playlistId)) ids.add(playlistId);
    u['youtubePlaylists'] = ids;
    return u;
  }

  @override
  Future<Map<String, dynamic>?> findCustomPlaylist(String userId, String playlistId) async {
    final u = await getUser(userId);
    final customs = List<Map<String, dynamic>>.from(u['customPlaylists']);
    return customs.firstWhere((e) => e['ytid'] == playlistId, orElse: () => {});
  }

  @override
  Future<Map<String, dynamic>> createCustomPlaylist(String userId, {required String title, String? image}) async {
    final u = await getUser(userId);
    final customs = List<Map<String, dynamic>>.from(u['customPlaylists']);
    customs.add({
      'ytid': 'custom-1',
      'title': title,
      'source': 'user-created',
      'image': image,
      'list': <Map<String, dynamic>>[],
    });
    u['customPlaylists'] = customs;
    return u;
  }

  @override
  Future<Map<String, dynamic>> getUser(String userId) async {
    return _store.putIfAbsent(userId, () => _emptyUser(userId));
  }

  @override
  Future<Map<String, dynamic>> likePlaylist(String userId, Map<String, dynamic> playlist, {required bool add}) async {
    final u = await getUser(userId);
    final liked = List<Map<String, dynamic>>.from(u['likedPlaylists']);
    if (add) {
      if (!liked.any((p) => p['ytid'] == playlist['ytid'])) liked.add(playlist);
    } else {
      liked.removeWhere((p) => p['ytid'] == playlist['ytid']);
    }
    u['likedPlaylists'] = liked;
    return u;
  }

  @override
  Future<Map<String, dynamic>> likeSong(String userId, Map<String, dynamic> song, {required bool add}) async {
    final u = await getUser(userId);
    final liked = List<Map<String, dynamic>>.from(u['likedSongs']);
    if (add) {
      if (!liked.any((s) => s['ytid'] == song['ytid'])) liked.add(song);
    } else {
      liked.removeWhere((s) => s['ytid'] == song['ytid']);
    }
    u['likedSongs'] = liked;
    return u;
  }

  @override
  Future<Map<String, dynamic>> removeSongFromCustomPlaylist(String userId, {required String playlistId, required String songId}) {
    return Future.value(_store[userId] ?? _emptyUser(userId));
  }

  @override
  Future<Map<String, dynamic>> removeUserPlaylistId(String userId, String playlistId) async {
    final u = await getUser(userId);
    final ids = List<String>.from(u['youtubePlaylists']);
    ids.removeWhere((id) => id == playlistId);
    u['youtubePlaylists'] = ids;
    return u;
  }

  @override
  Future<Map<String, dynamic>> setPlaylistFolders(String userId, List<Map<String, dynamic>> folders) async {
    final u = await getUser(userId);
    u['playlistFolders'] = folders;
    return u;
  }
}
