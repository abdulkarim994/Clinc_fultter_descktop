/// Appointment DTO — literal port of dto/appointment.dto.js (+ Phase H
/// clinic-scoped identity: stable link keys derived deterministically, never
/// overwriting a value already present).
library;

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';
import '../repositories/patients_repository.dart';

Row? toAppointmentDto(Row? raw) {
  if (raw == null) return null;
  final clinic = (jsOr(raw['clinic'], '') as String?) ?? '';
  return {
    'id': raw['id'],
    'name': jsOr(jsOr(raw['name'], raw['patient_name']), ''),
    'phone': jsOr(raw['phone'], ''),
    'date': jsOr(raw['date'], ''),
    'time': jsOr(raw['time'], ''),
    'service': jsOr(raw['service'], ''),
    'clinic': clinic,
    'status': jsOr(raw['status'], 'scheduled'),
    'notes': jsOr(raw['notes'], ''),
    'clinic_id': jsOr(raw['clinic_id'], clinicKeyFor(clinic)),
    'patient_id': jsOr(
          raw['patient_id'],
          patientKeyFor(
            name: jsOr(raw['name'], raw['patient_name']) as String?,
            phone: raw['phone'] as String?,
          ),
        ) ??
        '',
    '_mod': jsOr(raw['_mod'], 0),
  };
}

Row toAppointmentDb(Row dto) {
  final clinic = (jsOr(dto['clinic'], '') as String?) ?? '';
  return {
    'id': dto['id'],
    'name': dto['name'],
    'phone': jsOr(dto['phone'], ''),
    'date': dto['date'],
    'time': jsOr(dto['time'], ''),
    'service': jsOr(dto['service'], ''),
    'clinic': clinic,
    'status': jsOr(dto['status'], 'scheduled'),
    'notes': jsOr(dto['notes'], ''),
    'clinic_id': jsOr(dto['clinic_id'], clinicKeyFor(clinic)),
    'patient_id': jsOr(
          dto['patient_id'],
          patientKeyFor(
            name: dto['name'] as String?,
            phone: dto['phone'] as String?,
          ),
        ) ??
        '',
    '_mod': jsNow(),
  };
}

List<Row> toAppointmentDtoList(Object? rawList) {
  if (rawList is! List) return const [];
  return [
    for (final r in rawList)
      if (r is Row && toAppointmentDto(r) != null) toAppointmentDto(r)!,
  ];
}
