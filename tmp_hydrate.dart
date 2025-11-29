import "dart:convert";
import "package:orpheus_dart/services/youtube_service.dart";
import "package:orpheus_dart/data/curated_home.dart";

Future<void> main() async {
  final yt = YoutubeService(proxyUrl: null, proxyPoolEnabled: false);
  final data = await hydrateCuratedHome(yt, forceRefresh: true);
  print(jsonEncode(data));
  await yt.dispose();
}
