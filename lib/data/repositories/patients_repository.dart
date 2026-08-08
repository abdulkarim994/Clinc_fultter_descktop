/// ============================================================================
///  Patients Repository — literal port of repositories/patients.repository.js
/// ============================================================================
///
///  Includes the stable-key derivers (`patientKeyFor` / `clinicKeyFor` /
///  `clinicScopedKey`) — the single source of truth the repos, DTOs and
///  migrations all share, preserved with identical semantics (including the
///  PHONE_IDENTITY gate defaulting to the legacy TRIM(name) key).
library;

import '../../core/utils/ar_normalize.dart';
import '../db/local_db.dart';
import '../sync/feature_flags.dart';
import 'base_repository.dart';

const _columns = [
  'id', 'name', 'phone', 'notes', 'last_visit',
  'created_at', 'updated_at', '_mod', '_deleted', 'data', 'owner_uid',
  '_hlc', '_dirty', '_origin', 'server_seq', 'clinic_id',
  'patient_id',
];

/// Phase C4 — only reach for the server when the local search returns FEWER
/// than this many hits.
const coldSearchMinLocal = 5;

/// Phase A — single source of truth for a patient's stable link key.
/// PHONE_IDENTITY OFF (default) → `TRIM(name) || null` (legacy, byte-for-byte).
/// ON → deterministic identity key: `p:<normPhone>:<normAr(name)>` or
/// `n:<normAr(name)>`.
String? patientKeyFor({String? name, String? phone}) {
  if (!isPhoneIdentityEnabled()) {
    final t = (name ?? '').trim();
    return t.isEmpty ? null : t;
  }
  final nm = normAr(name ?? '');
  final ph = normPhone(phone);
  if (nm.isEmpty && ph.isEmpty) return null;
  return ph.isNotEmpty ? 'p:$ph:$nm' : 'n:$nm';
}

/// Back-compat alias — with PHONE_IDENTITY OFF identical to TRIM(name).
String? patientIdForName(String? name) => patientKeyFor(name: name);

/// م-عزل الهوية — **الحلّال الموحّد** لمعرّف المريض الفعلي على أي صف
/// (سجل/تركيبة/دين/موعد/أشعة أو صف مرضى). المصدر الوحيد للحقيقة الذي
/// تشترك فيه الكتابة (record_saver) والاكتساح والردم:
///
///  • إن حمل الصفُّ `patient_id` **غير فارغ وغير مساوٍ TRIM(name)** فهو
///    معرّف هوياتي مسكوك سلفاً (p:هاتف:اسم أو n:اسم أو PID خادمي) —
///    يُعتمد كما هو (لا نعيد اشتقاق فوق هوية موجودة).
///  • وإلا يُشتق من (اسم الصف + هاتفه) عبر [patientKeyFor] — فيفصل
///    سميّين بهاتفين مختلفين حتى لو كان عمود patient_id القديم = الاسم.
///
/// يقبل مفاتيح الاسم بكلا الشكلين (`name` للصفوف المالية، `patient_name`
/// للأشعة) فيعمل موحّداً عبر كل الجداول.
String? resolvePid(Map<Object?, Object?> row) {
  final rawName = (row['name'] ?? row['patient_name']);
  final name = rawName is String ? rawName : '${rawName ?? ''}';
  final existing = '${row['patient_id'] ?? ''}'.trim();
  if (existing.isNotEmpty && existing != name.trim()) return existing;
  return patientKeyFor(name: name, phone: '${row['phone'] ?? ''}');
}

/// Phase H — single source of truth for a clinic's stable id
/// (`clinic_id == TRIM(clinic)` — deterministic, sync-stable).
String clinicKeyFor(String? clinic) => (clinic ?? '').trim();

/// Phase H — composite clinic-scoped patient key `clinic_id|patient_id`.
String? clinicScopedKey({String? clinic, String? name, String? phone}) {
  final ck = clinicKeyFor(clinic);
  final pk = patientKeyFor(name: name, phone: phone) ?? '';
  if (ck.isEmpty && pk.isEmpty) return null;
  return '$ck|$pk';
}

/// Phase C4 hook — server phone-search (Supabase), injected when the cloud
/// layer is wired (M5). Returns already-mapped rows; local always wins on id.
typedef ColdPhoneSearch = List<Row> Function(String query);

class PatientsRepository extends BaseRepository {
  PatientsRepository(LocalDb db) : super(db, 'patients', _columns);

