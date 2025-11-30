import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_swagger_ui/shelf_swagger_ui.dart';

import 'package:orpheus_dart/config/env.dart';
import 'package:orpheus_dart/repositories/user_repository.dart';
import 'package:orpheus_dart/repositories/home_repository.dart';
import 'package:orpheus_dart/repositories/media_repository.dart';
import 'package:orpheus_dart/routes/api_router.dart';
import 'package:orpheus_dart/services/lyrics_service.dart';
import 'package:orpheus_dart/services/mongo_service.dart';
import 'package:orpheus_dart/services/recommendation_service.dart';
import 'package:orpheus_dart/services/sponsorblock_service.dart';
import 'package:orpheus_dart/services/youtube_service.dart';

void main(List<String> args) async {
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  final config = AppConfig.load();
  if (config.mongoUri.isEmpty) {
    print('Missing MONGO_URI env var. Set it before running the server.');
    exit(1);
  }

  final mongo = MongoService(config.mongoUri);
  final youtube = YoutubeService(
    proxyUrl: config.proxyUrl,
    proxyPoolEnabled: config.proxyPoolEnabled,
  );
  final users = UserRepository(mongo);
  final home = HomeRepository(mongo);
  final mediaRepo = MediaRepository(mongo);
  final recommendationService = RecommendationService(users, youtube, mediaRepo);
  final sponsorBlock = SponsorBlockService();
  final lyrics = LyricsService();

  final router = ApiRouter(
    config: config,
    youtube: youtube,
    users: users,
    recommendations: recommendationService,
    sponsorBlock: sponsorBlock,
    lyrics: lyrics,
    home: home,
    media: mediaRepo,
  ).build();

  // Serve OpenAPI spec and Swagger UI
  final swaggerHandler = SwaggerUI(
    'openapi.yaml',
    title: 'Orpheus API Docs',
    deepLink: true,
  );

  // Configure a pipeline that logs requests and enables CORS.
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler((request) {
        final path = request.url.path;
        if (path.startsWith('docs')) {
          return swaggerHandler(request);
        }
        return router(request);
      });

  // For running in containers, we respect the PORT environment variable.
  final port = config.port;
  final server = await serve(handler, ip, port);
  print('Server listening on port ${server.port}');
}
