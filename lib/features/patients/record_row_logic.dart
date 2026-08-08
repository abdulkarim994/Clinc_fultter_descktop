/// منطق عرض صف السجل — دوال نقية توأم RecordRow.vue (displayService،
/// installmentLabel، شارة نوع الدفعة، وصيغة التاريخ). مفصولة عن الودجت
/// كي تُختبر مباشرة (م27).
library;

import '../../core/utils/js_compat.dart';
import '../finance/treasury_logic.dart' show installmentSeqForRecord;

typedef JMap = Map<String, Object?>;

/// displayService — تنظيف بادئات الدفعات وأخذ خدمة الدين للدفعات
/// (توأم displayService في RecordRow حرفياً): الدفعة تأخذ اسم خدمة دينها،
/// وتُزال بادئات «دفعة تركيبات —/دفعة دين —/دفعة أولى (دين)» ولواحق
/// «(دفعة…)/(دين)»، والفارغ يصبح «تركيبات» للتركيبات وإلا «زيارة».
String recordDisplayService(JMap e, {JMap? payDebt, required bool isPros}) {
  final isDebtPay = jsTruthy(e['isDebtPayment']);
  if (isDebtPay && payDebt != null && jsTruthy(payDebt['service'])) {
    return '${payDebt['service']}';
  }
  final raw = '${e['service'] ?? ''}';
  var clean = raw
      .replaceAll(RegExp(r'^دفعة تركيبات\s*[—–-]\s*'), '')
      .replaceAll(RegExp(r'^دفعة دين\s*[—–-]\s*'), '')
      .replaceAll(RegExp(r'^دفعة أولى\s*\(دين\)'), '')
      .replaceAll(RegExp(r'\s*\(دفعة[^)]*\)'), '')
      .replaceAll(RegExp(r'\s*\(دين\)'), '')
      .trim();
  if (clean.isEmpty || clean == 'دفعة أولى' || clean == 'دفعة دين') {
    if (isPros || raw.contains('تركيبات')) return 'تركيبات';
    return 'زيارة';
  }
  return clean;
}

/// شارة نوع الدفعة — سداد كلي (full) / دفعة جزئية (توأم debtPaymentType).
String payTypeBadge(Object? debtPaymentType) =>
    '$debtPaymentType' == 'full' ? 'سداد كلي' : 'دفعة جزئية';

/// installmentLabel — «دفعة N» لسجل دفعة عبر المصدر الموحّد؛ '' لغير الدفعات.
String installmentLabelFor(JMap e, JMap? payDebt, List<JMap> records) {
  if (!jsTruthy(e['isDebtPayment']) || !jsTruthy(e['debtId'])) return '';
  final seq =
      payDebt == null ? 1 : installmentSeqForRecord(payDebt, records, e);
  return 'دفعة $seq';
}

/// formatDisplayDate — YYYY-MM-DD ← DD/MM/YYYY (توأم RecordRow حرفياً).
String fmtDisplayDate(String dateStr) {
  if (dateStr.isEmpty) return '';
  final parts = dateStr.split('-');
  if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
  return dateStr;
}

/// displayPayment — «دين» يبقى «دين»؛ غيره كما هو (توأم displayPayment).
String recordDisplayPayment(Object? payment) => '${payment ?? ''}';
