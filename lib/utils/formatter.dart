import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final wordsPatternForSongTitle = RegExp(
  r'\b(official music video|official lyric video|official lyrics video|official video|official 4k video|official audio|lyric video|lyrics video|official hd video|lyric visualizer|lyric vizualizer|official visualizer|lyrics|lyric|official song clip)\b',
  caseSensitive: false,
);

final replacementsForSongTitle = {
  '[': '',
  ']': '',
  '(': '',
  ')': '',
  '|': '',
  '&amp;': '&',
  '&#039;': "'",
  '&quot;': '"',
};

String formatSongTitle(String title) {
  final pattern = RegExp(
    replacementsForSongTitle.keys.map(RegExp.escape).join('|'),
  );

  var finalTitle =
      title
          .replaceAllMapped(
            pattern,
            (match) => replacementsForSongTitle[match.group(0)] ?? '',
          )
          .trimLeft();

  finalTitle = finalTitle.replaceAll(wordsPatternForSongTitle, '');

  return finalTitle;
}

Map<String, dynamic> returnSongLayout(
  int index,
  Video song, {
  String? playlistImage,
}) =>
    {
      'id': index,
      'ytid': song.id.toString(),
      'title': formatSongTitle(
        song.title.split('-')[song.title.split('-').length - 1],
      ),
      'artist': song.title.split('-')[0],
      'image': playlistImage ?? song.thumbnails.standardResUrl,
      'lowResImage': playlistImage ?? song.thumbnails.lowResUrl,
      'highResImage': playlistImage ?? song.thumbnails.maxResUrl,
      'duration': song.duration?.inSeconds,
      'isLive': song.isLive,
    };

String formatDuration(int audioDurationInSeconds) {
  final duration = Duration(seconds: audioDurationInSeconds);

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  return [
    if (hours > 0) hours.toString().padLeft(2, '0'),
    minutes.toString().padLeft(2, '0'),
    seconds.toString().padLeft(2, '0'),
  ].join(':');
}
