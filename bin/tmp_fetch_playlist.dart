import 'dart:io';

import 'package:orpheus_dart/services/youtube_service.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/tmp_fetch_playlist.dart <playlistId>');
    exit(1);
  }
  final playlistId = args.first;
  final service = YoutubeService(proxyUrl: null, proxyPoolEnabled: false);
  try {
    final playlist = await service.getPlaylistInfo(playlistId);
    print(playlist);
  } catch (err, stack) {
    print('Error fetching playlist: $err');
    print(stack);
  } finally {
    await service.dispose();
  }
}
