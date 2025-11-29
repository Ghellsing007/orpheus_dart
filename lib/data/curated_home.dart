import '../services/cache_service.dart';
import '../services/youtube_service.dart';
import '../repositories/home_repository.dart';

/// Semilla minimal por nombres; los IDs reales se resolverán vía YouTube.
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
  {"title": "Qué Más Pues?", "artist": "J Balvin Maria Becerra"},
  {"title": "Un x100to", "artist": "Grupo Frontera Bad Bunny"},
  {"title": "Flowers", "artist": "Miley Cyrus"},
  {"title": "Kill Bill", "artist": "SZA"},
  {"title": "Creepin'", "artist": "Metro Boomin The Weeknd 21 Savage"},
  {"title": "Me Porto Bonito", "artist": "Bad Bunny Chencho Corleone"},
  {"title": "Shakira: Bzrp Music Sessions, Vol. 53", "artist": "Shakira Bizarrap"},
  {"title": "Ella No Es Tuya Remix", "artist": "Myke Towers Anitta Nicki Nicole"},
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

const curatedFeaturedPlaylistNames = [
  "Top 100 Global",
  "Trending Worldwide",
  "Today's Biggest Hits",
  "New Released Tracks",
  "Hotlist Internacional",
  "Pop Hits 2025",
  "Best Pop Music",
  "Pop Rising",
  "Viral Pop",
  "Éxitos Latinos",
  "Reggaeton Hits",
  "Bachata Mix",
  "Top Música Mexicana",
  "Lofi Beats",
  "Chill Vibes",
  "Relaxing Lofi Mix",
  "Rap & Trap Hits",
  "EDM Party Mix",
  "Rock Classics",
  "R&B Vibes",
];

const curatedMoodSeeds = [
  {
    "title": "Chill / Relax / Night Vibes",
    "songs": [
      {"title": "Kill Bill", "artist": "SZA"},
      {"title": "Calm Down", "artist": "Rema Selena Gomez"},
      {"title": "Anti-Hero", "artist": "Taylor Swift"},
    ]
  },
  {
    "title": "Happy / Good Vibes",
    "songs": [
      {"title": "Flowers", "artist": "Miley Cyrus"},
      {"title": "Provenza", "artist": "Karol G"},
      {"title": "Me Porto Bonito", "artist": "Bad Bunny Chencho"},
    ]
  },
  {
    "title": "Sad / Heartbreak",
    "songs": [
      {"title": "Bzrp Music Sessions #53", "artist": "Shakira Bizarrap"},
      {"title": "Stay", "artist": "The Kid LAROI Justin Bieber"},
      {"title": "Monotonía", "artist": "Shakira Ozuna"},
    ]
  },
  {
    "title": "Energy / Upbeat / Gym",
    "songs": [
      {"title": "Pepas", "artist": "Farruko"},
      {"title": "Creepin'", "artist": "Metro Boomin The Weeknd 21 Savage"},
      {"title": "Un x100to", "artist": "Grupo Frontera Bad Bunny"},
    ]
  },
];

Map<String, dynamic> curatedHomeResponse() => {
      "artists": curatedArtistNames.map((name) => {"name": name}).toList(),
      "trending": curatedTrendingNames,
      "featuredPlaylists": curatedFeaturedPlaylistNames.map((name) => {"title": name}).toList(),
      "moodPlaylists": curatedMoodSeeds,
    };

