/// ============================================================================
///  Config Repository — port of repositories/config.repository.js
/// ============================================================================
///
///  The JS original stored the clinic config blob in the web `metadata` store
///  (IndexedDB). The Flutter build keeps the same contract (getConfig /
///  saveConfig JSON round-trip under the 'clinic_config' key) over the SQLite
///  `metadata` table — the single-backend equivalent.
library;

import 'dart:convert';

import '../db/local_db.dart';

const _configKey = 'clinic_config';

class ConfigRepository {
  ConfigRepository(this.db);

  final LocalDb db;

  Object? getConfig() {
    try {
      final row = db.queryFirst(
        'SELECT value FROM metadata WHERE key = ?',
        const [_configKey],
      );
      final v = row?['value'];
      if (v is! String || v.isEmpty) return null;
      return jsonDecode(v);
    } catch (_) {
      return null;
    }
  }

  bool saveConfig(Object? config) {
    try {
      db.execute(
        'INSERT OR REPLACE INTO metadata(key, value, updated_at) '
        "VALUES (?, ?, datetime('now'))",
        [_configKey, jsonEncode(config)],
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
