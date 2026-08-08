/// ============================================================================
///  Recompute-after-merge — literal port of sync/merge/recompute.js
/// ============================================================================
///
///  PURE, deterministic post-merge step for entities whose stored DERIVED
///  fields are computed from MULTIPLE independent inputs that are field-merged
///  separately. Re-derives those fields from the already-merged inputs so the
///  row is globally consistent again — no I/O, no live-settings read.
///
///  Contract for every registered function `(row) => row`:
///    - PURE + DETERMINISTIC (only the row's own inputs + frozen _rateSnapshot)
///    - IDEMPOTENT: f(f(x)) == f(x); returns the SAME object reference when
///      nothing changes (no churn / no re-stamp)
///    - CARVE-OUT: prosthetics without a valid frozen snapshot are returned
///      UNCHANGED (never read live settings here).
library;

import '../../../core/utils/js_compat.dart';

typedef DomainRow = Map<String, Object?>;
typedef RecomputeFn = DomainRow Function(DomainRow row);

/// prosthetics: doctorShare / clinicShare derive from `total` and `labValue`,
/// split by the frozen snapshot's doctorPct (mirrors calculateProstheticShares
/// for rows that carry a snapshot).
DomainRow recomputeProsthetics(DomainRow row) {
  final snap = row['_rateSnapshot'];
  final snapPct = snap is Map ? jsNumber(snap['doctorPct']) : double.nan;
  // Legacy carve-out: no frozen pct → leave the row as field-merged.
  if (snap is! Map || snapPct.isNaN || snapPct.isInfinite) return row;
  final pct = snapPct.clamp(0, 100);
  // م67 — نفس علّة الديون: التركيبة قد تحمل الإجمالي في العمود total_amount
  // وحده (صفوف Vue القديمة). القيمة الطازجة `total` أولاً ثم العمود ملاذاً.
  final total = jsNumOr0(row['total'] ?? row['total_amount']);
  final labValue = jsNumOr0(row['labValue']);
  final profit = total - labValue;
  final doctorShare = jsRound(profit * (pct / 100));
  final clinicShare = profit - doctorShare;
  // Idempotent: already consistent → same reference (no churn).
  if (_numEq(row['doctorShare'], doctorShare) &&
      _numEq(row['clinicShare'], clinicShare)) {
    return row;
  }
  return {...row, 'doctorShare': doctorShare, 'clinicShare': clinicShare};
}

List<Map> _activeInstallments(Object? arr) {
  if (arr is! List) return const [];
  return [
    for (final el in arr)
      if (el is Map && jsNumber(el['_deleted']) != 1) el,
  ];
}

/// debts: paidAmount / remaining / status are aggregates of the payment
/// `installments` array (the ONLY source of truth for payments). Re-derives
/// them from the already-merged installments so no payment is ever lost.
/// Status thresholds mirror DebtsTab.vue EXACTLY: remaining<=0.01 → paid
/// (remaining clamped to 0), else paidAmount>0.01 → partial, else unpaid.
DomainRow recomputeDebts(DomainRow row) {
  final items = _activeInstallments(row['installments']);
  final paid = items.fold<double>(0, (s, el) => s + jsNumOr0(el['amount']));
  // دفعة أول/ب (م67) — أضيف `total_amount` (العمود الحقيقي) إلى سلسلة قراءة
  // الإجمالي. كانت تقرأ total ?? totalAmount فقط، فدينٌ كتبه تطبيق Vue القديم
  // بالإجمالي في العمود snake_case وحده كان يُعاد حسابه إلى إجمالي صفر ⇒
  // متبقٍ صفر ⇒ حالة «مسدَّد» — دين يُشطب بصمت. الترتيب يقدّم القيم الطازجة
  // (camelCase التي يعدّلها منطق الأعمال) ثم العمود كملاذ للصفوف القديمة.
  final total = jsNumOr0(row['total'] ?? row['totalAmount'] ?? row['total_amount']);
  var remaining = (total - paid) > 0 ? (total - paid) : 0.0;
  String status;
  if (remaining <= 0.01) {
    remaining = 0;
    status = 'paid';
  } else if (paid > 0.01) {
    status = 'partial';
  } else {
    status = 'unpaid';
  }
  final isPros = row['type'] == 'prosthetic';
  final labValue = jsNumOr0(row['labValue']);
  final labPaid = isPros ? (labValue < paid ? labValue : paid) : row['labPaid'];
  // Idempotent: already consistent → same reference.
  final same = _numEq(row['paidAmount'], paid) &&
      _numEq(row['remaining'], remaining) &&
      row['status'] == status &&
      (!isPros || _numEq(row['labPaid'], labPaid as num));
  if (same) return row;
  final out = <String, Object?>{
    ...row,
    'paidAmount': paid,
    'remaining': remaining,
    'status': status,
  };
  if (isPros) out['labPaid'] = labPaid;
  return out;
}

bool _numEq(Object? a, num b) => a is num && a == b;

/// Registry of per-entity recompute functions. An entity with NO entry is left
/// completely untouched (identity).
final Map<String, RecomputeFn> recomputeByEntity = {
  'prosthetics': recomputeProsthetics,
  'debts': recomputeDebts,
};

/// Apply the registered recompute for [entity]. Identity (same reference) when
/// the entity has no registered fn.
DomainRow applyRecompute(String? entity, DomainRow row) {
  final fn = recomputeByEntity[entity];
  return fn == null ? row : fn(row);
}
