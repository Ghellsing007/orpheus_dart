import 'dart:io';
import 'package:orpheus_dart/services/mongo_service.dart';
import 'package:mongo_dart/mongo_dart.dart';

// Copy of the URI from env
const String _mongoUri = 'mongodb+srv://root:root@cluster0.pfs0rzo.mongodb.net/orpheus?retryWrites=true&w=majority&appName=Cluster0';

void main() async {
  print('--- STRESS TEST START ---');
  print('Dart Version: ${Platform.version}');
  
  // Use the actual service class to test its concurrency logic
  final mongo = MongoService(_mongoUri);

  print('Launching 4 concurrent operations...');
  print('Service instance hash: ${mongo.hashCode}');

  
  final futures = <Future<void>>[];
  for (var i = 0; i < 4; i++) {
    futures.add(_runOperation(mongo, i));
  }

  await Future.wait(futures);
  
  print('--- STRESS TEST END ---');
  await mongo.close();
  exit(0);
}

Future<void> _runOperation(MongoService mongo, int id) async {
  try {
    // Wait a random bit to stagger slightly but still hit concurrency
    await Future.delayed(Duration(milliseconds: id * 10)); 
    print('Op #$id starting...');
    
    await mongo.dbOperation<int>((collection) async {
      // With mongo_pool, we trust the pool.
      // print('Op #$id using DB hash: ${collection.db.hashCode}'); 
      return await collection.count();
    }, collectionName: 'users');
    
    print('SUCCESS: Op #$id completed.');
  } catch (e) {
    print('FAILURE: Op #$id failed: $e');
  }
}
