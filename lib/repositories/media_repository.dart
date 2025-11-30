import '../models/media_models.dart';
import '../services/mongo_service.dart';

class CollectionPersistenceResult {
  CollectionPersistenceResult({required this.collection, required this.songs});

  final ContentCollection collection;
  final List<Song> songs;
}

abstract class MediaRepositoryBase {
  Future<Song> persistSongFromYoutube(
    Map<String, dynamic> payload, {
    String? artistId,
    Set<String>? playlistIds,
    Set<String>? collectionIds,
    Set<HomeSectionType>? sections,
  });

  Future<Artist> persistArtistFromYoutube(
    Map<String, dynamic> payload, {
    Set<String>? relatedArtistIds,
  });

  Future<CollectionPersistenceResult> persistCollectionFromYoutube(
    Map<String, dynamic> payload, {
    CollectionType type,
    Set<String>? additionalSongIds,
    Set<String>? artistIds,
    String? ownerId,
    String? mood,
    Set<HomeSectionType>? sections,
  });

  Future<Song?> getSongById(String id);
  Future<List<Song>> getSongsByIds(List<String> ids);
  Future<ContentCollection?> getCollectionById(String id);
  Future<List<ContentCollection>> getCollectionsByIds(List<String> ids);
  Future<Map<String, dynamic>?> getDbPlaylistById(String id);
  Future<Artist?> getArtistById(String id);
}

class MediaRepository implements MediaRepositoryBase {
  MediaRepository(this._mongo);

  final MongoService _mongo;

  static const _songsCollection = 'songs';
  static const _artistsCollection = 'artists';
  static const _collectionsCollection = 'collections';
  static const _playlistsCollection = 'playlists';

  @override
  Future<Song> persistSongFromYoutube(
    Map<String, dynamic> payload, {
    String? artistId,
    Set<String>? playlistIds,
    Set<String>? collectionIds,
    Set<HomeSectionType>? sections,
  }) async {
    final song = Song.fromYoutube(payload);
    final coll = await _mongo.collection(_songsCollection);
    final existing = await coll.findOne({'_id': song.ytid});
    // DEBUG: Log image URLs
    print(
      'DEBUG: Persisting song ${song.ytid} - New image: ${song.image}, Existing image: ${existing?['image']}',
    );
    // Preserve existing image if it's better (to avoid overwriting correct DB images with YouTube ones)
    final preservedImage = (existing?['image'] as String?) ?? song.image;
    final merged = Song(
      ytid: song.ytid,
      title: song.title,
      artistName: song.artistName,
      artistId: artistId ?? song.artistId ?? (existing?['artistId'] as String?),
      durationSec: song.durationSec,
      isLive: song.isLive,
      image: preservedImage,
      lowResImage: song.lowResImage,
      highResImage: song.highResImage,
      source: song.source,
      playlistIds: {
        ..._stringSet(existing?['playlistIds']),
        ...(playlistIds ?? {}),
      },
      collectionIds: {
        ..._stringSet(existing?['collectionIds']),
        ...(collectionIds ?? {}),
      },
      sections: {..._sectionSet(existing?['sections']), ...(sections ?? {})},
      isImageFallback: song.isImageFallback,
      fallbackImageSource: song.fallbackImageSource,
    );
    final doc = merged.toMap();
    doc['_id'] = merged.ytid;
    await coll.replaceOne({'_id': merged.ytid}, doc, upsert: true);
    return merged;
  }

