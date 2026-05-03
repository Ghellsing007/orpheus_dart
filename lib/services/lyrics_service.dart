import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class LyricsService {
  Future<String?> fetchLyrics(String artistName, String title) async {
    final cleanTitle = title.replaceAll('Lyrics', '').replaceAll('Karaoke', '');

    // Try lrclib first (has synced lyrics!)
    final lyricsFromLrclib = await _fetchLyricsFromLrclib(artistName, cleanTitle);
    if (lyricsFromLrclib != null) return lyricsFromLrclib;

    final lyricsFromGoogle = await _fetchLyricsFromGoogle(artistName, cleanTitle);
    if (lyricsFromGoogle != null) return lyricsFromGoogle;

    final lyricsFromParolesNet = await _fetchLyricsFromParolesNet(
      artistName.split(',')[0],
      cleanTitle,
    );
    if (lyricsFromParolesNet != null) return lyricsFromParolesNet;

    final lyricsFromLyricsMania = await _fetchLyricsFromLyricsMania(
      artistName,
      cleanTitle,
    );
    return lyricsFromLyricsMania;
  }

  Future<String?> _fetchLyricsFromLrclib(
    String artistName,
    String title,
  ) async {
    try {
      // Try with specific parameters first
      final searchUrl = Uri.parse(
        'https://lrclib.net/api/get?artist_name=${Uri.encodeComponent(artistName)}&track_name=${Uri.encodeComponent(title)}',
      );
      var response = await http.get(searchUrl).timeout(const Duration(seconds: 10));
      
      // If no result, try with combined query
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['id'] == null) {
          // Not found, try search
          final q = '$artistName $title';
          final searchUri = Uri.parse(
            'https://lrclib.net/api/search?q=${Uri.encodeComponent(q)}',
          );
          response = await http.get(searchUri).timeout(const Duration(seconds: 10));
          
          if (response.statusCode == 200) {
            final searchResults = jsonDecode(response.body) as List<dynamic>;
            if (searchResults.isNotEmpty) {
              // Get first result
              final first = searchResults[0] as Map<String, dynamic>;
              final getUri = Uri.parse(
                'https://lrclib.net/api/get?id=${first['id']}',
              );
              response = await http.get(getUri).timeout(const Duration(seconds: 10));
            }
          }
        }
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        // Try synced lyrics first
        final synced = data['syncedLyrics'] as String?;
        if (synced != null && synced.isNotEmpty) {
          return _formatSyncedLyrics(synced);
        }
        
        // Fall back to plain lyrics
        final plain = data['plainLyrics'] as String?;
        if (plain != null && plain.isNotEmpty) {
          return plain;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _formatSyncedLyrics(String synced) {
    // Convert [mm:ss.xx]line format to plain text with metadata
    final lines = synced.split('\n');
    final formatted = StringBuffer();
    
    for (final line in lines) {
      // Match [00:12.34] or [00:12] format
      final match = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]').firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millis = match.group(3) != null 
          ? int.parse(match.group(3)!.padRight(3, '0').substring(0, 3))
          : 0;
        final timeMs = (minutes * 60 * 1000) + (seconds * 1000) + millis;
        final text = line.substring(match.end).trim();
        
        if (text.isNotEmpty) {
          formatted.writeln('[$timeMs]$text');
        }
      } else {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          formatted.writeln(trimmed);
        }
      }
    }
    
    return formatted.toString().trim();
  }

  Future<String?> _fetchLyricsFromGoogle(
    String artistName,
    String title,
  ) async {
    const url =
        'https://www.google.com/search?client=safari&rls=en&ie=UTF-8&oe=UTF-8&q=';
    const delimiter1 =
        '</div></div></div></div><div class="hwc"><div class="BNeawe tAd8D AP7Wnd"><div><div class="BNeawe tAd8D AP7Wnd">';
    const delimiter2 =
        '</div></div></div></div></div><div><span class="hwc"><div class="BNeawe uEec3 AP7Wnd">';

    try {
      final res = await http
          .get(Uri.parse(Uri.encodeFull('$url$artistName - $title lyrics')))
          .timeout(const Duration(seconds: 10));
      final body = res.body;
      if (!body.contains(delimiter1) || !body.contains(delimiter2)) return null;
      final lyricsRes = body.substring(
        body.indexOf(delimiter1) + delimiter1.length,
        body.lastIndexOf(delimiter2),
      );
      if (lyricsRes.contains('<meta charset="UTF-8">')) return null;
      if (lyricsRes.contains('please enable javascript on your web browser')) {
        return null;
      }
      if (lyricsRes.contains('Error 500 (Server Error)')) return null;
      if (lyricsRes.contains(
        'systems have detected unusual traffic from your computer network',
      )) {
        return null;
      }
      return lyricsRes;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchLyricsFromParolesNet(
    String artistName,
    String title,
  ) async {
    try {
      final uri = Uri.parse(
        'https://www.paroles.net/${_lyricsUrl(artistName)}/paroles-${_lyricsUrl(title)}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        final songTextElements = document.querySelectorAll('.song-text');

        if (songTextElements.isNotEmpty) {
          final lyricsLines = songTextElements.first.text.split('\n');
          if (lyricsLines.length > 1) {
            lyricsLines.removeAt(0);

            final finalLyrics = addCopyright(
              lyricsLines.join('\n'),
              'www.paroles.net',
            );
            return _removeSpaces(finalLyrics);
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchLyricsFromLyricsMania(
    String artistName,
    String title,
  ) async {
    try {
      final uri = Uri.parse(
        'https://www.lyricsmania.com/${_lyricsManiaUrl(title)}_lyrics_${_lyricsManiaUrl(artistName)}.html',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        final lyricsBodyElements = document.querySelectorAll('.lyrics-body');

        if (lyricsBodyElements.isNotEmpty) {
          return addCopyright(
            lyricsBodyElements.first.text,
            'www.lyricsmania.com',
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _lyricsUrl(String input) {
    var result = input.replaceAll(' ', '-').toLowerCase();
    if (result.isNotEmpty && result.endsWith('-')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  String _lyricsManiaUrl(String input) {
    var result = input.replaceAll(' ', '_').toLowerCase();
    if (result.isNotEmpty && result.startsWith('_')) {
      result = result.substring(1);
    }
    if (result.isNotEmpty && result.endsWith('_')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  String _removeSpaces(String input) {
    return input.replaceAll('  ', '');
  }

  String addCopyright(String input, String copyright) {
    return '$input\n\n\u00a9 $copyright';
  }
}
