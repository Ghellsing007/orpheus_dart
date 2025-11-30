import 'dart:convert';

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
    print('No MONGO_URI configurado');
    return;
  }

  final mongo = MongoService(mongoUri);
  final home = HomeRepository(mongo);
  final media = MediaRepository(mongo);
  final yt = YoutubeService(proxyUrl: config.proxyUrl, proxyPoolEnabled: config.proxyPoolEnabled);

  final data = await hydrateCuratedHome(
    yt,
    home,
    media,
    forceRefresh: true,
  );
  print(jsonEncode(data));

  await yt.dispose();
  await mongo.close();
}
