import '../models/media_models.dart';
import '../repositories/home_repository.dart';
import '../repositories/media_repository.dart';
import '../services/youtube_service.dart';

/// Semilla de artistas, playlists y moods para la pantalla de inicio.
const curatedArtistNames = [
  "Bad Bunny",
  "Karol G",
  "Ozuna",
  "Anuel AA",
  "Taylor Swift",
  "BLACKPINK",
  "BTS",
  "Justin Bieber",
  "Eminem",
  "Ed Sheeran",
  "Ariana Grande",
  "Billie Eilish",
  "The Weeknd",
  "Shakira",
  "Dua Lipa",
  "Feid",
  "ROSALÍA",
  "Rauw Alejandro",
  "Maluma",
  "Doja Cat",
];

const curatedTrendingNames = [
  {"title": "Despechá", "artist": "ROSALÍA"},
  {"title": "Ella Baila Sola", "artist": "Eslabón Armado Peso Pluma"},
  {"title": "TQM", "artist": "Feid"},
  {"title": "Quién Más Pues?", "artist": "J Balvin Maria Becerra"},
  {"title": "Un x100to", "artist": "Grupo Frontera Bad Bunny"},
  {"title": "Flowers", "artist": "Miley Cyrus"},
  {"title": "Kill Bill", "artist": "SZA"},
  {"title": "Creepin'", "artist": "Metro Boomin The Weeknd 21 Savage"},
  {"title": "Me Porto Bonito", "artist": "Bad Bunny Chencho Corleone"},
  {
    "title": "Shakira: Bzrp Music Sessions, Vol. 53",
    "artist": "Shakira Bizarrap",
  },
  {
    "title": "Ella No Es Tuya Remix",
    "artist": "Myke Towers Anitta Nicki Nicole",
  },
  {"title": "La Bachata", "artist": "Manuel Turizo"},
  {"title": "Desesperados", "artist": "Rauw Alejandro Chencho Corleone"},
  {"title": "Anti-Hero", "artist": "Taylor Swift"},
  {"title": "Calm Down", "artist": "Rema Selena Gomez"},
  {"title": "Industry Baby", "artist": "Lil Nas X Jack Harlow"},
  {"title": "Monotonía", "artist": "Shakira Ozuna"},
  {"title": "Provenza", "artist": "Karol G"},
  {"title": "Pepas", "artist": "Farruko"},
  {"title": "Stay", "artist": "The Kid LAROI Justin Bieber"},
];

const curatedFeaturedPlaylistSeeds = [
  // Añade ytid cuando lo conozcamos para evitar búsquedas y usar metadata real.
  {"title": "Top 100 Global", "ytid": "PL4fGSI1pDJn6puJdseH2Rt9sMvt9E2M4i"},
  {"title": "Trending Worldwide", "ytid": "PLFcGX84jKOu7fnNxRpajpvs-Zk3Za41ul"},
  {
    "title": "Today's Biggest Hits",
    "ytid": "PLO7-VO1D0_6MlO4UxJWFBUq3U-7zoIBf7",
  },
  {
    "title": "New Released Tracks",
    "ytid": "PL3-sRm8xAzY9gpXTMGVHJWy_FMD67NBed",
  },
  {
    "title": "Hotlist Internacional",
    "ytid": "PL3-sRm8xAzY_Rr7jgjrVCEy1JnNPuVp0W",
  },
  {"title": "Pop Hits 2025"},
  {"title": "Best Pop Music"},
  {"title": "Pop Rising"},
  {"title": "Viral Pop"},
  {"title": "Éxitos Latinos"},
  {"title": "Reggaeton Hits"},
  {"title": "Bachata Mix"},
  {"title": "Top Música Mexicana"},
  {"title": "Lofi Beats"},
  {"title": "Chill Vibes"},
  {"title": "Relaxing Lofi Mix"},
  {"title": "Rap & Trap Hits"},
  {"title": "EDM Party Mix"},
  {"title": "Rock Classics"},
  {"title": "R&B Vibes"},
];

