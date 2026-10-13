import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../auth/secure_session_storage.dart';
import '../security/local_database_security.dart';
import 'database_scope.dart';

QueryExecutor openNativeDatabase(
  DatabaseScope scope, {
  SecretStore? store,
}) => LazyDatabase(() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  // Hash untrusted identifiers instead of allowing them into a filesystem path.
  final key = sha256
      .convert(utf8.encode(jsonEncode([scope.organizationId, scope.branchId])))
      .toString();
  return EncryptedDatabaseFactory(
    store: store ?? PlatformSecretStore(),
  ).open(File(path.join(directory.path, 'nexapos_$key.sqlite')));
});
