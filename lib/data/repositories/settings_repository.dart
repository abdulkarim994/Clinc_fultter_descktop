/// ============================================================================
///  Settings Repository — port of repositories/settings.repository.js
/// ============================================================================
///
///  One row per setting key: a null/partial server value can never wipe the
///  whole config blob. Includes the `setBaseline` seed semantics — the fix for
///  "clinic names revert to default on reinstall": a baseline row is never
///  pushed (`_dirty = 0`) and always loses the merge (sentinel HLC '0:0:seed').
library;

import 'dart:convert';

import '../settings/config_rows.dart';

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';

const seedHlc = '0:0:seed';

class SettingsRepository {
  SettingsRepository(this.db);

  final LocalDb db;

  /// v30 — قراءة `app.config` = تركيب الكتلة القديمة + صفوف الأوراق
  /// والعناصر المستقلة (المصدر الحقيقي للإعدادات بعد v30).
  Map<String, Object?> assembledConfig() {
    final raw = _rawValue('app.config');
    final blob = raw is Map ? Map<String, Object?>.from(raw) : <String, Object?>{};
    return assembleConfig(
      blob: blob,
      leafRows: rowsWithPrefix(kCfgLeafPrefix),
      itemRows: rowsWithPrefix(kCfgItemPrefix),
    );
  }

