import "dart:io";
import 'package:dotenv/dotenv.dart';
import 'package:orpheus_dart/config/env.dart';
import 'package:orpheus_dart/data/curated_home.dart';
import 'package:orpheus_dart/repositories/home_repository.dart';
import 'package:orpheus_dart/repositories/media_repository.dart';
import 'package:orpheus_dart/services/mongo_service.dart';
import 'package:orpheus_dart/services/youtube_service.dart';

Future<void> main() async {
  final dotEnv = DotEnv(includePlatformEnvironment: true)..load();
  final config = AppConfig.load();
  final mongoUri = config.mongoUri.isNotEmpty ? config.mongoUri : (dotEnv['MONGO_URI'] ?? '');
  if (mongoUri.isEmpty) {
    print('No MONGO_URI configurado.');
    exit(1);
  }
  final mongo = MongoService(mongoUri);
  final repo = HomeRepository(mongo);
  final media = MediaRepository(mongo);
  final yt = YoutubeService(proxyUrl: config.proxyUrl, proxyPoolEnabled: config.proxyPoolEnabled);

  bool progress = true;
  int attempts = 0;
  while (progress && attempts < 15) {
    progress = false;
    attempts++;
    for (final entry in [
      ['artists', 5, curatedArtistNames.length],
      ['trending', 5, curatedTrendingNames.length],
      ['featured', 4, curatedFeaturedPlaylistSeeds.length],
      ['mood', 4, curatedMoodSeeds.length],
    ]) {
      final section = entry[0] as String;
      final limit = entry[1] as int;
      final total = entry[2] as int;
      final docBefore = await repo.getOrSeed();
      final statusKey = section.startsWith('feature')
          ? 'featuredPlaylists'
          : section.startsWith('mood')
              ? 'moodPlaylists'
              : section;
      final beforeCount = (docBefore['status'] as Map<String, dynamic>? ?? {})[statusKey] as int? ?? 0;
      await hydrateCuratedChunk(
        yt,
        repo,
        media,
        section: section,
        limit: limit,
      );
      final afterDoc = await repo.getOrSeed();
      final afterCount = (afterDoc['status'] as Map<String, dynamic>? ?? {})[statusKey] as int? ?? 0;
      if (afterCount > beforeCount) {
        progress = true;
        print('[$section] avance $beforeCount -> $afterCount de $total');
      }
    }
  }

  final doc = await repo.getOrSeed();
  final status = Map<String, dynamic>.from(doc['status'] ?? {});

  print('Resumen final:');
  print('Artists: ${status['artists'] ?? 0}/${curatedArtistNames.length}');
  print('Trending: ${status['trending'] ?? 0}/${curatedTrendingNames.length}');
  print('Featured: ${status['featuredPlaylists'] ?? 0}/${curatedFeaturedPlaylistSeeds.length}');
  print('Mood: ${status['moodPlaylists'] ?? 0}/${curatedMoodSeeds.length}');

  final sections = await repo.getSections();
  if (sections.isNotEmpty) {
    print('Secciones cargadas: ${sections.map((s) => s.type.name).join(', ')}');
  }

  await yt.dispose();
}
