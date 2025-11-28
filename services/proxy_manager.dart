import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Lightweight proxy rotator inspired by Musify.
/// Fetches public HTTPS proxies and tries them until one returns a manifest.
class ProxyManager {
  ProxyManager._(this.enabled);

  static ProxyManager? _instance;

  factory ProxyManager({bool enabled = true}) {
    _instance ??= ProxyManager._(enabled);
    return _instance!;
  }

  final bool enabled;
  final _goodProxies = <String>{};
  final _pool = <String>{};
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  final _rand = Random();

  bool _isValid(String proxy) =>
      RegExp(r'^\\d+\\.\\d+\\.\\d+\\.\\d+:\\d+\$').hasMatch(proxy.trim());

  Future<void> _ensurePool() async {
    if (!enabled) return;
    final shouldRefetch =
        _pool.isEmpty || DateTime.now().difference(_lastFetch).inMinutes >= 60;
    if (shouldRefetch) {
      await _fetchProxies();
    }
  }

  Future<void> _fetchProxies() async {
    if (!enabled) return;
    _pool.clear();
    final tasks = [
      _fetchSpysMe(),
      _fetchProxyScrape(),
      _fetchOpenProxyList(),
    ];
    await Future.wait(tasks);
    _pool.addAll(_goodProxies); // seed with known-good proxies
    _lastFetch = DateTime.now();
  }

  String? _pickProxy(Set<String> tried) {
    final candidates = _goodProxies.isNotEmpty ? _goodProxies : _pool;
    final available = candidates.where((p) => !tried.contains(p)).toList();
    if (available.isEmpty) return null;
    return available[_rand.nextInt(available.length)];
  }

  Future<YoutubeExplode?> _buildClient(String proxy, int timeoutSeconds) async {
    if (!enabled) return null;
    try {
      final httpClient = HttpClient()
        ..connectionTimeout = Duration(seconds: timeoutSeconds)
        ..findProxy = (_) => 'PROXY $proxy; DIRECT'
        ..badCertificateCallback = (_, __, ___) => false;
      final ioClient = IOClient(httpClient);
      return YoutubeExplode(YoutubeHttpClient(ioClient));
    } catch (_) {
      return null;
    }
  }

  /// Try to get a stream URL via a proxy. Returns null if none worked.
  Future<String?> getStreamUrlWithProxy(
    String songId, {
    required bool isLive,
    required String quality,
    int maxAttempts = 6,
  }) async {
    if (!enabled) return null;
    await _ensurePool();
    final tried = <String>{};

    for (var i = 0; i < maxAttempts; i++) {
      final proxy = _pickProxy(tried);
      if (proxy == null) break;
      tried.add(proxy);

      YoutubeExplode? yt;
      try {
        yt = await _buildClient(proxy, 6);
        if (yt == null) continue;

        String url;
        if (isLive) {
          url = await yt.videos.streamsClient
              .getHttpLiveStreamUrl(VideoId(songId));
        } else {
          final manifest = await yt.videos.streams
              .getManifest(songId, ytClients: [YoutubeApiClient.androidVr])
              .timeout(const Duration(seconds: 10));
          final audioStreams = manifest.audioOnly;
          if (audioStreams.isEmpty) continue;
          url = _selectAudioQuality(audioStreams, quality).url.toString();
        }
        _goodProxies.add(proxy);
        return url;
      } catch (_) {
        _goodProxies.remove(proxy);
        continue;
      } finally {
        try {
          yt?.close();
        } catch (_) {}
      }
    }
    return null;
  }

  // --- Proxy sources ---

  Future<void> _fetchSpysMe() async {
    if (!enabled) return;
    try {
      const url = 'https://spys.me/proxy.txt';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      for (final line in res.body.split('\\n')) {
        final match = RegExp(
                r'(?<ip>\\d+\\.\\d+\\.\\d+\\.\\d+):(?<port>\\d+)\\s(?<country>[A-Z]{2})')
            .firstMatch(line);
        if (match != null) {
          final proxy = '${match.namedGroup('ip')}:${match.namedGroup('port')}';
          if (_isValid(proxy)) _pool.add(proxy);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchProxyScrape() async {
    if (!enabled) return;
    try {
      const url =
          'https://api.proxyscrape.com/v4/free-proxy-list/get?request=display_proxies&proxy_format=protocolipport&format=json';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final decoded = res.body;
      for (final match in RegExp(r'"ip":"(\\d+\\.\\d+\\.\\d+\\.\\d+)","port":"(\\d+)"')
          .allMatches(decoded)) {
        final proxy = '${match.group(1)}:${match.group(2)}';
        if (_isValid(proxy)) _pool.add(proxy);
      }
    } catch (_) {}
  }

  Future<void> _fetchOpenProxyList() async {
    if (!enabled) return;
    try {
      const url =
          'https://raw.githubusercontent.com/roosterkid/openproxylist/main/HTTPS.txt';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      for (final line in res.body.split('\\n')) {
        final match =
            RegExp(r'(?<ip>\\d+\\.\\d+\\.\\d+\\.\\d+):(?<port>\\d+)').firstMatch(line);
        if (match != null) {
          final proxy = '${match.namedGroup('ip')}:${match.namedGroup('port')}';
          if (_isValid(proxy)) _pool.add(proxy);
        }
      }
    } catch (_) {}
  }
}

AudioStreamInfo _selectAudioQuality(List<AudioStreamInfo> sources, String quality) {
  final q = quality.toLowerCase();
  if (q == 'low') return sources.last;
  if (q == 'medium') return sources[sources.length ~/ 2];
  return sources.withHighestBitrate();
}
