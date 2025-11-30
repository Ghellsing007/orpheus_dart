enum CollectionType { playlist, album, mood, curated, unknown }

enum HomeSectionType {
  featuredPlaylists,
  trendingSongs,
  popularArtists,
  recommendations,
  moodPlaylists,
}

CollectionType collectionTypeFromString(String? value) {
  if (value == null) return CollectionType.unknown;
  return CollectionType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => CollectionType.unknown,
  );
}

HomeSectionType homeSectionTypeFromString(String? value) {
  if (value == null) return HomeSectionType.featuredPlaylists;
  return HomeSectionType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => HomeSectionType.featuredPlaylists,
  );
}

/// Modelo tipado para canciones (YouTube video).
/// Sirve como unidad básica para deduplicar y relacionar con artistas/payouts.
class Song {
  Song({
    required this.ytid,
    required this.title,
    required this.artistName,
    this.artistId,
    this.durationSec,
    this.isLive = false,
    this.image,
    this.lowResImage,
    this.highResImage,
    this.source,
    Set<String>? playlistIds,
    Set<String>? collectionIds,
    Set<HomeSectionType>? sections,
    this.isImageFallback = false,
    this.fallbackImageSource,
  }) : playlistIds = playlistIds ?? {},
       collectionIds = collectionIds ?? {},
       sections = sections ?? {};

  final String ytid;
  final String title;
  final String artistName;
  final String? artistId;
  final int? durationSec;
  final bool isLive;
  final String? image;
  final String? lowResImage;
  final String? highResImage;
  final String? source;
  final Set<String> playlistIds;
  final Set<String> collectionIds;
  final Set<HomeSectionType> sections;
  final bool isImageFallback;
  final String? fallbackImageSource;

  Map<String, dynamic> toMap() => {
    'ytid': ytid,
    'title': title,
    'artist': artistName,
    if (artistId != null) 'artistId': artistId,
    if (durationSec != null) 'duration': durationSec,
    'isLive': isLive,
    if (image != null) 'image': image,
    if (lowResImage != null) 'lowResImage': lowResImage,
    if (highResImage != null) 'highResImage': highResImage,
    if (source != null) 'source': source,
    if (playlistIds.isNotEmpty) 'playlistIds': playlistIds.toList(),
    if (collectionIds.isNotEmpty) 'collectionIds': collectionIds.toList(),
    if (sections.isNotEmpty) 'sections': sections.map((s) => s.name).toList(),
    if (isImageFallback) 'isImageFallback': isImageFallback,
    if (fallbackImageSource != null) 'fallbackImageSource': fallbackImageSource,
  };

  factory Song.fromYoutube(Map<String, dynamic> payload) {
    return Song(
      ytid: payload['ytid'] ?? payload['id'],
      title: payload['title'] ?? '',
      artistName: payload['artist'] ?? '',
      durationSec: payload['duration'] as int?,
      isLive: payload['isLive'] == true,
      image: payload['image'],
      lowResImage: payload['lowResImage'] ?? payload['thumbnail'],
      highResImage: payload['highResImage'],
      source: payload['source'] as String?,
      isImageFallback: payload['isImageFallback'] == true,
      fallbackImageSource: payload['fallbackImageSource'] as String?,
    );
  }

  factory Song.fromMap(Map<String, dynamic> map) {
    return Song(
      ytid: map['ytid'] as String,
      title: map['title'] as String? ?? '',
      artistName: map['artist'] as String? ?? '',
      artistId: map['artistId'] as String?,
      durationSec: map['duration'] as int?,
      isLive: map['isLive'] == true,
      image: map['image'] as String?,
      lowResImage: map['lowResImage'] as String?,
      highResImage: map['highResImage'] as String?,
      source: map['source'] as String?,
      playlistIds: (map['playlistIds'] as Iterable?)
          ?.whereType<String>()
          .toSet(),
      collectionIds: (map['collectionIds'] as Iterable?)
          ?.whereType<String>()
          .toSet(),
      sections: (map['sections'] as Iterable?)
          ?.whereType<String>()
          .map(homeSectionTypeFromString)
          .toSet(),
      isImageFallback: map['isImageFallback'] == true,
      fallbackImageSource: map['fallbackImageSource'] as String?,
    );
  }

