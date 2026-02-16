import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';

// Copy of the URI from .env
const String _mongoUri = 'mongodb+srv://root:root@cluster0.pfs0rzo.mongodb.net/orpheus?retryWrites=true&w=majority&appName=Cluster0';

void main() async {
  print('--- DIAGNOSTIC START ---');
  print('Dart Version: ${Platform.version}');
  print('OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  
  await testConnection('Standard (Insecure)', _mongoUri, secure: false);
  
  // Test with &tls=true appended manually + secure: true
  final uriWithTls = '$_mongoUri&tls=true';
  await testConnection('Explicit TLS=true + secure:true', uriWithTls, secure: true);

  await testConnection('Explicit TLS=true + secure:true + AllowInvalidCerts', uriWithTls, secure: true, allowInvalidCerts: true);

  print('--- DIAGNOSTIC END ---');
  exit(0);
}

Future<void> testConnection(String label, String uri, {bool secure = false, bool allowInvalidCerts = false}) async {
  print('\nTesting: $label');
  print('URI: $uri');
  print('Params -> secure: $secure, allowInvalidCerts: $allowInvalidCerts');
  
  Db? db;
  try {
    db = await Db.create(uri);
    await db.open(secure: secure, tlsAllowInvalidCertificates: allowInvalidCerts);
    print('SUCCESS: Connected!');
    
    // Try a simple operation
    final collection = db.collection('users');
    final count = await collection.count();
    print('SUCCESS: Operation "count" returned: $count');
    
  } catch (e) {
    print('FAILURE: $e');
  } finally {
    if (db != null) {
      try {
        await db.close();
        print('Closed connection.');
      } catch (_) {}
    }
  }
}
