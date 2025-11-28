import 'package:mongo_dart/mongo_dart.dart';

class MongoService {
  MongoService(this.uri);

  final String uri;
  Db? _db;

  Future<Db> _getDb() async {
    if (_db != null && _db!.isConnected) return _db!;
    _db = await Db.create(uri);
    await _db!.open();
    return _db!;
  }

  Future<DbCollection> collection(String name) async {
    final db = await _getDb();
    return db.collection(name);
  }

  Future<void> close() async {
    if (_db != null && _db!.isConnected) {
      await _db!.close();
    }
  }
}
