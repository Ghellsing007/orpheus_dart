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
  int count(List list) => list.where((e) => (e as Map)['ytid'] != null && ((e as Map)['ytid'] as String).isNotEmpty).length;
  print('Artists: ${count(List.from(doc['artists'] ?? []))}/${curatedArtistNames.length}');
  print('Trending: ${count(List.from(doc['trending'] ?? []))}/${curatedTrendingNames.length}');
  print('Featured: ${count(List.from(doc['featuredPlaylists'] ?? []))}/${curatedFeaturedPlaylistNames.length}');
  print('Mood: ${(doc['moodPlaylists'] as List? ?? []).length}/${curatedMoodSeeds.length}');
  print('Status: ${doc['status']}');
  if ((doc['artists'] as List).isNotEmpty) print('Ej artista: ${(doc['artists'] as List).first}');
  if ((doc['trending'] as List).isNotEmpty) print('Ej trending: ${(doc['trending'] as List).first}');
  if ((doc['featuredPlaylists'] as List).isNotEmpty) print('Ej playlist: ${(doc['featuredPlaylists'] as List).first}');
}
