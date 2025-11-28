import 'dart:io';

import 'package:dotenv/dotenv.dart';

class AppConfig {
  AppConfig._(this.port, this.mongoUri, this.proxyUrl, this.streamMode);

  final int port;
  final String mongoUri;
  final String? proxyUrl;
  final String streamMode; // redirect | proxy | url

  factory AppConfig.manual({
    required int port,
    required String mongoUri,
    String? proxyUrl,
    String streamMode = 'redirect',
  }) =>
      AppConfig._(port, mongoUri, proxyUrl, streamMode);

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

    return AppConfig._(port, mongoUri, proxyUrl?.isEmpty == true ? null : proxyUrl, streamMode);
  }
}
