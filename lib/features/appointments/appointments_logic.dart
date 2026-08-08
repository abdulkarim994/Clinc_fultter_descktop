/// منطق تقويم المواعيد التقليدي — نقل حرفي من CalendarTab.vue وsearch.js:
///   • apptMap: دمج ثلاثة مصادر — جدول المواعيد + حقل appointment في
///     السجلات والتركيبات (مصدر 'rec' للقراءة فقط، كما الأصل).
///   • calendarCells: شبكة الشهر بأحدية البداية (getDay) مع خلايا الشهرين
///     المجاورين معطّلة، عدّاد مواعيد كل يوم + أول اسمين.
///   • dayDiff/dayLabel (اليوم/غداً/بعد N أيام/منذ N أيام)، to12h (ص/م)،
///     cleanPhone، upcoming (12 قادمة غير مكتملة/ملغاة)،
///     getPatientDebt، ونصوص تذكير واتساب/SMS والدين حرفياً.
///   • fuzzyMatch/levenshtein لاقتراحات الأسماء (search.js حرفياً).
library;

import '../../core/utils/ar_normalize.dart';
import '../../core/utils/js_compat.dart';
import '../../core/display_prefs.dart' show formatClockHm;

typedef JMap = Map<String, Object?>;

const monthNames = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];
const dayNames = ['أح', 'إث', 'ثل', 'أر', 'خم', 'جم', 'سب'];

/// دمج مصادر المواعيد الثلاثة — apptMap حرفياً.
Map<String, List<JMap>> buildApptMap({
  required List<JMap> appointments,
  required List<JMap> records,
  required List<JMap> prosthetics,
}) {
  final all = <JMap>[
    for (final a in appointments) {...a, '_src': 'appt'},
    for (final r in records)
      if (jsTruthy(r['appointment']))
        {
          'id': 'rec-${r['id']}',
          'name': r['name'],
          'date': r['appointment'],
          'service': r['service'],
          'phone': '',
          'notes': '',
          'status': 'upcoming',
          '_src': 'rec',
        },
    for (final p in prosthetics)
      if (jsTruthy(p['appointment']))
        {
          'id': 'pros-${p['id']}',
          'name': p['name'],
          'date': p['appointment'],
          'service': 'تركيبات',
          'phone': '',
          'notes': '',
          'status': 'upcoming',
          '_src': 'rec',
        },
  ];
  final map = <String, List<JMap>>{};
  for (final a in all) {
    final d = '${a['date'] ?? ''}';
    if (d.isEmpty) continue;
    (map[d] ??= []).add(a);
  }
  return map;
}

class CalCell {
  const CalCell({
    required this.day,
    required this.other,
    required this.isToday,
    required this.apptCount,
    required this.names,
    required this.dateStr,
  });

  final int day;
  final bool other;
  final bool isToday;
  final int apptCount;
  final String names;
  final String dateStr;
}

/// خلايا شبكة الشهر — calendarCells حرفياً (بداية الأسبوع أحد كما getDay).
List<CalCell> calendarCells(
    int year, int month0, Map<String, List<JMap>> apptMap) {
  final firstDay = DateTime(year, month0 + 1, 1).weekday % 7; // أحد=0
  final lastDate = DateTime(year, month0 + 2, 0).day;
  final prevLast = DateTime(year, month0 + 1, 0).day;
  final today = getCurrentDate();
  final cells = <CalCell>[];
  for (var i = firstDay - 1; i >= 0; i--) {
    cells.add(CalCell(
        day: prevLast - i, other: true, isToday: false,
        apptCount: 0, names: '', dateStr: ''));
  }
  for (var d = 1; d <= lastDate; d++) {
    final ds = '$year-${(month0 + 1).toString().padLeft(2, '0')}-'
        '${d.toString().padLeft(2, '0')}';
    final ap = apptMap[ds] ?? const [];
    final names = ap.map((a) => '${a['name'] ?? ''}').take(2).join('، ') +
        (ap.length > 2 ? '...' : '');
    cells.add(CalCell(
        day: d, other: false, isToday: ds == today,
        apptCount: ap.length, names: names, dateStr: ds));
  }
  final total = firstDay + lastDate;
  final rem = total % 7 != 0 ? 7 - (total % 7) : 0;
  for (var d = 1; d <= rem; d++) {
    cells.add(CalCell(
        day: d, other: true, isToday: false,
        apptCount: 0, names: '', dateStr: ''));
  }
  return cells;
}

