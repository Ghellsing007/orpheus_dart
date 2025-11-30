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

  var finalTitle = title
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
}) => {
  'id': index,
  'ytid': song.id.toString(),
  'title': formatSongTitle(
    song.title.split('-')[song.title.split('-').length - 1],
  ),
  'artist': song.title.split('-')[0],
  // Prioriza los thumbnails propios; si no hay, cae al thumbnail de la playlist
  // y como último recurso genera uno con el id del video.
  'image':
      _validThumb(song.thumbnails.standardResUrl, song.id) ??
      _validThumb(song.thumbnails.maxResUrl, song.id) ??
      _validThumb(song.thumbnails.lowResUrl, song.id) ??
      'https://img.youtube.com/vi/${song.id}/sddefault.jpg',
  'lowResImage':
      _validThumb(song.thumbnails.lowResUrl, song.id) ??
      _validThumb(song.thumbnails.standardResUrl, song.id) ??
      'https://img.youtube.com/vi/${song.id}/sddefault.jpg',
  'highResImage':
      _validThumb(song.thumbnails.maxResUrl, song.id) ??
      _validThumb(song.thumbnails.standardResUrl, song.id) ??
      'https://img.youtube.com/vi/${song.id}/maxresdefault.jpg',
  'duration': song.duration?.inSeconds,
  'isLive': song.isLive,
};

String? _validThumb(String? url, dynamic videoId) {
  if (url == null) return null;
  final id = videoId.toString();
  final looksLikePlaylist = url.contains('/vi/PL');
  final belongsToVideo = url.contains('/vi/$id');
  if (looksLikePlaylist && !belongsToVideo) return null;
  return url;
}

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