  /// صفوف ببادئة مع حالة الحذف (لازمة لتطبيق شواهد القبور).
  Map<String, CfgRow> rowsWithPrefix(String prefix) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT id, value, _deleted FROM settings WHERE id LIKE ?${oc.sql}',
      ['$prefix%', ...oc.params],
    );
    final out = <String, CfgRow>{};
    for (final r in rows) {
      out['${r['id']}'] =
          CfgRow(_decode(r['value']), jsNumber(r['_deleted']) == 1);
    }
    return out;
  }

  Object? _rawValue(String key) {
    final oc = db.ownerClause();
    final row = db.queryFirst(
      'SELECT * FROM settings WHERE id = ? AND _deleted = 0${oc.sql}',
      [key, ...oc.params],
    );
    if (row == null) return null;
    return _decode(row['value']);
  }

  /// Read a single setting value (JSON-decoded) by key.
  Object? get(String key) {
    // v30 — الإعدادات تُقرأ مركّبة من صفوفها المستقلة (وnull إن لم يوجد
    // أي شيء بعد، كسلوك الصف الغائب سابقاً).
    if (key == 'app.config') {
      final asm = assembledConfig();
      if (asm.isEmpty) return null;
      return asm;
    }
    final oc = db.ownerClause();
    final row = db.queryFirst(
      'SELECT * FROM settings WHERE id = ? AND _deleted = 0${oc.sql}',
      [key, ...oc.params],
    );
    if (row == null) return null;
    final value = row['value'];
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  /// Read all settings as a flat map { key: value }.
  Map<String, Object?> getAll() {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM settings WHERE _deleted = 0${oc.sql}',
      oc.params,
    );
    final out = <String, Object?>{};
    for (final r in rows) {
      final parsed = parseRowData(r)!;
      out[parsed['id'] as String] = _decode(parsed['value']);
    }
    return out;
  }

  /// Upsert a single setting key/value (stamped `_dirty = 1`).
  bool set(
    String key,
    Object? value, {
    String clinicId = '',
    String? hlc,
    String? origin,
    /// v30 — لقطة الإعدادات التي بنت عليها الواجهة قيمتها الجديدة. تمريرها
    /// يجعل الفرق **مطابقاً لنيّة المستخدم تماماً**: يُكتب ما غيّره فقط،
    /// فلا تُرجَع قيمة قديمة فوق تعديل وصل من جهاز آخر بين القراءة والحفظ.
    Map<String, Object?>? configBase,
  }) {
    // كل مستدعيات set في التطبيق الأصلي تمرر hlc/origin صراحةً
    // (writeThrough: hlc: tick(deviceId())). نجعل ذلك الافتراضي هنا حتى لا
    // يعلق صف إعدادات بلا ساعة فلا يُمسح علمه بعد الإقرار أبداً.
    hlc ??= db.hlc.tick(db.deviceId);
    origin ??= db.deviceId;
    // v27 — ختم كل ورقة تغيّرت داخل أشجار الإعدادات بساعتها: هو ما يجعل
    // تعديل جهازين لحقلين مختلفين ينجو معاً (لا حسم بساعة الصف كله).
    // v30 — حفظ الإعدادات = كتابة **الصفوف المتغيّرة فقط**: كل ورقة
    // إعداد وكل عنصر قائمة صفٌّ مستقل يتزامن بنفسه، فلا تُلمس إعدادات
    // لم يغيّرها المستخدم ولا يمكن لجهاز أن يمسح عمل الآخر.
    if (key == 'app.config' && value is Map) {
      final before = configBase ?? assembledConfig();
      final after = Map<String, Object?>.from(value);
      final writes = diffConfigToRows(before, after);
      for (final w in writes) {
        if (w.delete) {
          softDelete(w.key);
        } else {
          set(w.key, w.value);
        }
      }
      // الكتلة القديمة لا تُكتب مطلقاً بعد v30 (أرشيف قراءة فقط).
      return true;
    }
    final encoded = jsonEncode(value);
    final owner = db.getOwnerUid();
    db.execute(
      'INSERT INTO settings (id, clinic_id, value, updated_at, _mod, _hlc, _dirty, _origin, owner_uid) '
      "VALUES (?, ?, ?, datetime('now'), ?, ?, 1, ?, ?) "
      'ON CONFLICT(id) DO UPDATE SET value = ?, clinic_id = ?, '
      "updated_at = datetime('now'), "
      // v30 — إعادة كتابة صف كان محذوفاً تُحييه بساعة جديدة.
      '_deleted = 0, '
      '_mod = ?, _hlc = ?, _dirty = 1, _origin = ?, owner_uid = ?',
      [
        key, clinicId, encoded, jsNow(), hlc, origin, owner, //
        encoded, clinicId, jsNow(), hlc, origin, owner,
      ],
    );
    return true;
  }

  /// v30 — نوايا صريحة لتعديل الإعدادات: كل نداء يمس صفاً واحداً فقط.
  /// (الحذف بشاهد قبر ⇒ حتمي بلا بعث، والإضافة صفٌّ مستقل ⇒ لا تتعارض
  /// إضافتان من جهازين أبداً.)
  bool configSetLeaf(List<String> path, Object? value) =>
      set('$kCfgLeafPrefix${joinCfgPath(path)}', {'v': value});

  bool configRemoveLeaf(List<String> path) =>
      softDelete('$kCfgLeafPrefix${joinCfgPath(path)}');

  bool configAddItem(List<String> listPath, Object? item, {num? order}) {
    final list = assembledConfig();
    Object? cur = list;
    for (final seg in listPath) {
      cur = cur is Map ? cur[seg] : null;
    }
    final n = cur is List ? cur.length : 0;
    return set(
      '$kCfgItemPrefix${joinCfgPath(listPath)}:${encSeg(itemSlug(item))}',
      {'v': item, 'o': order ?? n},
    );
  }

  bool configRemoveItem(List<String> listPath, Object? item) => softDelete(
      '$kCfgItemPrefix${joinCfgPath(listPath)}:${encSeg(itemSlug(item))}');

  /// v29 — كل صفوف الإعدادات التي يبدأ مفتاحها ببادئة (الحيّة فقط).
  /// أساس مخزن «كل مرحلة صف مستقل»: البادئة تجمع مراحل مريض واحد.
  Map<String, Object?> valuesWithPrefix(String prefix) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM settings WHERE id LIKE ? AND _deleted = 0${oc.sql}',
      ['$prefix%', ...oc.params],
    );
    final out = <String, Object?>{};
    for (final r in rows) {
      final id = '${r['id']}';
      out[id] = _decode(r['value']);
    }
    return out;
  }

  /// هل المفتاح موجود **حتى لو كان محذوفاً** (شاهد قبر)؟ يمنع استيراد
  /// مرحلة حُذفت سابقاً فتعود للحياة.
  bool existsIncludingDeleted(String key) {
    final oc = db.ownerClause();
    final row = db.queryFirst(
      'SELECT id FROM settings WHERE id = ?${oc.sql}',
      [key, ...oc.params],
    );
    return row != null;
  }

  /// v29 — حذف ناعم يتزامن: شاهد قبر بساعة جديدة (الحذف يصل كل الأجهزة
  /// حتماً ولا يُبعث، بعكس «غياب عنصر من كتلة» الذي لا يمكن تمييزه).
  bool softDelete(String key, {String? hlc, String? origin}) {
    hlc ??= db.hlc.tick(db.deviceId);
    origin ??= db.deviceId;
    final oc = db.ownerClause();
    final row = db.queryFirst(
      'SELECT id FROM settings WHERE id = ?${oc.sql}',
      [key, ...oc.params],
    );
    if (row == null) {
      // لا صف محلي: نكتب شاهد القبر مباشرة كي ينتشر الحذف.
      final owner = db.getOwnerUid();
      db.execute(
        'INSERT INTO settings (id, clinic_id, value, updated_at, _mod, _hlc, '
        '_dirty, _deleted, _origin, owner_uid) '
        "VALUES (?, '', NULL, datetime('now'), ?, ?, 1, 1, ?, ?) "
        'ON CONFLICT(id) DO UPDATE SET _deleted = 1, _dirty = 1, '
        "updated_at = datetime('now'), _mod = ?, _hlc = ?, _origin = ?",
        [key, jsNow(), hlc, origin, owner, jsNow(), hlc, origin],
      );
      return true;
    }
    db.execute(
      'UPDATE settings SET _deleted = 1, _dirty = 1, '
      "updated_at = datetime('now'), _mod = ?, _hlc = ?, _origin = ? "
      'WHERE id = ?',
      [jsNow(), hlc, origin, key],
    );
    return true;
  }

  /// Seed a setting ONLY when it does not already exist, as a NON-dirty
  /// baseline stamped with the sentinel HLC that loses to ANY real value.
  bool setBaseline(String key, Object? value, {String clinicId = ''}) {
    final encoded = jsonEncode(value);
    final owner = db.getOwnerUid();
    // INSERT ... DO NOTHING: never clobber an existing row (real or pulled).
    db.execute(
      'INSERT INTO settings (id, clinic_id, value, updated_at, _mod, _hlc, _dirty, _origin, owner_uid) '
      "VALUES (?, ?, ?, datetime('now'), ?, ?, 0, ?, ?) "
      'ON CONFLICT(id) DO NOTHING',
      [key, clinicId, encoded, jsNow(), seedHlc, 'seed', owner],
    );
    return true;
  }

  static Object? _decode(Object? v) {
    if (v is! String) return v;
    try {
      return jsonDecode(v);
    } catch (_) {
      return v;
    }
  }
}
