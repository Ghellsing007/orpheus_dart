import '../services/mongo_service.dart';
class HomeRepository {
  HomeRepository(this._mongo);

  final MongoService _mongo;
  static const _collection = 'home_cache';
  static const _docId = 'home';

  Future<Map<String, dynamic>?> getDoc() async {
    final coll = await _mongo.collection(_collection);
    final doc = await coll.findOne({'_id': _docId});
    return doc == null ? null : Map<String, dynamic>.from(doc);
  }

  Future<void> saveDoc(Map<String, dynamic> doc) async {
    final coll = await _mongo.collection(_collection);
    await coll.replaceOne({'_id': _docId}, doc, upsert: true);
  }

  Future<Map<String, dynamic>> getOrSeed() async {
    final existing = await getDoc();
    if (existing != null) return existing;
    final seeded = <String, dynamic>{
      '_id': _docId,
      'artists': <Map<String, dynamic>>[],
      'trending': <Map<String, dynamic>>[],
      'featuredPlaylists': <Map<String, dynamic>>[],
      'moodPlaylists': <Map<String, dynamic>>[],
      'status': {
        'artists': 0,
        'trending': 0,
        'featuredPlaylists': 0,
        'moodPlaylists': 0,
      },
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await saveDoc(seeded);
    return seeded;
  }
}
