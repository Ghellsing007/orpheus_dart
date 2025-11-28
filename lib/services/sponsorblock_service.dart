import 'dart:convert';

import 'package:http/http.dart' as http;

class SponsorBlockService {
  Future<List<Map<String, int>>> getSkipSegments(String videoId) async {
    try {
      final uri = Uri(
        scheme: 'https',
        host: 'sponsor.ajay.app',
        path: '/api/skipSegments',
        queryParameters: {
          'videoID': videoId,
          'category': [
            'sponsor',
            'selfpromo',
            'interaction',
            'intro',
            'outro',
            'music_offtopic',
          ],
          'actionType': 'skip',
        },
      );

      final res = await http.get(uri);
      if (res.statusCode != 200 || res.body == 'Not Found') return [];
      final data = jsonDecode(res.body) as List<dynamic>;
      return data.map<Map<String, int>>((obj) {
        final segment = (obj['segment'] as List);
        final start = (segment.first as num).toInt();
        final end = (segment.last as num).toInt();
        return {'start': start, 'end': end};
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
