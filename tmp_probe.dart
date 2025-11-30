import 'lib/services/youtube_service.dart';
import 'dart:io';

Future<void> main() async {
  final yt = YoutubeService(proxyUrl: Platform.environment['PROXY_URL']);
  final queries = [
    'Top 100 Global',
    'Trending Worldwide',
    "Today\'s Biggest Hits",
    'New Released Tracks',
    'Hotlist Internacional',
    'Pop Hits 2025',
    'Best Pop Music',
    'Pop Rising',
    'Viral Pop',
    'Éxitos Latinos',
  ];
  for (final q in queries) {
    try {
      final found = await yt.searchPlaylistsOnline(q);
      final first = found.isNotEmpty ? found.first : null;
      stdout.writeln('Query: $q -> ${found.length}${first != null ? ' | first: ${first['ytid']} | ${first['title']}' : ''}');
    } catch (e, st) {
      stdout.writeln('Query: $q error: $e');
    }
  }
}