  /// Cold-search + online-state hooks (test/DI seams; both default "offline",
  /// so every gate keeps its byte-identical default behaviour).
  ColdPhoneSearch? coldPhoneSearch;
  bool Function() isOnline = () => false;

  /// Search patients by name — FTS5 fast path with the normalised index,
  /// falling back to the LIKE scan on ANY failure (behaviour can only
  /// improve, never regress).
  List<Row> searchByName(String? query) {
    if (query == null || query.trim().isEmpty) return getAll();

    // ── Phase 4.2 FTS5 fast path ──
    final tokens =
        arNorm(query).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isNotEmpty) {
      try {
        final match =
            tokens.map((t) => '"${t.replaceAll('"', '""')}"*').join(' ');
        final uid = db.getOwnerUid();
        final ownerSql =
            uid != null ? ' AND (p.owner_uid = ? OR p.owner_uid IS NULL)' : '';
        final rows = db.query(
          'SELECT p.* FROM patients_fts f JOIN patients p ON p.rowid = f.rowid '
          'WHERE f.norm MATCH ? AND p._deleted = 0$ownerSql '
          'ORDER BY p.last_visit DESC',
          uid != null ? [match, uid] : [match],
        );
        return _coldAugment(query, [for (final r in rows) parseRowData(r)!]);
      } catch (_) {
        /* fall through to LIKE */
      }
    }
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM patients WHERE _deleted = 0 AND name LIKE ?${oc.sql} '
      'ORDER BY last_visit DESC',
      ['%${query.trim()}%', ...oc.params],
    );
    return _coldAugment(query, [for (final r in rows) parseRowData(r)!]);
  }

  /// Phase C4 — "local first, then server" augmentation. STRICTLY gated:
  /// flag OFF / offline / non-phone query / enough local hits → local
  /// untouched. Only then phone-search the server and merge (local wins on id
  /// clash — cold can only ADD). Any error falls back to local.
  List<Row> _coldAugment(String query, List<Row> local) {
    try {
      if (!isColdFetchEnabled() || !isOnline()) return local;
      if (normPhone(query).isEmpty) return local;
      if (local.length >= coldSearchMinLocal) return local;
      final search = coldPhoneSearch;
      if (search == null) return local;
      final cold = search(query);
      return _mergeById(local, cold);
    } catch (_) {
      return local;
    }
  }

  /// utils/coldMerge.mergeById — local always wins on id clash.
  static List<Row> _mergeById(List<Row> local, List<Row> cold) {
    final seen = {for (final r in local) r['id']};
    return [
      ...local,
      for (final r in cold)
        if (!seen.contains(r['id'])) r,
    ];
  }

  /// Patients with recent visits (dashboard).
  List<Row> getRecentPatients([int limit = 20]) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM patients WHERE _deleted = 0${oc.sql} '
      'ORDER BY last_visit DESC LIMIT ?',
      [...oc.params, limit],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// One keyset page of patients, most recently visited first.
  PageResult getPatientsPage({int limit = 50, PageCursor? cursor}) =>
      getPage(orderBy: 'last_visit', dir: 'DESC', limit: limit, cursor: cursor);

  /// Build/refresh the patients table from records + prosthetics — literal
  /// port of cacheFromRecords (last_visit = max date, _mod = max _mod,
  /// patient_id stamped via the stable deriver).
  List<Row> cacheFromRecords(List<Row>? records, List<Row>? prosthetics) {
    final patientMap = <String, Row>{};
    final allRecs = [...(records ?? const []), ...(prosthetics ?? const [])];

    for (final r in allRecs) {
      final rawName = r['name'];
      if (rawName is! String || rawName.trim().isEmpty) continue;
      final name = rawName.trim();
      final existing = patientMap[name] ??
          <String, Object?>{
            'id': name,
            'name': name,
            'patient_id': patientIdForName(name),
            'last_visit': null,
            '_mod': 0,
          };

      final date = r['date'];
      final lastVisit = existing['last_visit'];
      if (lastVisit == null ||
          (date is String &&
              date.compareTo((lastVisit as String?) ?? '') > 0)) {
        if (date != null) existing['last_visit'] = date;
      }

      final mod = (r['_mod'] is num) ? (r['_mod'] as num).toInt() : 0;
      if (mod > ((existing['_mod'] as num?)?.toInt() ?? 0)) {
        existing['_mod'] = mod;
      }

      patientMap[name] = existing;
    }

    final patients = patientMap.values.toList();
    if (patients.isNotEmpty) {
      bulkUpsert(patients);
    }
    return patients;
  }
}
