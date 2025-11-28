import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import './cache_service.dart';
import './proxy_manager.dart';
import '../utils/formatter.dart';

const Duration songCacheDuration = Duration(hours: 1, minutes: 30);
const Duration playlistCacheDuration = Duration(hours: 5);
const Duration searchCacheDuration = Duration(days: 4);
const Duration streamCacheDuration = Duration(hours: 3);

class YoutubeService {
  YoutubeService({
    this.proxyUrl,
    this.defaultQuality = 'high',
    this.proxyPoolEnabled = true,
  }) {
    _directClient = YoutubeExplode();
    if (_isValidProxy(proxyUrl)) {
      _proxyClient = _buildProxyClient(proxyUrl!);
    }
    _proxyManager = ProxyManager(enabled: proxyPoolEnabled);
  }

  final String? proxyUrl;
  final String defaultQuality;
  final bool proxyPoolEnabled;
  late final ProxyManager _proxyManager;

  late final YoutubeExplode _directClient;
  YoutubeExplode? _proxyClient;

  YoutubeExplode _client({bool forceProxy = false}) {
    if (forceProxy && _proxyClient != null) return _proxyClient!;
    return _proxyClient ?? _directClient;
  }

  bool _isValidProxy(String? value) {
    if (value == null) return false;
    if (value.isEmpty) return false;
    // Basic validation: expect host:port without scheme
    final pattern = RegExp(r'^[^:]+:\d+$');
    return pattern.hasMatch(value);
  }

  // Visible for testing
  YoutubeExplode get clientForTests => _client();

  YoutubeExplode _buildProxyClient(String proxyAddress) {
    final httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    httpClient.findProxy = (_) => 'PROXY $proxyAddress; DIRECT';
    httpClient.badCertificateCallback = (cert, host, port) => false;
    final io = IOClient(httpClient);
    return YoutubeExplode(YoutubeHttpClient(io));
  }

  Future<List<Map<String, dynamic>>> searchSongs(String query) async {
    final cacheKey = 'search_$query';
    final cached = cache.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null) return cached;

