import 'package:drift/drift.dart';

import '../auth/secure_session_storage.dart';
import 'database_scope.dart';

QueryExecutor openNativeDatabase(DatabaseScope scope, {SecretStore? store}) =>
    throw UnsupportedError('Durable SQLite is supported on native platforms.');