/// فرق الأيام عن اليوم — dayDiff حرفياً (سقف القسمة).
int dayDiff(String ds) {
  final today = DateTime.parse('${getCurrentDate()}T00:00:00');
  final d = DateTime.parse('${ds}T00:00:00');
  return (d.difference(today).inMilliseconds / 86400000).ceil();
}

String dayLabel(String ds) {
  final diff = dayDiff(ds);
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'غداً';
  if (diff < 0) return 'منذ ${diff.abs()} أيام';
  return 'بعد $diff أيام';
}

/// 12 ساعة بلاحقة ص/م — to12h حرفياً.
String to12h(String? t) {
  if (t == null || t.isEmpty) return '';
  // م116 — يتبع إعداد نظام الوقت (12/24) ونظام الأرقام مركزياً.
  return formatClockHm(t);
}

String cleanPhone(Object? p) =>
    p == null ? '' : '$p'.replaceAll(RegExp(r'[^0-9+]'), '');

/// القادمة — upcoming حرفياً: من اليوم فصاعداً، لا مكتملة ولا ملغاة، 12.
List<JMap> upcomingAppts(Map<String, List<JMap>> apptMap) {
  final today = getCurrentDate();
  final all = [for (final l in apptMap.values) ...l];
  final list = [
    for (final a in all)
      if ('${a['date']}'.compareTo(today) >= 0 &&
          a['status'] != 'completed' &&
          a['status'] != 'cancelled')
        a,
  ]..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
  return list.take(12).toList();
}

/// مجموع ديون المريض غير المسددة — getPatientDebt حرفياً.
/// م-عزل الهوية — [phone] (متى مُرِّر) يعزل الدين بهوية صاحب الموعد
/// (أرقام هاتفه): دينُ سميٍّ لا يُحسب على سميّه. غيابُه = السلوك القائم
/// (كل ديون الاسم — يطابق مفاتيح الأصل حرفياً).
num getPatientDebt(List<JMap> debts, String? name, {Object? phone}) {
  if (name == null || name.isEmpty) return 0;
  final want = '${phone ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
  num s = 0;
  for (final d in debts) {
    if (d['name'] != name || d['status'] == 'paid') continue;
    if (want.isNotEmpty) {
      // هاتف الدين (أرقام فقط)؛ الدينُ عديمُ الهاتف يُنسب للجميع (إرث).
      final dp = '${d['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
      if (dp.isNotEmpty && dp != want) continue;
    }
    s += jsNumOr0(d['remaining']);
  }
  return s;
}

String _arWeekday(String? date) {
  if (date == null || date.isEmpty) return '';
  const names = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس',
    'الجمعة', 'السبت', 'الأحد',
  ];
  try {
    return names[DateTime.parse(date).weekday - 1];
  } catch (_) {
    return '';
  }
}

/// نص تذكير الموعد (واتساب) — حرفي.
String waReminderText(JMap a, String centerName) {
  final dayName = _arWeekday('${a['date'] ?? ''}');
  final time = '${a['time'] ?? ''}';
  final service = '${a['service'] ?? ''}';
  return '🏥 *$centerName*\n━━━━━━━━━━━━━━━\n📋 *تذكير بموعدكم*\n\n'
      'السلام عليكم ورحمة الله\nعزيزنا/عزيزتنا *${a['name'] ?? ''}*\n\n'
      'نود تذكيركم بموعدكم القادم:\n\n'
      '📅 التاريخ: *${a['date']}*\n📆 اليوم: *$dayName*\n'
      '${time.isNotEmpty ? '🕐 الساعة: *${to12h(time)}*\n' : ''}'
      '${service.isNotEmpty ? '🦷 الخدمة: $service\n' : ''}'
      '\nنرجو التأكيد أو التواصل معنا في حال الرغبة بتغيير الموعد.\n\n'
      '━━━━━━━━━━━━━━━\n✨ مع تمنياتنا لكم بدوام الصحة والعافية\n'
      '*$centerName* 🦷';
}

