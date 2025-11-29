import "dart:convert";
import 'package:dotenv/dotenv.dart';
import 'package:orpheus_dart/config/env.dart';
import 'package:orpheus_dart/services/mongo_service.dart';
import 'package:orpheus_dart/services/youtube_service.dart';
import 'package:orpheus_dart/repositories/home_repository.dart';
import 'package:orpheus_dart/data/curated_home.dart';

Future<void> main() async {
  final dotEnv = DotEnv(includePlatformEnvironment: true)..load();
  final config = AppConfig.load();
  final mongoUri = config.mongoUri.isNotEmpty ? config.mongoUri : (dotEnv['MONGO_URI'] ?? '');
  if (mongoUri.isEmpty) {
    print('No MONGO_URI configurado');
    return;
  }
  final mongo = MongoService(mongoUri);
  final repo = HomeRepository(mongo);
  final yt = YoutubeService(proxyUrl: config.proxyUrl, proxyPoolEnabled: config.proxyPoolEnabled);

  final sections = [
    ['artists', 5],
    ['trending', 5],
    ['featured', 4],
    ['mood', 4],
  ];

  for (final s in sections) {
    final section = s[0] as String;
    final limit = s[1] as int;
    print('Hydrating section: $section limit=$limit');
    try {
      final data = await hydrateCuratedChunk(yt, repo, section: section, limit: limit);
      print('Section $section status: ${(data['status'] ?? {}).toString()}');
    } catch (e) {
      print('Error section $section: $e');
    }
  }

  final doc = await repo.getOrSeed();
  print('Final cached keys: ${doc.keys}');
  print('Artists loaded: ${(doc['artists'] as List).where((e) => e['ytid'] != null).length}/${curatedArtistNames.length}');
  print('Trending loaded: ${(doc['trending'] as List).where((e) => e['ytid'] != null).length}/${curatedTrendingNames.length}');
  print('Featured loaded: ${(doc['featuredPlaylists'] as List).where((e) => e['ytid'] != null).length}/${curatedFeaturedPlaylistNames.length}');
  print('Mood loaded: ${(doc['moodPlaylists'] as List).length}/${curatedMoodSeeds.length}');

  await yt.dispose();
}
