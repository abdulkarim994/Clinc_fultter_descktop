/// ============================================================================
///  DTO barrel — literal ports of src/dto/* (Phase 6 mappers)
/// ============================================================================
///
///  The JS DTOs are mapping FUNCTIONS between raw DB rows (post-parseRowData
///  maps) and UI-safe shapes. The Dart ports keep the exact same field-level
///  coercions (including the `||` truthiness fallbacks in the money fields) and
///  return typed maps — the typed-class layer arrives with the UI milestones.
library;

export 'appointment_dto.dart';
export 'debt_dto.dart';
export 'patient_dto.dart';
export 'record_dto.dart';
