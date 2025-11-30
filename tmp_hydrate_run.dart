import 'package:dotenv/dotenv.dart';
import 'package:orpheus_dart/config/env.dart';
import 'package:orpheus_dart/data/curated_home.dart';
import 'package:orpheus_dart/models/media_models.dart';
import 'package:orpheus_dart/repositories/home_repository.dart';
import 'package:orpheus_dart/repositories/media_repository.dart';
import 'package:orpheus_dart/services/mongo_service.dart';
import 'package:orpheus_dart/services/youtube_service.dart';

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
  final media = MediaRepository(mongo);
  final yt = YoutubeService(proxyUrl: config.proxyUrl, proxyPoolEnabled: config.proxyPoolEnabled);

  final sectionPlans = [
    ['artists', 5],
    ['trending', 5],
    ['featured', 4],
    ['mood', 4],
  ];

  for (final s in sectionPlans) {
    final section = s[0] as String;
    final limit = s[1] as int;
    print('Hydrating section: $section limit=$limit');
    try {
      final data = await hydrateCuratedChunk(
        yt,
        repo,
        media,
        section: section,
        limit: limit,
      );
      print('Section $section status: ${(data['status'] ?? {}).toString()}');
    } catch (e) {
      print('Error section $section: $e');
    }
  }

  final doc = await repo.getOrSeed();
  final List<HomeSection> sections = await repo.getSections();
  print('Final cached sections: ${sections.map((s) => s.type.name).toList()}');
  print('Status: ${doc['status']}');
  print('Updated at: ${doc['updatedAt']}');

  await yt.dispose();
}