const curatedMoodSeeds = [
  {
    "title": "Chill / Relax / Night Vibes",
    "songs": [
      {"title": "Kill Bill", "artist": "SZA"},
      {"title": "Calm Down", "artist": "Rema Selena Gomez"},
      {"title": "Anti-Hero", "artist": "Taylor Swift"},
    ],
  },
  {
    "title": "Happy / Good Vibes",
    "songs": [
      {"title": "Flowers", "artist": "Miley Cyrus"},
      {"title": "Provenza", "artist": "Karol G"},
      {"title": "Me Porto Bonito", "artist": "Bad Bunny Chencho"},
    ],
  },
  {
    "title": "Sad / Heartbreak",
    "songs": [
      {"title": "Bzrp Music Sessions #53", "artist": "Shakira Bizarrap"},
      {"title": "Stay", "artist": "The Kid LAROI Justin Bieber"},
      {"title": "Monotonía", "artist": "Shakira Ozuna"},
    ],
  },
  {
    "title": "Energy / Upbeat / Gym",
    "songs": [
      {"title": "Pepas", "artist": "Farruko"},
      {"title": "Creepin'", "artist": "Metro Boomin The Weeknd 21 Savage"},
      {"title": "Un x100to", "artist": "Grupo Frontera Bad Bunny"},
    ],
  },
];

final _sectionConfig = [
  ['artists', 5, curatedArtistNames.length],
  ['trending', 5, curatedTrendingNames.length],
  ['featured', 4, curatedFeaturedPlaylistSeeds.length],
  ['mood', 4, curatedMoodSeeds.length],
];

/// Hydrates all sections and keeps a preview map to drive the frontend without extra calls.
Future<Map<String, dynamic>> hydrateCuratedHome(
  YoutubeService youtube,
  HomeRepository repo,
  MediaRepositoryBase media, {
  bool forceRefresh = false,
}) async {
  await migrateLegacyHome(repo);
  for (final entry in _sectionConfig) {
    final sectionKey = entry[0] as String;
    final chunkLimit = forceRefresh ? entry[2] as int : entry[1] as int;
    await hydrateCuratedChunk(
      youtube,
      repo,
      media,
      section: sectionKey,
      limit: chunkLimit,
    );
  }

  final doc = await repo.getOrSeed();
  final sections = _sectionsFromDoc(doc);
  final previews = await repo.getPreviews();
  return {
    'sections': sections.map((s) => s.toMap()).toList(),
    'previews': previews,
    'status': doc['status'] ?? {},
    'updatedAt': doc['updatedAt'],
  };
}