  @override
  Future<Artist> persistArtistFromYoutube(
    Map<String, dynamic> payload, {
    Set<String>? relatedArtistIds,
  }) async {
    final artist = Artist.fromYoutube(payload);
    final topSongs =
        (payload['topSongs'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final persistedTopSongIds = <String>{};
    for (final songPayload in topSongs) {
      final persistedSong = await persistSongFromYoutube(
        songPayload,
        artistId: artist.ytid,
      );
      persistedTopSongIds.add(persistedSong.ytid);
    }

    final coll = await _mongo.collection(_artistsCollection);
    final existing = await coll.findOne({'_id': artist.ytid});
    final merged = artist.copyWith(
      topSongIds: {
        ..._stringSet(existing?['topSongIds']),
        ...artist.topSongIds,
        ...persistedTopSongIds,
      },
      playlistIds: {
        ..._stringSet(existing?['playlistIds']),
        ...artist.playlistIds,
      },
      relatedArtistIds: {
        ..._stringSet(existing?['relatedArtistIds']),
        ...(relatedArtistIds ?? {}),
      },
    );
    final doc = merged.toMap();
    doc['_id'] = merged.ytid;
    await coll.replaceOne({'_id': merged.ytid}, doc, upsert: true);
    return merged;
  }

  @override
  Future<CollectionPersistenceResult> persistCollectionFromYoutube(
    Map<String, dynamic> payload, {
    CollectionType type = CollectionType.playlist,
    Set<String>? additionalSongIds,
    Set<String>? artistIds,
    String? ownerId,
    String? mood,
    Set<HomeSectionType>? sections,
  }) async {
    final collection = ContentCollection.fromYoutube(payload, type: type);
    final songPayloads =
        (payload['list'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final persistedSongs = <Song>[];
    for (final songPayload in songPayloads) {
      final persistedSong = await persistSongFromYoutube(
        songPayload,
        collectionIds: {collection.ytid},
        sections: sections,
      );
      persistedSongs.add(persistedSong);
    }

    final coll = await _mongo.collection(_collectionsCollection);
    final existing = await coll.findOne({'_id': collection.ytid});
    final merged = collection.copyWith(
      songIds: {
        ..._stringSet(existing?['songIds']),
        ...collection.songIds,
        ...(additionalSongIds ?? {}),
        ...persistedSongs.map((s) => s.ytid),
      },
      artistIds: {..._stringSet(existing?['artistIds']), ...(artistIds ?? {})},
      ownerId: ownerId ?? existing?['ownerId'] as String?,
      mood: mood ?? existing?['mood'] as String?,
    );
    await _persistPlaylistDocument(merged, persistedSongs);
    final doc = merged.toMap();
    doc['_id'] = merged.ytid;
    await coll.replaceOne({'_id': merged.ytid}, doc, upsert: true);
    return CollectionPersistenceResult(
      collection: merged,
      songs: persistedSongs,
    );
  }

  Future<void> _persistPlaylistDocument(
    ContentCollection collection,
    List<Song> songs,
  ) async {
    if (collection.type != CollectionType.playlist) return;

    final playlistDoc = {
      '_id': collection.ytid,
      'ytid': collection.ytid,
      'title': collection.title,
      'type': collection.type.name,
      'image': collection.image,
      'source': collection.source,
      'songCount': collection.songIds.length,
      'songIds': collection.songIds.toList(),
      'songs': songs.map((song) => _buildSongPreview(song)).toList(),
      'list': songs.map((song) => _buildSongPreview(song)).toList(),
    };

    final coll = await _mongo.collection(_playlistsCollection);
    await coll.replaceOne({'_id': collection.ytid}, playlistDoc, upsert: true);
  }

  Map<String, dynamic> _buildSongPreview(Song song) {
    final thumbnail = _resolveSongThumbnail(song);
    return {
      'ytid': song.ytid,
      'title': song.title,
      'artist': song.artistName,
      'thumbnail': thumbnail,
      'image': thumbnail,
      'duration': song.durationSec,
      'isLive': song.isLive,
      'type': 'song',
      'source': song.source,
    };
  }

  String _resolveSongThumbnail(Song song) {
    final candidates = [song.highResImage, song.image, song.lowResImage];
    for (final candidate in candidates) {
      if (candidate == null) continue;
      if (candidate.contains('/vi/${song.ytid}')) {
        return candidate;
      }
    }
    return 'https://img.youtube.com/vi/${song.ytid}/sddefault.jpg';
  }

  @override
  Future<Song?> getSongById(String id) async {
    final coll = await _mongo.collection(_songsCollection);
    final doc = await coll.findOne({'_id': id});
    return doc == null ? null : Song.fromMap(Map<String, dynamic>.from(doc));
  }

  @override
  Future<List<Song>> getSongsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final coll = await _mongo.collection(_songsCollection);
    final cursor = coll.find({
      '_id': {'\$in': ids},
    });
    final fetched = await cursor
        .map((doc) => Song.fromMap(Map<String, dynamic>.from(doc)))
        .toList();
    final byId = {for (final song in fetched) song.ytid: song};
    return ids.map((id) => byId[id]).whereType<Song>().toList();
  }

  @override
  Future<ContentCollection?> getCollectionById(String id) async {
    final coll = await _mongo.collection(_collectionsCollection);
    final doc = await coll.findOne({'_id': id});
    return doc == null
        ? null
        : ContentCollection.fromMap(Map<String, dynamic>.from(doc));
  }

  @override
  Future<List<ContentCollection>> getCollectionsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final coll = await _mongo.collection(_collectionsCollection);
    final cursor = coll.find({
      '_id': {'\$in': ids},
    });
    final fetched = await cursor
        .map((doc) => ContentCollection.fromMap(Map<String, dynamic>.from(doc)))
        .toList();
    final byId = {for (final collection in fetched) collection.ytid: collection};
    return ids.map((id) => byId[id]).whereType<ContentCollection>().toList();
  }

  @override
  Future<Map<String, dynamic>?> getDbPlaylistById(String id) async {
    final coll = await _mongo.collection(_playlistsCollection);
    final doc = await coll.findOne({'_id': id});
    return doc == null ? null : Map<String, dynamic>.from(doc);
  }

  @override
  Future<Artist?> getArtistById(String id) async {
    final coll = await _mongo.collection(_artistsCollection);
    final doc = await coll.findOne({'_id': id});
    return doc == null ? null : Artist.fromMap(Map<String, dynamic>.from(doc));
  }

  Set<String> _stringSet(dynamic value) {
    if (value is Iterable) {
      return value.whereType<String>().toSet();
    }
    if (value is String) {
      return {value};
    }
    return {};
  }

  Set<HomeSectionType> _sectionSet(dynamic value) {
    if (value is Iterable) {
      return value.whereType<String>().map(homeSectionTypeFromString).toSet();
    }
    return {};
  }
}
