/// ============================================================================
///  X-Rays Repository — port of repositories/xrays.repository.js
/// ============================================================================
///
///  Metadata + thumbnails live locally; full images live in R2. The Phase 6
///  verify-before-cleanup invariant is preserved: an offline-only capture's
///  thumbnail is the ONLY copy, so it is never cleaned up before a confirmed
///  upload.
library;

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';
import 'base_repository.dart';
import 'patients_repository.dart';

const _columns = [
  'id', 'patient_name', 'file_key', 'thumbnail_data',
  'upload_status', 'created_at', '_mod', '_deleted', 'data',
  'checksum', 'clinic_id', '_hlc', '_dirty', '_origin', 'server_seq',
  'owner_uid',
  'patient_id',
];

class XraysRepository extends BaseRepository {
  XraysRepository(LocalDb db) : super(db, 'xrays', _columns);

  /// All xrays for a specific patient.
  List<Row> getByPatient(String patientName) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM xrays WHERE _deleted = 0 AND patient_name = ?${oc.sql} '
      'ORDER BY created_at DESC',
      [patientName, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Store a thumbnail for an xray.
  void saveThumbnail(String fileKey, String thumbnailDataUrl) {
    db.execute(
      'UPDATE xrays SET thumbnail_data = ?, _mod = ? WHERE file_key = ?',
      [thumbnailDataUrl, jsNow(), fileKey],
    );
  }

  /// Get a thumbnail for an xray.
  String? getThumbnail(String fileKey) {
    final row = db.queryFirst(
      'SELECT thumbnail_data FROM xrays WHERE file_key = ? AND _deleted = 0',
      [fileKey],
    );
    return row?['thumbnail_data'] as String?;
  }

  /// Remove a thumbnail.
  void removeThumbnail(String fileKey) {
    db.execute(
      'UPDATE xrays SET thumbnail_data = NULL, _mod = ? WHERE file_key = ?',
      [jsNow(), fileKey],
    );
  }

  /// Xrays that haven't been uploaded yet (for retry).
  List<Row> getPendingUploads() {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM xrays WHERE _deleted = 0 '
      "AND upload_status = 'pending'${oc.sql} ORDER BY created_at ASC",
      oc.params,
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Mark an xray as uploaded — records the confirmed `file_key` + integrity
  /// `checksum` and marks the row `_dirty = 1` so the delta engine pushes the
  /// file_key to other devices.
  void markUploaded(String id, {String? fileKey, String? checksum}) {
    db.execute(
      "UPDATE xrays SET upload_status = 'uploaded', "
      'file_key = COALESCE(?, file_key), '
      'checksum = COALESCE(?, checksum), '
      '_dirty = 1, _mod = ? WHERE id = ?',
      [fileKey, checksum, jsNow(), id],
    );
  }

  /// Add an xray entry with metadata, stamping the stable link keys (Phase H).
  /// م-عزل الهوية — [phone] (متى مُرِّر) يُنتج `patient_id` هوياتياً
  /// (`patientKeyFor(name:, phone:)`) فيعزل صور المتشابهين: استعلامات
  /// [getByClinicPatient]/[getByPatientId] تطابق هذا المعرّف. غيابُ الهاتف
  /// وpatientId يُبقي المشتق القديم (اسم/هوية-بلا-هاتف) حرفياً.
  Row addXray(
    String patientName,
    String fileKey, {
    String? thumbnailData,
    String clinic = '',
    String clinicId = '',
    String patientId = '',
    Object? phone,
  }) {
    final xray = <String, Object?>{
      'id': fileKey,
      'patient_name': patientName,
      'file_key': fileKey,
      'thumbnail_data': thumbnailData,
      'upload_status': 'pending',
      'created_at': jsIsoNow(),
      'clinic_id': clinicId.isNotEmpty ? clinicId : clinicKeyFor(clinic),
      'patient_id': patientId.isNotEmpty
          ? patientId
          : (patientKeyFor(name: patientName, phone: '${phone ?? ''}') ?? ''),
      '_mod': jsNow(),
    };
    upsert(xray);
    return xray;
  }

  /// Phase H — one patient's xrays INSIDE one clinic, with the self-healing
  /// legacy fallback (a row with NULL keys is matched by name, never hidden).
  /// م-عزل الهوية — [phone] (متى مُرِّر) يشدّ المطابقة إلى معرّف الهاتف
  /// (`patientKeyFor(name:, phone:)`) فلا تظهر صور سميٍّ بهاتف مختلف؛ مع
  /// **تراجع اسمي** للصفوف القديمة عديمة المعرّف (لا تختفي صورة قديمة).
  /// غيابُ الهاتف = السلوك القائم حرفياً (المطابقة بمعرّف الاسم/العيادة).
  List<Row> getByClinicPatient(String? clinic, String patientName,
      {Object? phone}) {
    final cid = clinicKeyFor(clinic);
    final ph = '${phone ?? ''}';
    final pid = patientKeyFor(name: patientName, phone: ph) ??
        patientName.trim();
    if (cid.isEmpty) {
      // بلا عيادة: نطابق المعرّف الهوياتي مع تراجع اسمي للصفوف عديمة المعرّف.
      final oc = db.ownerClause();
      final rows = db.query(
        'SELECT * FROM xrays WHERE _deleted = 0 '
        "AND (patient_id = ? OR (IFNULL(patient_id,'') = '' "
        "  AND TRIM(IFNULL(patient_name,'')) = ?))${oc.sql} "
        'ORDER BY created_at DESC',
        [pid, patientName.trim(), ...oc.params],
      );
      return [for (final r in rows) parseRowData(r)!];
    }
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM xrays WHERE _deleted = 0 '
      "AND (patient_id = ? OR (IFNULL(patient_id,'') = '' "
      "  AND TRIM(IFNULL(patient_name,'')) = ?)) "
      "AND (clinic_id = ? OR IFNULL(clinic_id,'') = '')${oc.sql} "
      'ORDER BY created_at DESC',
      [pid, patientName.trim(), cid, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Phase H — xrays for a stable patient link key (clinic-agnostic).
  List<Row> getByPatientId(String? patientId) {
    final pid = (patientId ?? '').trim();
    if (pid.isEmpty) return const [];
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM xrays WHERE _deleted = 0 '
      "AND (patient_id = ? OR (IFNULL(patient_id,'') = '' AND TRIM(IFNULL(patient_name,'')) = ?))${oc.sql} "
      'ORDER BY created_at DESC',
      [pid, pid, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Clean up thumbnails older than [maxAgeMs] — Phase 6 verify-before-cleanup:
  /// NEVER nulls the thumbnail of an image that is not confirmed uploaded.
  void cleanupOldThumbnails([int maxAgeMs = 30 * 24 * 60 * 60 * 1000]) {
    final cutoff = jsNow() - maxAgeMs;
    db.execute(
      'UPDATE xrays SET thumbnail_data = NULL '
      'WHERE _mod < ? AND thumbnail_data IS NOT NULL '
      "AND upload_status = 'uploaded' AND file_key IS NOT NULL",
      [cutoff],
    );
  }

  /// Count xrays for a patient.
  int countByPatient(String patientName) {
    final oc = db.ownerClause();
    final result = db.queryFirst(
      'SELECT COUNT(*) as cnt FROM xrays '
      'WHERE _deleted = 0 AND patient_name = ?${oc.sql}',
      [patientName, ...oc.params],
    );
    return (result?['cnt'] as int?) ?? 0;
  }
}