  Song copyWith({
    String? artistId,
    Set<String>? playlistIds,
    Set<String>? collectionIds,
    Set<HomeSectionType>? sections,
    bool? isImageFallback,
    String? fallbackImageSource,
  }) {
    return Song(
      ytid: ytid,
      title: title,
      artistName: artistName,
      artistId: artistId ?? this.artistId,
      durationSec: durationSec,
      isLive: isLive,
      image: image,
      lowResImage: lowResImage,
      highResImage: highResImage,
      source: source,
      playlistIds: playlistIds ?? this.playlistIds,
      collectionIds: collectionIds ?? this.collectionIds,
      sections: sections ?? this.sections,
      isImageFallback: isImageFallback ?? this.isImageFallback,
      fallbackImageSource: fallbackImageSource ?? this.fallbackImageSource,
    );
  }

  Map<String, dynamic> toPreview() {
    final thumb =
        image ??
        lowResImage ??
        highResImage ??
        'https://img.youtube.com/vi/$ytid/sddefault.jpg';
    // DEBUG: Log chosen thumbnail
    print(
      'DEBUG: Song $ytid toPreview - chosen thumb: $thumb (image: $image, low: $lowResImage, high: $highResImage)',
    );
    return {
      'ytid': ytid,
      'title': title,
      'artist': artistName,
      'thumbnail': thumb,
      'image': thumb,
      'duration': durationSec,
      'isLive': isLive,
      'type': 'song',
      'source': source,
      if (isImageFallback) 'isFallback': true,
    };
  }
}

/// Representación tipada de un artista (canal).
class Artist {
  Artist({
    required this.ytid,
    required this.name,
    this.description,
    this.image,
    this.banner,
    this.subscribers,
    Set<String>? topSongIds,
    Set<String>? playlistIds,
    Set<String>? relatedArtistIds,
  }) : topSongIds = topSongIds ?? {},
       playlistIds = playlistIds ?? {},
       relatedArtistIds = relatedArtistIds ?? {};

  final String ytid;
  final String name;
  final String? description;
  final String? image;
  final String? banner;
  final int? subscribers;
  final Set<String> topSongIds;
  final Set<String> playlistIds;
  final Set<String> relatedArtistIds;

  Map<String, dynamic> toMap() => {
    'ytid': ytid,
    'name': name,
    if (description != null) 'description': description,
    if (image != null) 'image': image,
    if (banner != null) 'banner': banner,
    if (subscribers != null) 'subscribers': subscribers,
    if (topSongIds.isNotEmpty) 'topSongIds': topSongIds.toList(),
    if (playlistIds.isNotEmpty) 'playlistIds': playlistIds.toList(),
    if (relatedArtistIds.isNotEmpty)
      'relatedArtistIds': relatedArtistIds.toList(),
  };

  factory Artist.fromYoutube(Map<String, dynamic> payload) {
    return Artist(
      ytid: payload['ytid'] ?? payload['id'],
      name: payload['name'] ?? payload['title'] ?? '',
      description: payload['description'] as String?,
      image: payload['image'] as String?,
      banner: payload['banner'] as String?,
      subscribers: payload['subscribers'] as int?,
      topSongIds:
          (payload['topSongs'] as List<dynamic>?)
              ?.map((s) => s['ytid'] as String)
              .toSet() ??
          {},
      playlistIds:
          (payload['playlists'] as List<dynamic>?)
              ?.map((p) => p['ytid'] as String)
              .toSet() ??
          {},
    );
  }

  factory Artist.fromMap(Map<String, dynamic> map) {
    return Artist(
      ytid: map['ytid'] as String,
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      image: map['image'] as String?,
      banner: map['banner'] as String?,
      subscribers: map['subscribers'] as int?,
      topSongIds: (map['topSongIds'] as Iterable?)?.whereType<String>().toSet(),
      playlistIds: (map['playlistIds'] as Iterable?)
          ?.whereType<String>()
          .toSet(),
      relatedArtistIds: (map['relatedArtistIds'] as Iterable?)
          ?.whereType<String>()
          .toSet(),
    );
  }

  Map<String, dynamic> toPreview() => {
    'ytid': ytid,
    'title': name,
    'image': image,
    'banner': banner,
    'type': 'artist',
    if (subscribers != null) 'subscribers': subscribers,
  };

  Artist copyWith({
    String? description,
    Set<String>? topSongIds,
    Set<String>? playlistIds,
    Set<String>? relatedArtistIds,
  }) {
    return Artist(
      ytid: ytid,
      name: name,
      description: description ?? this.description,
      image: image,
      banner: banner,
      subscribers: subscribers,
      topSongIds: topSongIds ?? this.topSongIds,
      playlistIds: playlistIds ?? this.playlistIds,
      relatedArtistIds: relatedArtistIds ?? this.relatedArtistIds,
    );
  }
}

