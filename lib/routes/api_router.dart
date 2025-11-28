import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../config/env.dart';
import '../data/albums_db.dart';
import '../data/playlists_db.dart';
import '../repositories/user_repository.dart';
import '../services/lyrics_service.dart';
import '../services/recommendation_service.dart';
import '../services/sponsorblock_service.dart';
import '../services/youtube_service.dart';

class ApiRouter {
  ApiRouter({
    required this.config,
    required this.youtube,
    required this.users,
    required this.recommendations,
    required this.sponsorBlock,
    required this.lyrics,
  });

  final AppConfig config;
  final YoutubeService youtube;
  final UserRepository users;
  final RecommendationService recommendations;
  final SponsorBlockService sponsorBlock;
  final LyricsService lyrics;

  Router build() {
    final router = Router();

    router.get('/health', (Request req) {
      return _json({'status': 'ok'});
    });

    router.get('/search', (Request req) async {
      final query = req.requestedUri.queryParameters['q'];
      if (query == null || query.isEmpty) {
        return _json({'error': 'Missing q'}, status: 400);
      }
      final songs = await youtube.searchSongs(query);
      return _json({'items': songs});
    });

    router.get('/suggestions', (Request req) async {
      final query = req.requestedUri.queryParameters['q'];
      if (query == null || query.isEmpty) {
        return _json({'error': 'Missing q'}, status: 400);
      }
      final suggestions = await youtube.getSuggestions(query);
      return _json({'items': suggestions});
    });

    router.get('/playlists', (Request req) async {
      final params = req.requestedUri.queryParameters;
      final query = params['query']?.toLowerCase();
      final type = params['type'] ?? 'all'; // all | album | playlist
      final includeOnline = params['online'] == 'true';

      final curated = [
        ...playlistsDB,
        ...albumsDB,
      ];

      Iterable<Map<String, dynamic>> filtered = curated;
      if (type == 'album') {
        filtered = filtered.where((p) => p['isAlbum'] == true);
      } else if (type == 'playlist') {
        filtered = filtered.where((p) => p['isAlbum'] != true);
      }
      if (query != null && query.isNotEmpty) {
        filtered = filtered.where(
          (p) => p['title'].toString().toLowerCase().contains(query),
        );
      }

      final results = filtered.toList();

      if (includeOnline && query != null && query.isNotEmpty) {
        try {
          final searchResults = await youtube.searchPlaylistsOnline(query);
          final existingIds = results.map((p) => p['ytid'] as String).toSet();
          results.addAll(
            searchResults.map((map) {
              if (existingIds.contains(map['ytid'])) return null;
              existingIds.add(map['ytid'] as String);
              return map;
            }).whereType<Map<String, dynamic>>(),
          );
        } catch (_) {}
      }

      return _json({'items': results});
    });

    router.get('/playlists/<id>', (Request req, String id) async {
      final userId = req.requestedUri.queryParameters['userId'];
      Map<String, dynamic>? playlist;

      // from curated
      final curated = [
        ...playlistsDB,
        ...albumsDB,
      ];
      final curatedMatch = curated
          .cast<Map<String, dynamic>>()
          .firstWhere(
            (p) => p['ytid'] == id,
            orElse: () => <String, dynamic>{},
          );
      if (curatedMatch.isNotEmpty) {
        playlist = curatedMatch;
      }

      // from user custom/youtube lists
      if (playlist == null && userId != null) {
        final user = await users.getUser(userId);
        final custom = List<Map<String, dynamic>>.from(
          user['customPlaylists'] ?? [],
        );
        final customMatch = custom.firstWhere(
          (p) => p['ytid'] == id,
          orElse: () => <String, dynamic>{},
        );
        if (customMatch.isNotEmpty) {
          playlist = customMatch;
        }
        if (playlist == null) {
          final ytIds = List<String>.from(user['youtubePlaylists'] ?? []);
          if (ytIds.contains(id)) {
            playlist = await youtube.getPlaylistInfo(id);
          }
        }
      }

      // fallback to online
      playlist ??= await youtube.getPlaylistInfo(id);

      return _json(playlist);
    });

    router.get('/songs/<id>', (Request req, String id) async {
      final song = await youtube.getSongDetails(id);
      return _json(song);
    });

    router.get('/songs/<id>/stream', (Request req, String id) async {
      try {
        final params = req.requestedUri.queryParameters;
        final quality = params['quality'];
        final mode = (params['mode'] ?? config.streamMode).toLowerCase();
        final useProxy = params['proxy'] == 'true';

        final details = await youtube.getSongDetails(id);
        final isLive = details['isLive'] == true;
        final url = await youtube.getSongUrl(
          id,
          isLive: isLive,
          quality: quality,
          useProxy: useProxy,
        );
        if (url == null) return _json({'error': 'Stream not available'}, status: 404);

        if (mode == 'redirect') {
          return Response.found(url);
        }
        if (mode == 'proxy') {
          try {
            final client = http.Client();
            final streamed = await client.send(
              http.Request('GET', Uri.parse(url)),
            );
            final headers = <String, String>{
              'content-type': streamed.headers['content-type'] ?? 'audio/mpeg',
            };
            return Response(
              streamed.statusCode,
              body: streamed.stream,
              headers: headers,
            );
          } catch (err) {
            print('Proxy stream failed for $id: $err');
            return _json({'error': 'Proxy stream failed'}, status: 502);
          }
        }

        // mode == url
        return _json({'url': url, 'mode': 'url'});
      } on VideoUnavailableException catch (err) {
        print('Video unavailable for $id: $err');
        return _json({'error': 'Video unavailable'}, status: 404);
      } catch (err, stack) {
        print('Stream error for $id: $err');
        print(stack);
        return _json({'error': 'Stream not available'}, status: 502);
      }
    });

    router.get('/songs/<id>/segments', (Request req, String id) async {
      final segments = await sponsorBlock.getSkipSegments(id);
      return _json({'items': segments});
    });

    router.get('/lyrics', (Request req) async {
      final params = req.requestedUri.queryParameters;
      final artist = params['artist'];
      final title = params['title'];
      if (artist == null || title == null) {
        return _json({'error': 'Missing artist or title'}, status: 400);
      }
      final res = await lyrics.fetchLyrics(artist, title);
      if (res == null) return _json({'lyrics': null, 'found': false});
      return _json({'lyrics': res, 'found': true});
    });

    router.get('/recommendations', (Request req) async {
      final userId = req.requestedUri.queryParameters['userId'];
      if (userId != null) {
        final recs = await recommendations.recommendations(
          userId,
          defaultRecommendations: true,
        );
        return _json({'items': recs});
      }
      // fallback global playlist
      final songs = await youtube.getPlaylistSongs(recommendations.globalPlaylistId);
      return _json({'items': songs.take(15).toList()});
    });

    router.get('/users/<userId>/state', (Request req, String userId) async {
      final user = await users.getUser(userId);
      return _json(user);
    });

    router.post('/users/<userId>/likes/song', (Request req, String userId) async {
      final body = await _jsonBody(req);
      final songId = body['songId']?.toString();
      final add = body['add'] != false;
      if (songId == null) return _json({'error': 'songId required'}, status: 400);
      final song = await youtube.getSongDetails(songId);
      final user = await users.likeSong(userId, song, add: add);
      return _json({
        'likedSongs': user['likedSongs'],
        'count': (user['likedSongs'] as List).length,
      });
    });

    router.post('/users/<userId>/likes/playlist', (Request req, String userId) async {
      final body = await _jsonBody(req);
      final playlistId = body['playlistId']?.toString();
      final add = body['add'] != false;
      if (playlistId == null) {
        return _json({'error': 'playlistId required'}, status: 400);
      }
      final playlist = await youtube.getPlaylistInfo(playlistId);
      final user = await users.likePlaylist(userId, playlist, add: add);
      return _json({
        'likedPlaylists': user['likedPlaylists'],
        'count': (user['likedPlaylists'] as List).length,
      });
    });

    router.post('/users/<userId>/recently', (Request req, String userId) async {
      final body = await _jsonBody(req);
      final songId = body['songId']?.toString();
      if (songId == null) return _json({'error': 'songId required'}, status: 400);
      final song = await youtube.getSongDetails(songId);
      final user = await users.addRecentlyPlayed(userId, song);
      return _json({'recentlyPlayed': user['recentlyPlayed']});
    });

    router.post('/users/<userId>/playlists/youtube', (Request req, String userId) async {
      final body = await _jsonBody(req);
      final playlistId = body['playlistId']?.toString();
      if (playlistId == null) {
        return _json({'error': 'playlistId required'}, status: 400);
      }
      final user = await users.addUserPlaylistId(userId, playlistId);
      return _json({'youtubePlaylists': user['youtubePlaylists']});
    });

    router.post('/users/<userId>/playlists/custom', (Request req, String userId) async {
      final body = await _jsonBody(req);
      final title = body['title']?.toString();
      final image = body['image']?.toString();
      if (title == null || title.trim().isEmpty) {
        return _json({'error': 'title required'}, status: 400);
      }
      final user = await users.createCustomPlaylist(userId, title: title.trim(), image: image);
      return _json({'customPlaylists': user['customPlaylists']});
    });

    router.post('/users/<userId>/playlists/custom/<playlistId>/songs',
        (Request req, String userId, String playlistId) async {
      final body = await _jsonBody(req);
      final songId = body['songId']?.toString();
      if (songId == null) return _json({'error': 'songId required'}, status: 400);
      final song = await youtube.getSongDetails(songId);
      final user = await users.addSongToCustomPlaylist(
        userId,
        playlistId: playlistId,
        song: song,
      );
      return _json({'customPlaylists': user['customPlaylists']});
    });

    return router;
  }

  Response _json(
    Object? data, {
    int status = 200,
  }) {
    return Response(
      status,
      body: jsonEncode(data),
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
      },
    );
  }

  Future<Map<String, dynamic>> _jsonBody(Request req) async {
    if (req.contentLength == 0) return {};
    final body = await req.readAsString();
    if (body.isEmpty) return {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }
}
