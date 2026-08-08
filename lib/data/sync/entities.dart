/// ============================================================================
///  Synced entities registry — literal port of sync/entities.js
/// ============================================================================
library;

import '../repositories/repositories.dart';
import 'context.dart';

/// Order is causal-friendly: parents (patients) before children.
const List<String> syncEntities = [
  'patients',
  'records',
  'prosthetics',
  'appointments',
  'debts',
  'xrays',
  'queue_patients',
  'employees',
  'expenses',
  'settings',
];

/// Repository for an entity, or null for `settings` / unknown
/// (`settings` is a key/value store, not a BaseRepository).
BaseRepository? repoFor(SyncContext ctx, String entity) {
  final r = ctx.repos;
  switch (entity) {
    case 'patients':
      return r.patients;
    case 'records':
      return r.records;
    case 'prosthetics':
      return r.prosthetics;
    case 'appointments':
      return r.appointments;
    case 'debts':
      return r.debts;
    case 'xrays':
      return r.xrays;
    case 'queue_patients':
      return r.queue;
    case 'employees':
      return r.employees;
    case 'expenses':
      return r.expenses;
    default:
      return null;
  }
}