    final results = await _client()
        .search
        .search(query)
        .timeout(const Duration(seconds: 12));
    final songs = results.map((video) => returnSongLayout(0, video)).toList();
    cache.set(cacheKey, songs, searchCacheDuration);
    return songs;
  }

  Future<List<String>> getSuggestions(String query) async {
    final cacheKey = 'suggestions_$query';
    final cached = cache.get<List<String>>(cacheKey);
    if (cached != null) return cached;
    final suggestions = await _client()
        .search
        .getQuerySuggestions(query)
        .timeout(const Duration(seconds: 8));
    cache.set(cacheKey, suggestions, searchCacheDuration);
    return suggestions;
  }

  Future<List<Map<String, dynamic>>> getPlaylistSongs(
    String playlistId, {
    String? playlistImage,
  }) async {
    final cacheKey = 'playlistSongs_$playlistId';
    final cached = cache.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null) return cached;

    final songList = <Map<String, dynamic>>[];
    await for (final song in _client().playlists.getVideos(playlistId)) {
      songList.add(
        returnSongLayout(songList.length, song, playlistImage: playlistImage),
      );
    }
    cache.set(cacheKey, songList, playlistCacheDuration);
    return songList;
  }

  Future<Map<String, dynamic>> getPlaylistInfo(String playlistId) async {
    final cacheKey = 'playlist_$playlistId';
    final cached = cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    final playlist = await _client()
        .playlists
        .get(playlistId)
        .timeout(const Duration(seconds: 12));

    final songs = await getPlaylistSongs(
      playlistId,
      playlistImage: playlist.thumbnails.standardResUrl,
    );

    final map = {
      'ytid': playlist.id.toString(),
      'title': playlist.title,
      'image': playlist.thumbnails.maxResUrl,
      'source': 'youtube',
      'list': songs,
    };
    cache.set(cacheKey, map, playlistCacheDuration);
    return map;
  }

  Future<List<Map<String, dynamic>>> getRelatedSongs(String songId) async {
    final song = await _client()
        .videos
        .get(songId)
        .timeout(const Duration(seconds: 12));
    final related =
        await _client().videos.getRelatedVideos(song) ?? <Video>[];
    return related.map((s) => returnSongLayout(0, s)).toList();
  }

  Future<Map<String, dynamic>> getSongDetails(String songId) async {
    final cacheKey = 'song_$songId';
    final cached = cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    final song = await _client()
        .videos
        .get(songId)
        .timeout(const Duration(seconds: 12));
    final map = returnSongLayout(0, song);
    cache.set(cacheKey, map, songCacheDuration);
    return map;
  }

  Future<List<Map<String, dynamic>>> searchPlaylistsOnline(String query) async {
    final results = await _client()
        .search
        .searchContent(
          query,
          filter: TypeFilters.playlist,
        )
        .timeout(const Duration(seconds: 12));

    return results.whereType<SearchPlaylist>().map((p) {
      final thumb = p.thumbnails.isNotEmpty
          ? p.thumbnails.first.url.toString()
          : null;
      return {
        'ytid': p.id.toString(),
        'title': p.title,
        if (thumb != null) 'image': thumb,
        'source': 'youtube',
        'list': <Map<String, dynamic>>[],
      };
    }).toList();
  }

  Future<String?> _getLiveUrl(String songId, {bool useProxy = false}) async {
    try {
      final streamUrl = await _client(forceProxy: useProxy)
          .videos
          .streamsClient
          .getHttpLiveStreamUrl(VideoId(songId));
      return streamUrl;
    } catch (_) {
      if (proxyPoolEnabled) {
        return _proxyManager.getStreamUrlWithProxy(
          songId,
          isLive: true,
          quality: defaultQuality,
        );
      }
      rethrow;
    }
  }

  Future<String?> getSongUrl(
    String songId, {
    bool isLive = false,
    String? quality,
    bool useProxy = false,
  }) async {
    final resolvedQuality = quality ?? defaultQuality;
    if (isLive) {
      return _getLiveUrl(songId, useProxy: useProxy);
    }

    final cacheKey =
        'song_${songId}_${resolvedQuality}_${useProxy ? 'proxy' : 'direct'}_url';
    final cached = cache.get<String>(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      final isValid = await _validateUrl(cached);
      if (isValid) return cached;
      cache.invalidate(cacheKey);
    }

    StreamManifest? manifest;
    try {
      manifest = await _client(forceProxy: useProxy)
          .videos
          .streams
          .getManifest(songId, ytClients: [YoutubeApiClient.androidVr])
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      manifest = null;
    }

    // If manifest failed and proxy pool is enabled, try rotating proxies.
    if (manifest == null && proxyPoolEnabled) {
      final proxyUrl =
          await _proxyManager.getStreamUrlWithProxy(songId, isLive: false, quality: resolvedQuality);
      if (proxyUrl != null) {
        cache.set(cacheKey, proxyUrl, streamCacheDuration);
        return proxyUrl;
      }
    }

    if (manifest == null) return null;

    final audioStreams = manifest.audioOnly;
    if (audioStreams.isEmpty) return null;

    final selected = _selectAudioQuality(audioStreams.sortByBitrate(), resolvedQuality);
    final url = selected.url.toString();
    cache.set(cacheKey, url, streamCacheDuration);
    return url;
  }

  AudioStreamInfo _selectAudioQuality(
    List<AudioStreamInfo> sources,
    String quality,
  ) {
    final q = quality.toLowerCase();
    if (q == 'low') return sources.last;
    if (q == 'medium') return sources[sources.length ~/ 2];
    return sources.withHighestBitrate();
  }

  Future<bool> _validateUrl(String url) async {
    try {
      final res = await http.head(Uri.parse(url)).timeout(
        const Duration(seconds: 6),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    try {
      _directClient.close();
    } catch (_) {}
    try {
      _proxyClient?.close();
    } catch (_) {}
  }
}