/// Colección general (playlist, álbum, mood, playlists destacadas).
class ContentCollection {
  ContentCollection({
    required this.ytid,
    required this.title,
    this.type = CollectionType.unknown,
    this.description,
    this.image,
    this.source,
    this.songCount,
    Set<String>? songIds,
    Set<String>? artistIds,
    this.ownerId,
    this.mood,
  }) : songIds = songIds ?? {},
       artistIds = artistIds ?? {};

  final String ytid;
  final String title;
  final CollectionType type;
  final String? description;
  final String? image;
  final String? source;
  final int? songCount;
  final Set<String> songIds;
  final Set<String> artistIds;
  final String? ownerId;
  final String? mood;

  Map<String, dynamic> toMap() => {
    'ytid': ytid,
    'title': title,
    'type': type.name,
    if (description != null) 'description': description,
    if (image != null) 'image': image,
    if (source != null) 'source': source,
    if (songCount != null) 'songCount': songCount,
    if (songIds.isNotEmpty) 'songIds': songIds.toList(),
    if (artistIds.isNotEmpty) 'artistIds': artistIds.toList(),
    if (ownerId != null) 'ownerId': ownerId,
    if (mood != null) 'mood': mood,
  };

  factory ContentCollection.fromYoutube(
    Map<String, dynamic> payload, {
    CollectionType type = CollectionType.playlist,
  }) {
    final songs = payload['list'] as List<dynamic>? ?? [];
    return ContentCollection(
      ytid: payload['ytid'] ?? payload['id'] ?? '',
      title: payload['title'] ?? '',
      type: type,
      image: payload['image'] ?? payload['thumbnail'] as String?,
      source: payload['source'] as String?,
      songCount: payload['songCount'] as int? ?? songs.length,
      songIds: songs.map((song) => song['ytid'] as String).toSet(),
    );
  }

  factory ContentCollection.fromMap(Map<String, dynamic> map) {
    return ContentCollection(
      ytid: map['ytid'] as String,
      title: map['title'] as String? ?? '',
      type: collectionTypeFromString(map['type'] as String?),
      description: map['description'] as String?,
      image: map['image'] as String?,
      source: map['source'] as String?,
      songCount: map['songCount'] as int?,
      songIds: (map['songIds'] as Iterable?)?.whereType<String>().toSet(),
      artistIds: (map['artistIds'] as Iterable?)?.whereType<String>().toSet(),
      ownerId: map['ownerId'] as String?,
      mood: map['mood'] as String?,
    );
  }

  Map<String, dynamic> toPreview({
    List<Map<String, dynamic>>? songs,
    String? thumbnail,
  }) {
    final thumb = thumbnail ?? image;
    return {
      'ytid': ytid,
      'title': title,
      'image': thumb,
      'thumbnail': thumb,
      'songCount': songCount,
      'type': type.name,
      'source': source,
      if (songs != null) 'songs': songs,
      if (mood != null) 'mood': mood,
    };
  }

  ContentCollection copyWith({
    Set<String>? songIds,
    Set<String>? artistIds,
    String? mood,
    String? ownerId,
  }) {
    return ContentCollection(
      ytid: ytid,
      title: title,
      type: type,
      description: description,
      image: image,
      source: source,
      songCount: songCount,
      songIds: songIds ?? this.songIds,
      artistIds: artistIds ?? this.artistIds,
      ownerId: ownerId ?? this.ownerId,
      mood: mood ?? this.mood,
    );
  }
}

/// Secciones del home cache para mantener referencias sin repetir objetos completos.
class HomeSection {
  HomeSection({
    required this.type,
    List<String>? itemIds,
    List<String>? collectionIds,
  }) : itemIds = itemIds ?? [],
       collectionIds = collectionIds ?? [];

  final HomeSectionType type;
  final List<String> itemIds;
  final List<String> collectionIds;

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'itemIds': itemIds,
    if (collectionIds.isNotEmpty) 'collectionIds': collectionIds,
  };

  factory HomeSection.fromMap(Map<String, dynamic> map) {
    final rawCollectionIds = map['collectionIds'] as List<dynamic>? ?? [];
    return HomeSection(
      type: homeSectionTypeFromString(map['type'] as String?),
      itemIds: List<String>.from(map['itemIds'] ?? []),
      collectionIds: rawCollectionIds.whereType<String>().toList(),
    );
  }
}