/// Hydrates curated home data using YouTube endpoints (search by name) and caches the result.
Future<Map<String, dynamic>> hydrateCuratedHome(
  YoutubeService youtube, {
  bool forceRefresh = false,
}) async {
  // Artists: buscar canal por nombre
  final artists = <Map<String, dynamic>>[];
  for (final name in curatedArtistNames) {
    try {
      final channels = await youtube.searchChannels(name);
      if (channels.isNotEmpty) {
        final ch = channels.first;
        final channelDetails = await youtube.getChannelDetails(ch['ytid'] as String);
        artists.add(channelDetails);
      } else {
        artists.add({
          "name": name,
          "id": name,
          "ytid": name,
          "image": "https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=111827&color=fff&size=256",
        });
      }
    } catch (_) {
      artists.add({
        "name": name,
        "id": name,
        "ytid": name,
        "image": "https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=111827&color=fff&size=256",
      });
    }
  }

  // Trending: buscar canción por título+artista
  final trending = <Map<String, dynamic>>[];
  for (final seed in curatedTrendingNames) {
    final query = "${seed["title"]} ${seed["artist"]}";
    try {
      final songs = await youtube.searchSongs(query);
      final song = songs.firstWhere(
        (s) => (s["duration"] ?? 0) >= 90,
        orElse: () => songs.isNotEmpty ? songs.first : {},
      );
      if (song.isNotEmpty) {
        trending.add(song);
        continue;
      }
    } catch (_) {}
    trending.add({
      "ytid": query,
      "title": seed["title"],
      "artist": seed["artist"],
      "thumbnail": "https://ui-avatars.com/api/?name=${Uri.encodeComponent(seed["title"] as String)}&background=111827&color=fff&size=256",
      "duration": 0,
      "source": "youtube",
    });
  }

  // Featured playlists: buscar playlist por nombre
  final featured = <Map<String, dynamic>>[];
  for (final name in curatedFeaturedPlaylistNames) {
    try {
      final found = await youtube.searchPlaylistsOnline(name);
      if (found.isNotEmpty) {
        final pl = found.first;
        final ytid = pl["ytid"] as String;
        try {
          final info = await youtube.getPlaylistInfo(ytid);
          featured.add(info);
        } catch (_) {
          final image = (pl["image"] as String?) ??
              "https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=111827&color=fff&size=256";
          featured.add({
            "id": ytid,
            "ytid": ytid,
            "title": pl["title"] ?? name,
            "thumbnail": image,
            "image": image,
            "source": "youtube",
            "songCount": 0,
            "list": <Map<String, dynamic>>[],
          });
        }
        continue;
      }
    } catch (_) {}
    featured.add({
      "id": name,
      "ytid": name,
      "title": name,
      "thumbnail": "https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=111827&color=fff&size=256",
      "image": "https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=111827&color=fff&size=256",
      "source": "youtube",
      "songCount": 0,
      "list": <Map<String, dynamic>>[],
    });
  }

  // Mood playlists: buscar canciones por nombre
  final moods = <Map<String, dynamic>>[];
  for (final mood in curatedMoodSeeds) {
    final songs = <Map<String, dynamic>>[];
    for (final s in (mood["songs"] as List)) {
      final query = "${s["title"]} ${s["artist"]}";
      try {
        final res = await youtube.searchSongs(query);
        final song = res.firstWhere(
          (song) => (song["duration"] ?? 0) >= 90,
          orElse: () => res.isNotEmpty ? res.first : {},
        );
        if (song.isNotEmpty) {
          songs.add(song);
          continue;
        }
      } catch (_) {}
      songs.add({
        "ytid": query,
        "title": s["title"],
        "artist": s["artist"],
        "thumbnail": "https://ui-avatars.com/api/?name=${Uri.encodeComponent(s["title"] as String)}&background=111827&color=fff&size=256",
        "duration": 0,
        "source": "youtube",
      });
    }
    moods.add({
      "title": mood["title"],
      "songs": songs,
    });
  }

  final result = {
    "artists": artists,
    "trending": trending,
    "featuredPlaylists": featured,
    "moodPlaylists": moods,
  };
  return result;
}

