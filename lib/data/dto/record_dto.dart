/// Record DTO — literal port of dto/record.dto.js.
library;

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';

Row? toRecordDto(Row? raw) {
  if (raw == null) return null;
  return {
    'id': raw['id'],
    'name': jsOr(raw['name'], ''),
    'date': jsOr(raw['date'], ''),
    'clinic': jsOr(raw['clinic'], ''),
    'service': jsOr(raw['service'], ''),
    'amount': jsNumOr0(raw['amount']),
    'payment': jsOr(raw['payment'], ''),
    'phone': jsOr(raw['phone'], ''),
    'notes': jsOr(raw['notes'], ''),
    'doctorShare': jsNumOr0(raw['doctorShare']),
    'isDebt': jsTruthy(raw['isDebt']),
    'isDebtPayment': jsTruthy(raw['isDebtPayment']),
    'debtId': raw['debtId'],
    'isPros': jsTruthy(raw['isPros']),
    '_mod': jsOr(raw['_mod'], 0),
  };
}

/// م76 — الاتجاه المعاكس لـ[toRecordDto]: هذه تكتب **صفّ تخزين**، وصفوف
/// التخزين لا تحمل منطقيات. كانت الأعلام الثلاثة تُبنى بـ`jsOr(…, false)`
/// فتُنتج منطقياً في حالتين: عند غياب المفتاح (الاحتياطي `false`)، وعند
/// وروده منطقياً أصلاً (`jsOr` يمرّر الطرف الصادق كما هو — فتصحيح
/// الاحتياطي وحده كان سيترك نصف العلة قائماً).
///
/// الدالة **بلا مستدعٍ اليوم**، لكنها مصدَّرة عبر `dto.dart`: أول استعمال
/// لها في مسار كتابة كان سيعيد فئة العلة التي عالجتها م76 من جذرها —
/// فتُثبَّت هنا لا في موضع الاستدعاء القادم.
Row toRecordDb(Row dto) {
  return {
    'id': dto['id'],
    'name': dto['name'],
    'date': dto['date'],
    'clinic': dto['clinic'],
    'service': dto['service'],
    'amount': dto['amount'],
    'payment': dto['payment'],
    'phone': jsOr(dto['phone'], ''),
    'notes': jsOr(dto['notes'], ''),
    'doctorShare': jsOr(dto['doctorShare'], 0),
    'isDebt': jsTruthy(dto['isDebt']) ? 1 : 0,
    'isDebtPayment': jsTruthy(dto['isDebtPayment']) ? 1 : 0,
    'debtId': dto['debtId'],
    'isPros': jsTruthy(dto['isPros']) ? 1 : 0,
    '_mod': jsNow(),
  };
}

List<Row> toRecordDtoList(Object? rawList) {
  if (rawList is! List) return const [];
  return [
    for (final r in rawList)
      if (r is Row && toRecordDto(r) != null) toRecordDto(r)!,
  ];
}
