import 'dart:io';

import 'package:dotenv/dotenv.dart';

class AppConfig {
  AppConfig._(
    this.port,
    this.mongoUri,
    this.proxyUrl,
    this.streamMode,
    this.proxyPoolEnabled,
    this.useYtDlp,
    this.ytDlpPath,
    this.downloadTimeoutSec,
    this.downloadMaxConcurrent,
    this.ytDlpUserAgent,
  );

  final int port;
  final String mongoUri;
  final String? proxyUrl;
  final String streamMode; // redirect | proxy | url
  final bool proxyPoolEnabled;
  final bool useYtDlp;
  final String ytDlpPath;
  final int downloadTimeoutSec;
  final int downloadMaxConcurrent;
  final String? ytDlpUserAgent;

  factory AppConfig.manual({
    required int port,
    required String mongoUri,
    String? proxyUrl,
    String streamMode = 'redirect',
    bool proxyPoolEnabled = true,
    bool useYtDlp = true,
    String ytDlpPath = 'yt-dlp',
    int downloadTimeoutSec = 240,
    int downloadMaxConcurrent = 3,
    String? ytDlpUserAgent,
  }) => AppConfig._(
    port,
    mongoUri,
    proxyUrl,
    streamMode,
    proxyPoolEnabled,
    useYtDlp,
    ytDlpPath,
    downloadTimeoutSec,
    downloadMaxConcurrent,
    ytDlpUserAgent,
  );

  static AppConfig load() {
    final dotEnv = DotEnv(includePlatformEnvironment: true);
    // Only load .env if it exists to avoid noisy "[dotenv] Load failed" logs.
    if (File('.env').existsSync()) {
      dotEnv.load();
    }

    String? read(String key) => dotEnv.isDefined(key) ? dotEnv[key] : null;

    String? envOrDot(String key) {
      final platformValue = Platform.environment[key];
      if (platformValue != null) return platformValue;
      return read(key);
    }

    final port = int.tryParse(envOrDot('PORT') ?? '') ?? 8080;
    final mongoUri = envOrDot('MONGO_URI') ?? '';
    final proxyUrl = envOrDot('PROXY_URL');
    final streamMode = (envOrDot('STREAM_MODE') ?? 'redirect').toLowerCase();
    final proxyPoolEnabled =
        (envOrDot('PROXY_POOL_ENABLED') ?? 'true').toLowerCase() == 'true';
    final useYtDlp = (envOrDot('USE_YTDLP') ?? 'true').toLowerCase() == 'true';
    final ytDlpPath = envOrDot('YTDLP_PATH')?.trim();
    final downloadTimeoutSec =
        int.tryParse(envOrDot('DOWNLOAD_TIMEOUT_SEC') ?? '') ?? 240;
    final downloadMaxConcurrent =
        int.tryParse(envOrDot('DOWNLOAD_MAX_CONCURRENT') ?? '') ?? 3;
    final ytDlpUserAgent = envOrDot('YTDLP_USER_AGENT');

    return AppConfig._(
      port,
      mongoUri,
      proxyUrl?.isEmpty == true ? null : proxyUrl,
      streamMode,
      proxyPoolEnabled,
      useYtDlp,
      (ytDlpPath == null || ytDlpPath.isEmpty) ? 'yt-dlp' : ytDlpPath,
      downloadTimeoutSec,
      downloadMaxConcurrent,
      ytDlpUserAgent?.isEmpty == true ? null : ytDlpUserAgent,
    );
  }
}