/// Hydrates a single section chunk and persists via repository.
Future<Map<String, dynamic>> hydrateCuratedChunk(
  YoutubeService youtube,
  HomeRepository repo, {
  required String section,
  int limit = 3,
}) async {
  final doc = await repo.getOrSeed();
  final status = Map<String, dynamic>.from(doc['status'] ?? {});

  switch (section) {
    case 'artists':
      {
        final cursor = status['artists'] ?? 0;
        final seeds = curatedArtistNames;
        final list = List<Map<String, dynamic>>.from(doc['artists'] ?? []);
        final end = (cursor + limit).clamp(0, seeds.length);
        while (list.length < end) {
          list.add(<String, dynamic>{});
        }
        for (int i = cursor; i < end; i++) {
          final name = seeds[i];
          try {
            final channels = await youtube.searchChannels(name);
            if (channels.isNotEmpty) {
              final ch = channels.first;
              final channelDetails = await youtube.getChannelDetails(ch['ytid'] as String);
              list[i] = channelDetails;
            } else {
              list[i] = {
                "name": name,
                "id": name,
                "ytid": name,
                "image":
                    "https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=111827&color=fff&size=256",
              };
            }
          } catch (_) {
            list[i] = {
              "name": name,
              "id": name,
              "ytid": name,
              "image":
                  "https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=111827&color=fff&size=256",
            };
          }
        }
        doc['artists'] = list;
        status['artists'] = end;
        break;
      }
    case 'trending':
      {
        final cursor = status['trending'] ?? 0;
        final seeds = curatedTrendingNames;
        final list = List<Map<String, dynamic>>.from(doc['trending'] ?? []);
        final end = (cursor + limit).clamp(0, seeds.length);
        while (list.length < end) {
          list.add(<String, dynamic>{});
        }
        for (int i = cursor; i < end; i++) {
          final seed = seeds[i];
          final query = "${seed["title"]} ${seed["artist"]}";
          try {
            final songs = await youtube.searchSongs(query);
            final song = songs.firstWhere(
              (s) => (s["duration"] ?? 0) >= 90,
              orElse: () => songs.isNotEmpty ? songs.first : {},
            );
            if (song.isNotEmpty) {
              list[i] = song;
              continue;
            }
          } catch (_) {}
          list[i] = {
            "ytid": query,
            "title": seed["title"],
            "artist": seed["artist"],
            "thumbnail":
                "https://ui-avatars.com/api/?name=${Uri.encodeComponent(seed["title"] as String)}&background=111827&color=fff&size=256",
            "duration": 0,
            "source": "youtube",
          };
        }
        doc['trending'] = list;
        status['trending'] = end;
        break;
      }
    case 'featured':
    case 'featuredPlaylists':
      {
        final cursor = status['featuredPlaylists'] ?? 0;
        final seeds = curatedFeaturedPlaylistNames;
        final list = List<Map<String, dynamic>>.from(doc['featuredPlaylists'] ?? []);
        final end = (cursor + limit).clamp(0, seeds.length);
        while (list.length < end) {
          list.add(<String, dynamic>{});
        }
        for (int i = cursor; i < end; i++) {
          final name = seeds[i];
          try {
            final found = await youtube.searchPlaylistsOnline(name);
            if (found.isNotEmpty) {
              final pl = found.first;
              final ytid = pl["ytid"] as String;
              try {
                final info = await youtube.getPlaylistInfo(ytid);
                list[i] = info;
              } catch (_) {
                final image = (pl["image"] as String?) ??
                    "https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=111827&color=fff&size=256";
                list[i] = {
                  "id": ytid,
                  "ytid": ytid,
                  "title": pl["title"] ?? name,
                  "thumbnail": image,
                  "image": image,
                  "source": "youtube",
                  "songCount": 0,
                  "list": <Map<String, dynamic>>[],
                };
              }
              continue;
            }
          } catch (_) {}
          list[i] = {
            "id": name,
            "ytid": name,
            "title": name,
            "thumbnail":
                "https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=111827&color=fff&size=256",
            "image":
                "https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=111827&color=fff&size=256",
            "source": "youtube",
            "songCount": 0,
            "list": <Map<String, dynamic>>[],
          };
        }
        doc['featuredPlaylists'] = list;
        status['featuredPlaylists'] = end;
        break;
      }
    case 'mood':
    case 'moodPlaylists':
      {
        final cursor = status['moodPlaylists'] ?? 0;
        final seeds = curatedMoodSeeds;
        final list = List<Map<String, dynamic>>.from(doc['moodPlaylists'] ?? []);
        final end = (cursor + limit).clamp(0, seeds.length);
        while (list.length < end) {
          list.add(<String, dynamic>{});
        }
        for (int i = cursor; i < end; i++) {
          final mood = seeds[i];
          final songs = <Map<String, dynamic>>[];
          for (final s in (mood["songs"] as List)) {
            final query = "${s["title"]} ${s["artist"]}";
            try {
              final res = await youtube.searchSongs(query);
              final song = res.firstWhere(
                (song) => (song["duration"] ?? 0) >= 90,
                orElse: () => res.isNotEmpty ? res.first : {},
              );
              if (song.isNotEmpty) {
                songs.add(song);
                continue;
              }
            } catch (_) {}
            songs.add({
              "ytid": query,
              "title": s["title"],
              "artist": s["artist"],
              "thumbnail":
                  "https://ui-avatars.com/api/?name=${Uri.encodeComponent(s["title"] as String)}&background=111827&color=fff&size=256",
              "duration": 0,
              "source": "youtube",
            });
          }
          list[i] = {
            "title": mood["title"],
            "songs": songs,
          };
        }
        doc['moodPlaylists'] = list;
        status['moodPlaylists'] = end;
        break;
      }
    default:
      break;
  }

  doc['status'] = status;
  doc['updatedAt'] = DateTime.now().toIso8601String();
  await repo.saveDoc(doc);

  final response = Map<String, dynamic>.from(doc)..remove('status');
  return response;
}
