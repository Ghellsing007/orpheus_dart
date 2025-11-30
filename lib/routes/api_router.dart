import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../config/env.dart';
import '../data/albums_db.dart';
import '../data/playlists_db.dart';
import '../models/media_models.dart';
import '../repositories/media_repository.dart';
import '../repositories/user_repository.dart';
import '../services/lyrics_service.dart';
import '../services/recommendation_service.dart';
import '../services/sponsorblock_service.dart';
import '../services/youtube_service.dart';
import '../data/curated_home.dart';
import '../repositories/home_repository.dart';

class ApiRouter {
  ApiRouter({
    required this.config,
    required this.youtube,
    required this.users,
    required this.recommendations,
    required this.sponsorBlock,
    required this.lyrics,
    required this.home,
    required this.media,
  });

  final AppConfig config;
  final YoutubeService youtube;
  final UserRepository users;
  final RecommendationService recommendations;
  final SponsorBlockService sponsorBlock;
  final LyricsService lyrics;
  final HomeRepository home;
  final MediaRepositoryBase media;

  static const _defaultPageSize = 20;
  static const _maxPageSize = 50;
  static const _maxIdsPerRequest = 50;

  Router build() {
    final router = Router();

    router.get('/health', (Request req) {
      return _json({'status': 'ok'});
    });

    router.get('/home/curated', (Request req) async {
      await migrateLegacyHome(home);
      final doc = await home.getOrSeed();
      final sections = await home.getSections();
      final previews = await home.getPreviews();
      final resolved = buildResolvedHomePayload(sections, previews);
      // DEBUG: Log URLs being sent to frontend
      previews.forEach((key, value) {
        if (value is Map && value.containsKey('image')) {
          print('DEBUG: Preview $key image URL: ${value['image']}');
        }
      });
      return _json({
        'sections': sections.map((s) => s.toMap()).toList(),
        'previews': previews,
        'resolved': resolved,
        'status': doc['status'] ?? {},
        'updatedAt': doc['updatedAt'],
      }, headers: {
        HttpHeaders.cacheControlHeader: 'public, max-age=300',
      });
    });

    router.post('/home/curated/refresh', (Request req) async {
      final section = req.requestedUri.queryParameters['section'] ?? 'artists';
      final limit =
          int.tryParse(req.requestedUri.queryParameters['limit'] ?? '') ?? 3;
      final data = await hydrateCuratedChunk(
        youtube,
        home,
        media,
        section: section,
        limit: limit,
      );
      return _json(data);
    });

    router.get('/media/songs', (Request req) async {
      final idsParam = req.requestedUri.queryParameters['ids'];
      final ids = (idsParam ?? '')
          .split(',')
          .where((id) => id.isNotEmpty)
          .take(_maxIdsPerRequest)
          .toList();
      final songs = await media.getSongsByIds(ids);
      return _json({'items': songs.map((song) => song.toMap()).toList()});
    });

    router.get('/media/playlists', (Request req) async {
      final idsParam = req.requestedUri.queryParameters['ids'];
      final ids = (idsParam ?? '')
          .split(',')
          .where((id) => id.isNotEmpty)
          .take(_maxIdsPerRequest)
          .toList();
      final collections = await media.getCollectionsByIds(ids);
      return _json({
        'items': collections.map((collection) => collection.toMap()).toList(),
      });
    });

    router.get('/media/artists', (Request req) async {
      final idsParam = req.requestedUri.queryParameters['ids'];
      final ids = (idsParam ?? '')
          .split(',')
          .where((id) => id.isNotEmpty)
          .take(_maxIdsPerRequest)
          .toList();
      final artists = <Artist>[];
      for (final id in ids) {
        final artist = await media.getArtistById(id);
        if (artist != null) artists.add(artist);
      }
      return _json({'items': artists.map((artist) => artist.toMap()).toList()});
    });

    router.get('/search', (Request req) async {
      final query = req.requestedUri.queryParameters['q'];
      if (query == null || query.isEmpty) {
        return _json({'error': 'Missing q'}, status: 400);
      }
      final limit = _parseLimit(req.requestedUri.queryParameters['limit']);
      final page = _parsePage(req.requestedUri.queryParameters['page']);
      final offset = (page - 1) * limit;
      final songs = await youtube.searchSongs(query);
      final sliced = songs.skip(offset).take(limit).toList();
      return _json({
        'items': sliced,
        'page': page,
        'limit': limit,
        'hasNext': offset + limit < songs.length,
      });
    });

    router.get('/suggestions', (Request req) async {
      final query = req.requestedUri.queryParameters['q'];
      if (query == null || query.isEmpty) {
        return _json({'error': 'Missing q'}, status: 400);
      }
      final suggestions = await youtube.getSuggestions(query);
      return _json({'items': suggestions});
    });

    router.get('/channel/search', (Request req) async {
      final query = req.requestedUri.queryParameters['q'];
      if (query == null || query.isEmpty) {
        return _json({'error': 'Missing q'}, status: 400);
      }
      final channels = await youtube.searchChannels(query);
      return _json({'items': channels});
    });

    router.get('/channel/<id>', (Request req, String id) async {
      // Decode por si viene URL encoded desde el cliente
      final decodedId = Uri.decodeComponent(id);
      String channelId = decodedId;
      final looksLikeId = RegExp(r'^UC[0-9A-Za-z_-]{20,}$').hasMatch(decodedId);

      // Si no parece un channelId, búscalo por nombre
      if (!looksLikeId) {
        try {
          final found = await youtube.searchChannels(decodedId);
          if (found.isEmpty) {
            return _json({'error': 'Channel not found'}, status: 404);
          }
          channelId = found.first['ytid'] as String? ?? id;
        } catch (_) {
          return _json({'error': 'Channel not found'}, status: 404);
        }
      }

      final channel = await youtube.getChannelDetails(channelId);
      // Intenta persistir en artistas para reutilizarlo luego
      try {
        await media.persistArtistFromYoutube(channel);
      } catch (_) {}
      return _json(channel);
    });

    // Artist details: prefer DB, fallback to YouTube then persist
    router.get('/artists/<id>', (Request req, String id) async {
      final decodedId = Uri.decodeComponent(id);
      final stored = await media.getArtistById(decodedId);
      if (stored != null) return _json(stored.toMap());

      try {
        String channelId = decodedId;
        final looksLikeId = RegExp(r'^UC[0-9A-Za-z_-]{20,}$').hasMatch(decodedId);
        if (!looksLikeId) {
          final found = await youtube.searchChannels(decodedId);
          if (found.isNotEmpty) {
            channelId = found.first['ytid'] as String? ?? decodedId;
          }
        }
        final payload = await youtube.getChannelDetails(channelId);
        final persisted = await media.persistArtistFromYoutube(payload);
        return _json(persisted.toMap());
      } catch (err) {
        print('Error fetching artist $id from YouTube: $err');
        return _json({'error': 'Artist not found'}, status: 404);
      }
    });

    router.get('/channel/<id>/songs', (Request req, String id) async {
      final params = req.requestedUri.queryParameters;
      final limitParam = params['limit'];
      final limit = _parseLimit(limitParam, defaultValue: 30);
      final songs = await youtube.getChannelSongs(id, limit: limit);
      return _json({'items': songs});
    });

    router.get('/playlists', (Request req) async {
      final params = req.requestedUri.queryParameters;
      final query = params['query']?.toLowerCase();
      final type = params['type'] ?? 'all'; // all | album | playlist
      final includeOnline = params['online'] == 'true';
      final limit = _parseLimit(params['limit']);
      final page = _parsePage(params['page']);
      final offset = (page - 1) * limit;

      final curated = [...playlistsDB, ...albumsDB];

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

      final total = results.length;
      final paged = results.skip(offset).take(limit).toList();
      return _json({
        'items': paged,
        'page': page,
        'limit': limit,
        'total': total,
        'hasNext': offset + limit < total,
      });
    });

    router.get('/playlists/<id>', (Request req, String id) async {
      // 1) Try DB first (fast path)
      final stored = await media.getDbPlaylistById(id);
      if (stored != null) return _json(stored);

      // 2) Fallback: fetch from YouTube, persist, and return freshly stored doc
      try {
        final payload = await youtube.getPlaylistInfo(id);
        final persisted = await media.persistCollectionFromYoutube(
          payload,
          type: CollectionType.playlist,
        );
        // persistCollectionFromYoutube already writes the playlist doc; retrieve to ensure we return the DB shape
        final refreshed = await media.getDbPlaylistById(persisted.collection.ytid);
        if (refreshed != null) return _json(refreshed);
      } catch (err) {
        print('Error fetching playlist $id from YouTube: $err');
      }

      return _json({'error': 'Playlist not found'}, status: 404);
    });

    router.get('/songs/<id>', (Request req, String id) async {
      final stored = await media.getSongById(id);
      if (stored != null) return _json(stored.toMap());

      try {
        final payload = await youtube.getSongDetails(id);
        final persisted = await media.persistSongFromYoutube(payload);
        return _json(persisted.toMap());
      } catch (err) {
        print('Error fetching song $id from YouTube: $err');
        return _json({'error': 'Song not found'}, status: 404);
      }
    });

    // Transcoded MP3 download
    router.get('/download/mp3/<id>', (Request req, String id) async {
      try {
        Map<String, dynamic>? details;
        bool isLive = false;
        try {
          details = await youtube.getSongDetails(id);
          isLive = details['isLive'] == true;
        } on VideoUnavailableException {
          details = null;
          isLive = false;
        }

        String? url;
        try {
          url = await youtube.getSongUrl(
            id,
            isLive: isLive,
            quality: 'high',
            useProxy: false,
          );
        } on VideoUnavailableException {
          url = null;
        }

        // Fallback con proxy si está habilitado
        if (url == null && youtube.proxyPoolEnabled) {
          try {
            url = await youtube.getSongUrl(
              id,
              isLive: isLive,
              quality: 'high',
              useProxy: true,
            );
          } catch (_) {
            url = null;
          }
        }
        if (url == null)
          return _json({'error': 'Stream not available'}, status: 404);

        Process process;
        try {
          process = await Process.start('ffmpeg', [
            '-hide_banner',
            '-loglevel',
            'error',
            '-i',
            url,
            '-vn',
            '-acodec',
            'libmp3lame',
            '-b:a',
            '192k',
            '-f',
            'mp3',
            'pipe:1',
          ]);
        } on ProcessException catch (err) {
          print('ffmpeg not available: $err');
          return _json({
            'error': 'ffmpeg not available on server',
          }, status: 500);
        }

        // Construye filenames seguros: ASCII (fallback) + UTF-8 (RFC 5987) para navegadores.
        final baseName =
            '${details?['artist'] ?? 'audio'} - ${details?['title'] ?? id}.mp3';
        final asciiClean = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final asciiFallback = asciiClean.isNotEmpty ? asciiClean : 'audio';
        final filenameAscii = '$asciiFallback.mp3';
        final filenameUtf8 = Uri.encodeComponent(baseName);

        return Response.ok(
          process.stdout,
          headers: {
            HttpHeaders.contentTypeHeader: 'audio/mpeg',
            // ASCII-only fallback + UTF-8 extended filename.
            'content-disposition':
                'attachment; filename="$filenameAscii"; filename*=UTF-8\'\'$filenameUtf8',
          },
        );
      } catch (err, stack) {
        print('Download mp3 error for $id: $err');
        print(stack);
        return _json({'error': 'Download not available'}, status: 502);
      }
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
        if (url == null)
          return _json({'error': 'Stream not available'}, status: 404);

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
      final limit = _parseLimit(req.requestedUri.queryParameters['limit'], defaultValue: 15);
      if (userId != null) {
        final recs = await recommendations.recommendations(
          userId,
          defaultRecommendations: true,
        );
        return _json({'items': recs.take(limit).toList()});
      }
      // fallback global playlist
      final songs = await youtube.getPlaylistSongs(
        recommendations.globalPlaylistId,
      );
      final persisted = await Future.wait(
        songs.take(15).map((song) {
          return media.persistSongFromYoutube(
            song,
            sections: {HomeSectionType.recommendations},
          );
        }),
      );
      return _json({
        'items': persisted.take(limit).map((song) => song.toMap()).toList(),
      });
    });

    router.get('/users/<userId>/state', (Request req, String userId) async {
      final user = await users.getUser(userId);
      final recentLimit = _parseLimit(
        req.requestedUri.queryParameters['recentLimit'],
        defaultValue: UserRepository.recentLimit,
        maxValue: UserRepository.recentLimit,
      );
      final likedLimit = _parseLimit(
        req.requestedUri.queryParameters['likedLimit'],
        defaultValue: user['likedSongs']?.length ?? _defaultPageSize,
      );
      final playlistLimit = _parseLimit(
        req.requestedUri.queryParameters['playlistLimit'],
        defaultValue: user['likedPlaylists']?.length ?? _defaultPageSize,
      );
      final shaped = Map<String, dynamic>.from(user);
      shaped['likedSongs'] =
          List<Map<String, dynamic>>.from(shaped['likedSongs'] ?? [])
              .take(likedLimit)
              .toList();
      shaped['likedPlaylists'] =
          List<Map<String, dynamic>>.from(shaped['likedPlaylists'] ?? [])
              .take(playlistLimit)
              .toList();
      shaped['recentlyPlayed'] =
          List<Map<String, dynamic>>.from(shaped['recentlyPlayed'] ?? [])
              .take(recentLimit)
              .toList();
      return _json(shaped);
    });

    router.post('/users/<userId>/likes/song', (
      Request req,
      String userId,
    ) async {
      final body = await _jsonBody(req);
      final songId = body['songId']?.toString();
      final add = body['add'] != false;
      if (songId == null)
        return _json({'error': 'songId required'}, status: 400);
      final song = await youtube.getSongDetails(songId);
      final user = await users.likeSong(userId, song, add: add);
      return _json({
        'likedSongs': user['likedSongs'],
        'count': (user['likedSongs'] as List).length,
      });
    });

    router.post('/users/<userId>/likes/playlist', (
      Request req,
      String userId,
    ) async {
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
      if (songId == null)
        return _json({'error': 'songId required'}, status: 400);
      Map<String, dynamic> song;
      try {
        song = await youtube.getSongDetails(songId);
      } on VideoUnavailableException {
        return _json({'error': 'Song unavailable'}, status: 404);
      }
      final user = await users.addRecentlyPlayed(userId, song);
      return _json({'recentlyPlayed': user['recentlyPlayed']});
    });

    router.post('/users/<userId>/playlists/youtube', (
      Request req,
      String userId,
    ) async {
      final body = await _jsonBody(req);
      final playlistId = body['playlistId']?.toString();
      if (playlistId == null) {
        return _json({'error': 'playlistId required'}, status: 400);
      }
      final user = await users.addUserPlaylistId(userId, playlistId);
      return _json({'youtubePlaylists': user['youtubePlaylists']});
    });

    router.post('/users/<userId>/playlists/custom', (
      Request req,
      String userId,
    ) async {
      final body = await _jsonBody(req);
      final title = body['title']?.toString();
      final image = body['image']?.toString();
      if (title == null || title.trim().isEmpty) {
        return _json({'error': 'title required'}, status: 400);
      }
      final user = await users.createCustomPlaylist(
        userId,
        title: title.trim(),
        image: image,
      );
      return _json({'customPlaylists': user['customPlaylists']});
    });

    router.post('/users/<userId>/playlists/custom/<playlistId>/songs', (
      Request req,
      String userId,
      String playlistId,
    ) async {
      final body = await _jsonBody(req);
      final songId = body['songId']?.toString();
      if (songId == null)
        return _json({'error': 'songId required'}, status: 400);
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

  Response _json(Object? data, {int status = 200, Map<String, String>? headers}) {
    return Response(
      status,
      body: jsonEncode(data),
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
        ...?headers,
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

  int _parseLimit(
    String? raw, {
    int defaultValue = _defaultPageSize,
    int maxValue = _maxPageSize,
  }) {
    final parsed = int.tryParse(raw ?? '') ?? defaultValue;
    return parsed.clamp(1, maxValue);
  }

  int _parsePage(String? raw) {
    final parsed = int.tryParse(raw ?? '') ?? 1;
    return parsed < 1 ? 1 : parsed;
  }
}