/// نص تذكير الموعد (SMS) — حرفي.
String smsReminderText(JMap a, String centerName) {
  final dayName = _arWeekday('${a['date'] ?? ''}');
  final time = '${a['time'] ?? ''}';
  return '$centerName: تذكير بموعدكم ${a['name'] ?? ''} - ${a['date']} '
      '$dayName${time.isNotEmpty ? ' الساعة ${to12h(time)}' : ''}. نرجو التأكيد.';
}

/// نص تذكير الدين (واتساب) — حرفي.
String debtWaText(JMap a, num amt, String currency, String centerName) {
  return '🏥 *$centerName*\n━━━━━━━━━━━━━━━\n📋 *تذكير بالمبلغ المتبقي*\n\n'
      'السلام عليكم\nعزيزنا/عزيزتنا *${a['name'] ?? ''}*\n\n'
      'نود تذكيركم بالمبلغ المتبقي:\n💰 المبلغ المتبقي: *$amt $currency*\n\n'
      'نرجو التواصل معنا لتسوية المبلغ.\n\n'
      '━━━━━━━━━━━━━━━\n*$centerName* 🦷';
}

/// نص تذكير الدين (SMS) — حرفي.
String debtSmsText(JMap a, num amt, String currency, String centerName) =>
    '$centerName: تذكير بالمبلغ المتبقي ${a['name'] ?? ''} - $amt $currency. '
    'نرجو التواصل لتسوية المبلغ.';

// ── البحث الضبابي (search.js حرفياً) ────────────────────────────────────────

int levenshtein(String a, String b) {
  final m = a.length, n = b.length;
  final dp = List.generate(m + 1, (i) => List<int>.filled(n + 1, 0));
  for (var i = 0; i <= m; i++) {
    dp[i][0] = i;
  }
  for (var j = 1; j <= n; j++) {
    dp[0][j] = j;
  }
  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] == b[j - 1]
          ? dp[i - 1][j - 1]
          : 1 +
              [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]]
                  .reduce((x, y) => x < y ? x : y);
    }
  }
  return dp[m][n];
}

bool fuzzyMatch(String? query, String? name) {
  if (query == null || query.isEmpty) return true;
  if (name == null || name.isEmpty) return false;
  final q = normAr(query);
  final n = normAr(name);
  if (n.contains(q)) return true;
  if (q.length <= 2) return n.startsWith(q);
  final maxDist = [2, q.length ~/ 3].reduce((x, y) => x > y ? x : y);
  return levenshtein(q, n) <= maxDist;
}

/// اقتراحات الأسماء — onApptNameInput حرفياً (سجلات + تركيبات، حد 5).
List<String> apptNameSuggestions(
    String query, List<JMap> records, List<JMap> prosthetics) {
  final q = query.trim();
  if (q.length < 2) return const [];
  final names = <String>{
    for (final r in records)
      if (jsTruthy(r['name'])) '${r['name']}',
    for (final p in prosthetics)
      if (jsTruthy(p['name'])) '${p['name']}',
  };
  return [for (final n in names) if (fuzzyMatch(q, n)) n].take(5).toList();
}

/// تعبئة الهاتف من تاريخ المريض — selectApptName حرفياً (الأحدث أولاً).
String phoneForName(String name,
    {required List<JMap> records,
    required List<JMap> prosthetics,
    required List<JMap> debts,
    required List<JMap> appointments}) {
  final all = [
    for (final r in [...records, ...prosthetics, ...debts, ...appointments])
      if (r['name'] == name) r,
  ]..sort((a, b) => '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}'));
  for (final r in all) {
    if (jsTruthy(r['phone'])) return '${r['phone']}';
  }
  return '';
}
