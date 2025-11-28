import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:orpheus_dart/config/env.dart';
import 'package:orpheus_dart/repositories/user_repository.dart';
import 'package:orpheus_dart/routes/api_router.dart';
import 'package:orpheus_dart/services/lyrics_service.dart';
import 'package:orpheus_dart/services/mongo_service.dart';
import 'package:orpheus_dart/services/recommendation_service.dart';
import 'package:orpheus_dart/services/sponsorblock_service.dart';
import 'package:orpheus_dart/services/youtube_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// Integration tests hitting real APIs (YouTube, SponsorBlock, Mongo).
// Run manually: RUN_INTEGRATION=true MONGO_URI=... dart test test/api_integration_test.dart -r expanded -j 1
void main() {
  final runIntegration = Platform.environment['RUN_INTEGRATION'] == 'true';
  final dotEnv = DotEnv(includePlatformEnvironment: true)..load();
  final mongoUri = Platform.environment['MONGO_URI'] ?? dotEnv['MONGO_URI'] ?? '';

  if (!runIntegration || mongoUri.isEmpty) {
    print('Skipping integration tests (set RUN_INTEGRATION=true and MONGO_URI)');
    return;
  }

  late Handler handler;
  late YoutubeService yt;
  late MongoService mongo;

  setUpAll(() async {
    final config = AppConfig.load();
    mongo = MongoService(mongoUri);
    yt = YoutubeService(proxyUrl: config.proxyUrl);
    final users = UserRepository(mongo);
    final recs = RecommendationService(users, yt);
    final sponsor = SponsorBlockService();
    final lyrics = LyricsService();

    final router = ApiRouter(
      config: config,
      youtube: yt,
      users: users,
      recommendations: recs,
      sponsorBlock: sponsor,
      lyrics: lyrics,
    ).build();

    handler = const Pipeline().addHandler(router.call);
  });

  tearDownAll(() async {
    await yt.dispose();
    await mongo.close();
  });

  test('search returns live results', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/search?q=the%20weeknd')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    final items = (body['items'] as List);
    print('First search result: ${items.first}');
    expect(items, isNotEmpty);
    expect(items.first['ytid'], isNotEmpty);
  });

  test('playlist detail returns songs', () async {
    // Public music playlist (YouTube official)
    const playlistId = 'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI';
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/playlists/$playlistId')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    final list = (body['list'] as List);
    print('Playlist title: ${body['title']}, songs: ${list.length}');
    expect(body['ytid'], playlistId);
    expect(list, isNotEmpty);
  });

  test('stream redirect returns playable url', () async {
    // Use a known video id
    const songId = 'dQw4w9WgXcQ';
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/songs/$songId/stream?mode=redirect')),
    );
    expect(res.statusCode, 302);
    final location = res.headers['location'];
    print('Redirect location: $location');
    expect(location, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 25)));

  test('lyrics fetch returns something for a popular song', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/lyrics?artist=adele&title=hello')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    print('Lyrics found: ${body['found']} length ${(body['lyrics'] as String?)?.length}');
    expect(body['found'], isTrue);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('sponsorblock returns segments for known video', () async {
    const songId = 'dQw4w9WgXcQ';
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/songs/$songId/segments')),
    );
    final body = jsonDecode(await res.readAsString()) as Map;
    print('Segments: ${body['items']}');
    expect(body['items'], isA<List>());
  });
}
