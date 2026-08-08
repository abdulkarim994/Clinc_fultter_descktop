/// Patient DTO — literal port of dto/patient.dto.js.
library;

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';

Row? toPatientDto(Row? raw) {
  if (raw == null) return null;
  return {
    'id': jsOr(raw['id'], raw['name']),
    'name': jsOr(raw['name'], ''),
    'phone': jsOr(raw['phone'], ''),
    'totalSpent': jsNumOr0(raw['totalSpent']),
    'visitCount': jsNumOr0(raw['visitCount']),
    'lastVisit': raw['lastVisit'] ?? raw['last_visit'],
    'services': raw['services'] is List ? raw['services'] : const [],
    'clinics': raw['clinics'] is List ? raw['clinics'] : const [],
    'hasProsthetics': jsTruthy(raw['hasProsthetics']),
    'hasDebt': jsTruthy(raw['hasDebt']),
    '_mod': jsOr(raw['_mod'], 0),
  };
}

List<Row> toPatientDtoList(Object? rawList) {
  if (rawList is! List) return const [];
  return [
    for (final r in rawList)
      if (r is Row && toPatientDto(r) != null) toPatientDto(r)!,
  ];
}