Future<Map<String, dynamic>> hydrateCuratedChunk(
  YoutubeService youtube,
  HomeRepository repo,
  MediaRepositoryBase media, {
  required String section,
  int limit = 3,
}) async {
  await migrateLegacyHome(repo);
  final doc = await repo.getOrSeed();
  final status = Map<String, dynamic>.from(doc['status'] ?? {});
  final sections = _sectionsFromDoc(doc);
  final previews = Map<String, Map<String, dynamic>>.from(
    doc['previews'] ?? {},
  );
  final sectionType = _sectionTypeFromKey(section);
  final targetSection = _ensureSection(sections, sectionType);

  switch (section) {
    case 'artists':
      {
        final cursor = status['artists'] ?? 0;
        final seeds = curatedArtistNames;
        final end = (cursor + limit).clamp(0, seeds.length);
        for (var i = cursor; i < end; i++) {
          final name = seeds[i];
          final payload = await _resolveArtist(youtube, name);
          final artist = await media.persistArtistFromYoutube(payload);
          _addUnique(targetSection.itemIds, artist.ytid);
          previews[artist.ytid] = artist.toPreview();
        }
        status['artists'] = end;
        break;
      }
    case 'trending':
      {
        final cursor = status['trending'] ?? 0;
        final seeds = curatedTrendingNames;
        final end = (cursor + limit).clamp(0, seeds.length);
        var processed = cursor;
        for (var i = cursor; i < end; i++) {
          final seed = seeds[i];
          final payload = await _resolveSong(
            youtube,
            seed['title'] as String,
            seed['artist'] as String,
          );
          if (payload == null) {
            print('WARN: Could not resolve trending seed ${seed['title']}');
            break; // no avanzamos el cursor; reintenta en siguiente corrida
          }
          final song = await media.persistSongFromYoutube(
            payload,
            sections: {HomeSectionType.trendingSongs},
          );
          _addUnique(targetSection.itemIds, song.ytid);
          previews[song.ytid] = song.toPreview();
          processed = i + 1;
        }
        status['trending'] = processed;
        break;
      }
    case 'featured':
    case 'featuredPlaylists':
      {
        final cursor = status['featuredPlaylists'] ?? 0;
        final seeds = curatedFeaturedPlaylistSeeds;
        final end = (cursor + limit).clamp(0, seeds.length);
        for (var i = cursor; i < end; i++) {
          final seed = seeds[i];
          final payload = await _resolvePlaylist(
            youtube,
            title: seed['title'] as String,
            playlistId: seed['ytid'] as String?,
          );
          final result = await media.persistCollectionFromYoutube(
            payload,
            type: CollectionType.playlist,
            sections: {HomeSectionType.featuredPlaylists},
          );
          _addUnique(targetSection.collectionIds, result.collection.ytid);
          previews[result.collection.ytid] = _buildPlaylistPreview(result);
        }
        status['featuredPlaylists'] = end;
        break;
      }
    case 'mood':
    case 'moodPlaylists':
      {
        final cursor = status['moodPlaylists'] ?? 0;
        final seeds = curatedMoodSeeds;
        final end = (cursor + limit).clamp(0, seeds.length);
        for (var i = cursor; i < end; i++) {
          final mood = seeds[i];
          final title = mood['title'] as String;
          final songs = <Map<String, dynamic>>[];
          for (final data in (mood['songs'] as List)) {
            final payload = await _resolveSong(
              youtube,
              data['title'] as String,
              data['artist'] as String,
            );
            if (payload != null) {
              songs.add(payload);
            }
          }
          final payload = {
            'ytid': _moodId(title),
            'title': title,
            'source': 'curated-mood',
            'list': songs,
          };
          final result = await media.persistCollectionFromYoutube(
            payload,
            type: CollectionType.mood,
            mood: title,
            sections: {HomeSectionType.moodPlaylists},
          );
          _addUnique(targetSection.collectionIds, result.collection.ytid);
          previews[result.collection.ytid] = _buildPlaylistPreview(result);
        }
        status['moodPlaylists'] = end;
        break;
      }
    default:
      break;
  }

  doc['status'] = status;
  await repo.persistSections(sections, previews, baseDoc: doc);

  return {
    'sections': sections.map((s) => s.toMap()).toList(),
    'previews': previews,
    'status': status,
    'updatedAt': doc['updatedAt'],
  };
}

List<HomeSection> _sectionsFromDoc(Map<String, dynamic> doc) {
  final rawSections = List<Map<String, dynamic>>.from(doc['sections'] ?? []);
  return rawSections.map(HomeSection.fromMap).toList();
}

HomeSection _ensureSection(List<HomeSection> sections, HomeSectionType type) {
  final index = sections.indexWhere((section) => section.type == type);
  if (index != -1) return sections[index];
  final section = HomeSection(type: type);
  sections.add(section);
  return section;
}

HomeSectionType _sectionTypeFromKey(String key) {
  switch (key) {
    case 'artists':
      return HomeSectionType.popularArtists;
    case 'trending':
      return HomeSectionType.trendingSongs;
    case 'featured':
    case 'featuredPlaylists':
      return HomeSectionType.featuredPlaylists;
    case 'mood':
    case 'moodPlaylists':
      return HomeSectionType.moodPlaylists;
    default:
      return HomeSectionType.featuredPlaylists;
  }
}

void _addUnique(List<String> list, String id) {
  if (!list.contains(id)) {
    list.add(id);
  }
}

