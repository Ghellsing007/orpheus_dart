import "dart:io";
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
    print('No MONGO_URI configurado.');
    exit(1);
  }
  final mongo = MongoService(mongoUri);
  final repo = HomeRepository(mongo);
  final yt = YoutubeService(proxyUrl: config.proxyUrl, proxyPoolEnabled: config.proxyPoolEnabled);

  Future<int> _countLoaded(List list) => Future.value(list.where((e) => (e as Map)["ytid"] != null && (e as Map)["ytid"].toString().isNotEmpty).length);

  bool progress = true;
  int attempts = 0;
  while (progress && attempts < 15) {
    progress = false;
    attempts++;
    for (final entry in [
      ['artists', 5, curatedArtistNames.length],
      ['trending', 5, curatedTrendingNames.length],
      ['featured', 4, curatedFeaturedPlaylistNames.length],
      ['mood', 4, curatedMoodSeeds.length],
    ]) {
      final section = entry[0] as String;
      final limit = entry[1] as int;
      final total = entry[2] as int;
      final docBefore = await repo.getOrSeed();
      final listKey = section.startsWith('feature') ? 'featuredPlaylists' : section.startsWith('mood') ? 'moodPlaylists' : section;
      final beforeList = List<Map<String, dynamic>>.from(docBefore[listKey] ?? []);
      final beforeCount = beforeList.where((e) => e['ytid'] != null && (e['ytid'] as String).isNotEmpty).length;
      await hydrateCuratedChunk(yt, repo, section: section, limit: limit);
      final afterDoc = await repo.getOrSeed();
      final afterList = List<Map<String, dynamic>>.from(afterDoc[listKey] ?? []);
      final afterCount = afterList.where((e) => e['ytid'] != null && (e['ytid'] as String).isNotEmpty).length;
      if (afterCount > beforeCount) {
        progress = true;
        print('[${section}] avance ${beforeCount} -> ${afterCount} de ${total}');
      }
    }
  }

  final doc = await repo.getOrSeed();
  final artistsLoaded = await _countLoaded(List.from(doc['artists'] ?? []));
  final trendingLoaded = await _countLoaded(List.from(doc['trending'] ?? []));
  final featuredLoaded = await _countLoaded(List.from(doc['featuredPlaylists'] ?? []));
  final moodLoaded = (doc['moodPlaylists'] as List? ?? []).length;

  print('Resumen final:');
  print('Artists: $artistsLoaded/${curatedArtistNames.length}');
  print('Trending: $trendingLoaded/${curatedTrendingNames.length}');
  print('Featured: $featuredLoaded/${curatedFeaturedPlaylistNames.length}');
  print('Mood: $moodLoaded/${curatedMoodSeeds.length}');

  // Muestra ejemplos
  if ((doc['artists'] as List).isNotEmpty) {
    print('Ejemplo artista: ${(doc['artists'] as List).first}');
  }
  if ((doc['trending'] as List).isNotEmpty) {
    print('Ejemplo trending: ${(doc['trending'] as List).first}');
  }
  if ((doc['featuredPlaylists'] as List).isNotEmpty) {
    print('Ejemplo playlist: ${(doc['featuredPlaylists'] as List).first}');
  }

  await yt.dispose();
}
