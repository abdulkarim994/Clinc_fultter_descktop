/// Debt DTO — literal port of dto/debt.dto.js (including the `||` fallback
/// from `totalAmount` to `total` and the ≥0 clamp on `remaining`).
library;

import 'dart:math';

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';

Row? toDebtDto(Row? raw) {
  if (raw == null) return null;
  final totalAmount = jsNumOr0(jsOr(raw['totalAmount'], raw['total']));
  final paidAmount = jsNumOr0(raw['paidAmount']);
  return {
    'id': raw['id'],
    'name': jsOr(raw['name'], ''),
    'phone': jsOr(raw['phone'], ''),
    'service': jsOr(raw['service'], ''),
    'totalAmount': totalAmount,
    'total': totalAmount,
    'paidAmount': paidAmount,
    'remaining': max(0, totalAmount - paidAmount),
    'status': jsOr(raw['status'], 'unpaid'),
    'type': jsOr(raw['type'], 'normal'),
    'notes': jsOr(raw['notes'], ''),
    'date': jsOr(raw['date'], ''),
    '_mod': jsOr(raw['_mod'], 0),
  };
}

Row toDebtDb(Row dto) {
  return {
    'id': dto['id'],
    'name': dto['name'],
    'phone': jsOr(dto['phone'], ''),
    'service': jsOr(dto['service'], ''),
    'totalAmount': dto['totalAmount'],
    'total': dto['totalAmount'],
    'paidAmount': jsOr(dto['paidAmount'], 0),
    'remaining': jsOr(dto['remaining'], 0),
    'status': jsOr(dto['status'], 'unpaid'),
    'type': jsOr(dto['type'], 'normal'),
    'notes': jsOr(dto['notes'], ''),
    'date': jsOr(dto['date'], ''),
    '_mod': jsNow(),
  };
}

List<Row> toDebtDtoList(Object? rawList) {
  if (rawList is! List) return const [];
  return [
    for (final r in rawList)
      if (r is Row && toDebtDto(r) != null) toDebtDto(r)!,
  ];
}
