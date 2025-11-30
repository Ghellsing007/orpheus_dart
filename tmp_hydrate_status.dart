import 'package:orpheus_dart/config/env.dart';
import 'package:dotenv/dotenv.dart';
import 'package:orpheus_dart/services/mongo_service.dart';
import 'package:orpheus_dart/repositories/home_repository.dart';
import 'package:orpheus_dart/data/curated_home.dart';

Future<void> main() async {
  final dotEnv = DotEnv(includePlatformEnvironment: true)..load();
  final config = AppConfig.load();
  final mongoUri = config.mongoUri.isNotEmpty ? config.mongoUri : (dotEnv['MONGO_URI'] ?? '');
  final mongo = MongoService(mongoUri);
  final repo = HomeRepository(mongo);
  final doc = await repo.getOrSeed();
  final sections = await repo.getSections();
  final status = Map<String, dynamic>.from(doc['status'] ?? {});
  print('Artists: ${status['artists'] ?? 0}/${curatedArtistNames.length}');
  print('Trending: ${status['trending'] ?? 0}/${curatedTrendingNames.length}');
  print('Featured: ${status['featuredPlaylists'] ?? 0}/${curatedFeaturedPlaylistNames.length}');
  print('Mood: ${status['moodPlaylists'] ?? 0}/${curatedMoodSeeds.length}');
  print('Status: $status');
  if (sections.isNotEmpty) {
    print('Sections stored: ${sections.map((s) => '${s.type.name}:${s.itemIds.length}/${s.collectionIds.length}').join(', ')}');
  }
}
