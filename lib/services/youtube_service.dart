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
const Duration channelCacheDuration = Duration(hours: 3);
const Duration streamCacheDuration = Duration(hours: 3);
const int minSongDurationSec = 90; // Evita shorts/teasers demasiado cortos en toda la API

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
    final songs = results
        .whereType<Video>()
        .where((video) => _isDurationValid(video))
        .map((video) => returnSongLayout(0, video))
        .toList();
    cache.set(cacheKey, songs, searchCacheDuration);
    return songs;
  }

  Future<List<Map<String, dynamic>>> searchChannels(String query) async {
    final cacheKey = 'channel_search_$query';
    final cached = cache.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null) return cached;

    final results = await _client()
        .search
        .searchContent(
          query,
          filter: TypeFilters.channel,
        )
        .timeout(const Duration(seconds: 12));

    final channels = results.whereType<SearchChannel>().map((channel) {
      final thumb = channel.thumbnails.isNotEmpty ? _sanitizeThumb(channel.thumbnails.first.url.toString()) : null;
      return {
        'id': channel.id.value,
        'ytid': channel.id.value,
        'title': channel.name,
        'name': channel.name,
        'description': channel.description,
        if (thumb != null) 'image': thumb,
      };
    }).toList();

    cache.set(cacheKey, channels, searchCacheDuration);
    return channels;
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
    int minDurationSec = minSongDurationSec,
  }) async {
    final cacheKey = 'playlistSongs_$playlistId';
    final cached = cache.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null) return cached;

    final songList = <Map<String, dynamic>>[];
    await for (final song in _client().playlists.getVideos(playlistId)) {
      if (!_isDurationValid(song, minDurationSec: minDurationSec)) continue;
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
      minDurationSec: minSongDurationSec,
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
    final related = await _client().videos.getRelatedVideos(song) ?? <Video>[];
    return related
        .where(_isDurationValid)
        .map((s) => returnSongLayout(0, s))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getChannelSongs(
    String channelId, {
    int limit = 30,
    int minDurationSec = minSongDurationSec,
    String? channelTitle,
  }) async {
    final cacheKey = 'channelSongs_${channelId}_$limit';
    final cached = cache.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null) return cached;

    final uploads = <Map<String, dynamic>>[];
    try {
      await for (final video in _client().channels.getUploads(channelId)) {
        if (!_isDurationValid(video, minDurationSec: minDurationSec)) continue; // evita shorts/teasers muy cortos
        uploads.add(_channelSongLayout(uploads.length, video, channelTitle: channelTitle));
        if (uploads.length >= limit) break;
      }
    } catch (_) {}

    cache.set(cacheKey, uploads, channelCacheDuration);
    return uploads;
  }

  Future<Map<String, dynamic>> getChannelDetails(String channelId) async {
    final cacheKey = 'channel_$channelId';
    final cached = cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    Channel? channel;
    ChannelAbout? about;
    try {
      channel = await _client().channels.get(channelId).timeout(const Duration(seconds: 12));
      about = await _client().channels.getAboutPage(channelId).timeout(const Duration(seconds: 12));
    } catch (_) {}

    final topSongs = await getChannelSongs(
      channelId,
      limit: 20,
      minDurationSec: minSongDurationSec,
      channelTitle: channel?.title ?? about?.title,
    );

    List<Map<String, dynamic>> playlists = <Map<String, dynamic>>[];
    try {
      if (channel != null) {
        playlists = await searchPlaylistsOnline(channel.title);
      }
    } catch (_) {}

    String? aboutThumb;
    if (about != null && about.thumbnails.isNotEmpty) {
      aboutThumb = _sanitizeThumb(about.thumbnails.first.url.toString());
    }

    final map = {
      'id': channelId,
      'ytid': channelId,
      'title': channel?.title ?? about?.title ?? channelId,
      'name': channel?.title ?? about?.title ?? channelId,
      'handle': null,
      'image': channel?.logoUrl ?? aboutThumb,
      'banner': channel?.bannerUrl,
      'subscribers': channel?.subscribersCount,
      'description': about?.description,
      'topSongs': topSongs,
      'playlists': playlists,
      'related': <Map<String, dynamic>>[],
    };

    cache.set(cacheKey, map, channelCacheDuration);
    return map;
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

  bool _isDurationValid(
    Video song, {
    int minDurationSec = minSongDurationSec,
  }) {
    final duration = song.duration?.inSeconds;
    if (duration == null) return false;
    return duration >= minDurationSec;
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

  Map<String, dynamic> _channelSongLayout(
    int index,
    Video song, {
    String? channelTitle,
  }) {
    return {
      'id': index,
      'ytid': song.id.toString(),
      'title': formatSongTitle(song.title),
      'artist': channelTitle ?? song.author,
      'image': song.thumbnails.standardResUrl,
      'lowResImage': song.thumbnails.lowResUrl,
      'highResImage': song.thumbnails.maxResUrl,
      'duration': song.duration?.inSeconds,
      'isLive': song.isLive,
    };
  }

  String? _sanitizeThumb(String? url) {
    if (url == null) return null;
    if (url.startsWith('https:https://')) return url.replaceFirst('https:', '');
    return url;
  }
}
