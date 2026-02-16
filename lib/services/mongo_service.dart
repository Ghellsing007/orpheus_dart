import 'package:mongo_dart/mongo_dart.dart';
import 'package:mongo_pool/mongo_pool.dart';

class MongoService {
  MongoService(this.uri);

  final String uri;
  // Pool size of 4, consistent with our proven stable configuration
  static const int _poolSize = 4;
  
  // Static future to handle concurrent initialization globally
  static Future<void>? _connectingFuture;

  /// Connects to the database using MongoDbPoolService.
  Future<void> connect() async {
    final poolService = MongoDbPoolService(
      MongoPoolConfiguration(
        maxLifetimeMilliseconds: 300000, // 5 minutes
        leakDetectionThreshold: 10000, // 10 seconds
        uriString: uri, 
        poolSize: _poolSize,
      ),
    );

    // If initialization is in progress, wait for it
    if (_connectingFuture != null) {
      await _connectingFuture;
      return;
    }

    // Access the base pool object
    final poolBase = poolService.pool;
    
    // If already connected/initialized, do nothing
    if (poolBase.allConnections.isNotEmpty) return;

    print('DEBUG: Initializing mongo_pool (Size: $_poolSize)...');
    _connectingFuture = _initPool(poolService);
    
    try {
      await _connectingFuture;
    } finally {
      _connectingFuture = null;
    }
  }

  Future<void> _initPool(MongoDbPoolService poolService) async {
    try {
      await poolService.initialize();
      print('DEBUG: mongo_pool Initialized.');
    } catch (e) {
      if (e.toString().contains('PoolAlreadyOpenMongoPoolException')) {
        return;
      }
      print('ERROR: Failed to initialize mongo_pool: $e');
      rethrow;
    }
  }

  Future<T> dbOperation<T>(
    Future<T> Function(DbCollection collection) operation, {
    required String collectionName,
    int retries = 2,
  }) async {
    // Get existing instance (throws if not init) or assume connect() called
    MongoDbPoolService poolService;
    try {
      poolService = MongoDbPoolService.getInstance();
    } catch (_) {
      await connect();
      poolService = MongoDbPoolService.getInstance();
    }
    
    try {
      // Ensure pool is open (check connections)
      if (poolService.pool.allConnections.isEmpty) await connect();

      // Acquire a connection from the pool
      final db = await poolService.acquire();
      
      try {
        final coll = db.collection(collectionName);
        return await operation(coll);
      } finally {
        // IMPORTANT: Always release the connection back to the pool!
        poolService.release(db);
      }
    } catch (e) {
      if (retries > 0 && _isConnectionError(e)) {
        print('DB Error (pool). Retrying ($retries left): $e');
        return dbOperation(
          operation,
          collectionName: collectionName,
          retries: retries - 1,
        );
      }
      rethrow;
    }
  }

  bool _isConnectionError(dynamic error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('no master connection') ||
        msg.contains('connection closed') ||
        msg.contains('connection reset') ||
        msg.contains('socketexception') ||
        msg.contains('state.opening') ||
        msg.contains('closed') ||
        msg.contains('connection refused') ||
        msg.contains('topology was destroyed');
  }

  Future<DbCollection> collection(String name) async {
    // Legacy support
    await connect();
    final poolService = MongoDbPoolService.getInstance();
    final db = await poolService.acquire();
    print('WARNING: Direct collection() access is deprecated with Pooling. Use dbOperation().');
    // We cannot release this connection easily. 
    // Ideally we should track it or wrap it.
    // For now, this remains a leak risk if not used carefully, but existing code mostly uses dbOperation now.
    return db.collection(name);
  }

  Future<void> close() async {
    print('DEBUG: Closing mongo_pool...');
    try {
      await MongoDbPoolService.getInstance().close();
    } catch (_) {}
    print('DEBUG: mongo_pool closed.');
  }
}