Map<String, dynamic> _buildPlaylistPreview(CollectionPersistenceResult result) {
  final previewSongs = result.songs.map((song) => song.toPreview()).toList();
  final firstSongThumb = previewSongs.isNotEmpty
      ? (previewSongs.first['thumbnail'] as String?)
      : null;
  // Prioriza siempre la portada del primer track; si no hay, usa la de la colección.
  var thumb = firstSongThumb ?? result.collection.image;
  final map = result.collection.toPreview(
    songs: previewSongs,
    thumbnail: thumb,
  );
  if (result.collection.type == CollectionType.mood) {
    map['type'] = 'playlist';
  }
  return map;
}

String _moodId(String title) =>
    'mood-${Uri.encodeComponent(title.toLowerCase())}';

/// Migra cache antiguo (artists/trending/featuredPlaylists/moodPlaylists) a sections+previews
/// para que el frontend no dependa del formato legacy.
Future<void> migrateLegacyHome(HomeRepository repo) async {
  final doc = await repo.getOrSeed();
  final hasSections = (doc['sections'] as List?)?.isNotEmpty == true;
  if (hasSections) return;

  final sections = <HomeSection>[];
  final previews = <String, Map<String, dynamic>>{};

  // Artists -> popularArtists
  final artistsList =
      (doc['artists'] as List?)?.whereType<Map<String, dynamic>>().toList() ??
      [];
  if (artistsList.isNotEmpty) {
    final section = HomeSection(type: HomeSectionType.popularArtists);
    for (final artist in artistsList) {
      final id = (artist['ytid'] ?? artist['id'])?.toString() ?? '';
      if (id.isEmpty) continue;
      section.itemIds.add(id);
      previews[id] = {
        'ytid': id,
        'title': artist['name'] ?? artist['title'] ?? id,
        'image': artist['image'] ?? artist['thumbnail'],
        'banner': artist['banner'],
        'type': 'artist',
        'subscribers': artist['subscribers'],
      };
    }
    sections.add(section);
  }

  // Trending songs -> trendingSongs
  final trendingList =
      (doc['trending'] as List?)?.whereType<Map<String, dynamic>>().toList() ??
      [];
  if (trendingList.isNotEmpty) {
    final section = HomeSection(type: HomeSectionType.trendingSongs);
    for (final song in trendingList) {
      final id = (song['ytid'] ?? song['id'])?.toString() ?? '';
      if (id.isEmpty) continue;
      section.itemIds.add(id);
      previews[id] = _songPreviewFromRaw(song);
    }
    sections.add(section);
  }

  // Featured playlists -> featuredPlaylists
  final featuredList =
      (doc['featuredPlaylists'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ??
      [];
  if (featuredList.isNotEmpty) {
    final section = HomeSection(type: HomeSectionType.featuredPlaylists);
    for (final pl in featuredList) {
      final id = (pl['ytid'] ?? pl['id'])?.toString() ?? '';
      if (id.isEmpty) continue;
      section.collectionIds.add(id);
      previews[id] = _playlistPreviewFromRaw(pl);
    }
    sections.add(section);
  }

  // Mood playlists -> moodPlaylists
  final moodList =
      (doc['moodPlaylists'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ??
      [];
  if (moodList.isNotEmpty) {
    final section = HomeSection(type: HomeSectionType.moodPlaylists);
    for (final mood in moodList) {
      final title = mood['title']?.toString() ?? 'Mood';
      final id = _moodId(title);
      section.collectionIds.add(id);
      final songs =
          (mood['songs'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [];
      previews[id] = {
        'ytid': id,
        'title': title,
        'thumbnail': _avatarUrl(title),
        'image': _avatarUrl(title),
        'songCount': songs.length,
        'type': 'playlist',
        'mood': title,
        'songs': songs.map(_songPreviewFromRaw).toList(),
      };
    }
    sections.add(section);
  }

  doc['sections'] = sections.map((s) => s.toMap()).toList();
  doc['previews'] = previews;
  await repo.persistSections(sections, previews, baseDoc: doc);
}

Map<String, dynamic> _songPreviewFromRaw(Map<String, dynamic> raw) {
  final id = (raw['ytid'] ?? raw['id'])?.toString() ?? '';
  final thumb =
      raw['image'] ??
      raw['thumbnail'] ??
      _avatarUrl(raw['title']?.toString() ?? id);
  return {
    'ytid': id,
    'title': raw['title'] ?? '',
    'artist': raw['artist'] ?? '',
    'thumbnail': thumb,
    'image': thumb,
    'duration': raw['duration'],
    'isLive': raw['isLive'],
    'type': 'song',
    'source': raw['source'],
  };
}

Map<String, dynamic> _playlistPreviewFromRaw(Map<String, dynamic> raw) {
  final id = (raw['ytid'] ?? raw['id'])?.toString() ?? '';
  final thumb =
      raw['image'] ??
      raw['thumbnail'] ??
      _avatarUrl(raw['title']?.toString() ?? id);
  final songs =
      (raw['list'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
  return {
    'ytid': id,
    'title': raw['title'] ?? '',
    'thumbnail': thumb,
    'image': thumb,
    'songCount': raw['songCount'] ?? songs.length,
    'type': 'playlist',
    'songs': songs.map(_songPreviewFromRaw).toList(),
    'source': raw['source'],
  };
}

Future<Map<String, dynamic>> _resolveArtist(
  YoutubeService youtube,
  String name,
) async {
  try {
    final channels = await youtube.searchChannels(name);
    if (channels.isNotEmpty) {
      final channel = channels.first;
      return await youtube.getChannelDetails(channel['ytid'] as String);
    }
  } catch (_) {}
  return {
    'ytid': name,
    'name': name,
    'title': name,
    'image': _avatarUrl(name),
    'source': 'curated-fallback',
  };
}

Future<Map<String, dynamic>?> _resolveSong(
  YoutubeService youtube,
  String title,
  String artist,
) async {
  final query = '$title $artist';
  try {
    final songs = await youtube.searchSongs(query);
    final valid = songs.firstWhere(
      (song) => (song['duration'] ?? 0) >= 90,
      orElse: () => songs.isNotEmpty ? songs.first : {},
    );
    final ytid = valid['ytid']?.toString() ?? '';
    if (valid.isNotEmpty && _looksLikeVideoId(ytid)) return valid;
  } catch (_) {}
  // No devolvemos fallback con ytid inválido; forzamos reintento en la siguiente corrida.
  return null;
}

Future<Map<String, dynamic>> _resolvePlaylist(
  YoutubeService youtube, {
  required String title,
  String? playlistId,
}) async {
  try {
    // Si tenemos el id, intentamos directamente.
    if (playlistId != null && playlistId.isNotEmpty) {
      final info = await youtube.getPlaylistInfo(playlistId);
      if (info.isNotEmpty) return info;
    }
  } catch (_) {}
  try {
    final found = await youtube.searchPlaylistsOnline(title);
    if (found.isNotEmpty) {
      final playlist = found.first;
      final ytid = playlist['ytid'] as String;
      return await youtube.getPlaylistInfo(ytid);
    }
  } catch (_) {}
  // Fallback: arma una playlist ad-hoc buscando canciones por el título.
  try {
    final songs = await youtube.searchSongs('$title playlist');
    if (songs.isNotEmpty) {
      final thumb =
          songs.first['image'] ?? songs.first['thumbnail'] ?? _avatarUrl(title);
      return {
        'ytid': title,
        'title': title,
        'image': thumb,
        'thumbnail': thumb,
        'source': 'curated-fallback',
        'songCount': songs.length,
        'list': songs,
      };
    }
  } catch (_) {}

  final fallbackImage = _avatarUrl(title);
  return {
    'ytid': title,
    'title': title,
    'image': fallbackImage,
    'thumbnail': fallbackImage,
    'source': 'curated-fallback',
    'songCount': 0,
    'list': <Map<String, dynamic>>[],
  };
}

String _avatarUrl(String name) =>
    'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=111827&color=fff&size=256';

bool _looksLikeVideoId(String id) =>
    RegExp(r'^[A-Za-z0-9_-]{6,}$').hasMatch(id);
