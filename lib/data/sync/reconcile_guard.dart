/// ============================================================================
///  Reconcile (delete) guard — literal port of sync/reconcileGuard.js
/// ============================================================================
///
///  The phantom-delete fix (Problem #6): delete-reconciliation may tombstone a
///  durable row ONLY when memory is a COMPLETE mirror of the repo. Until the
///  hydration gate flips, `shouldTombstone` refuses to delete anything —
///  fail-safe: worst case a delete lands one cycle later, never data loss.
library;

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';

bool _hydrated = false;

/// Mark memory as a complete mirror of the repo (after a successful hydrate).
void setHydrationReady([bool value = true]) => _hydrated = value;

/// Is memory a complete authoritative mirror this session?
bool isHydrationReady() => _hydrated;

/// Re-arm the gate (logout / store reset).
void resetHydrationReady() => _hydrated = false;

/// May this repo row be tombstoned by delete-reconciliation?
/// TRUE only when: gate open, row has id, not already tombstoned, and absent
/// from the authoritative memory set. FALSE in every ambiguous case.
bool shouldTombstone(
  Row? repoRow,
  Set<String>? memIds, {
  bool? hydrated,
}) {
  if (!(hydrated ?? isHydrationReady())) return false;
  final id = repoRow?['id'];
  if (repoRow == null || id == null || id == '') return false;
  if (jsNumber(repoRow['_deleted']) == 1) return false;
  if (memIds != null && memIds.contains(id)) return false;
  return true;
}
