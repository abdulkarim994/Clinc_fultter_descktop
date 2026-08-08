/// حوار تقرير الأسنان — نقل جوهر ToothReport.vue فوق مخطط CustomPaint:
/// وضع «تحديد الأسنان» (teethOnly — المستعمل في الإضافة وملف المريض) يوفّق
/// الإضافة والحذف عبر كل المعالجات بنفس خوارزمية confirmReport الحرفية،
/// والوضع الكامل يضيف معالجات (خدمة + كلفة لكل مجموعة أسنان) مع مجموع
/// التقرير ومزامنة قيمة النموذج عند الاختلاف > 0.01 ومعلومات المريض الطبية
/// (المصدر الوحيد: config.patientMedical[name]).
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../../core/utils/uid.dart';
import 'tooth_chart.dart';
import 'tooth_label_widget.dart';
import 'tooth_notation.dart';

typedef JMap = Map<String, Object?>;

/// نفس قائمتي ToothReport.vue.
const kDentalServices = [
  'حشو', 'حشو عصب', 'خلع', 'تنظيف', 'تاج', 'جسر', 'زراعة', 'تقويم',
  'تبييض', 'تركيب متحرك', 'حشو جمالي', 'علاج لثة',
];
const kMedicalConditions = [
  'السكري', 'ضغط الدم', 'حمل', 'أمراض القلب', 'الغدة الدرقية',
  'حساسية الأدوية', 'الربو', 'أمراض الكلى',
];

/// عناصر الأسنان الحية فقط (تصفية شواهد الحذف كما في activeItems).
List<JMap> activeTeeth(Object? teeth) => teeth is List
    ? [
        for (final t in teeth)
          if (t is Map && jsNumOr0(t['_deleted']) != 1)
            Map<String, Object?>.from(t),
      ]
    : const [];

/// مفتاح عنصر السن — م100/7: يقرأ وسم الطقم أيضاً (`q:n` دائم، `q:n:P`
/// لبني)، فسنّا الدائم واللبني بنفس الموضع لا يتصادمان في مجموعة الاختيار.
String _keyOf(Map t) => toothKeyOfTooth(t);

/// مفاتيح الأسنان الحاضرة في كل المعالجات.
Set<String> teethKeysOf(List<JMap> entries) => {
      for (final e in entries)
        for (final t in activeTeeth(e['teeth'])) _keyOf(t),
    };

/// توفيق وضع «تحديد الأسنان» — نقل حرفي لمقطع confirmReport (teethOnly):
/// 1) إسقاط الأسنان المُلغى تحديدها من كل معالجة، 2) جمع الحاضر،
/// 3) إضافة الجديد إلى معالجة حاضنة أولى (service «علاج»، cost 0).
List<JMap> reconcileTeethOnly(List<JMap> entries, Set<String> selection) {
  final out = [
    for (final e in entries)
      {
        ...e,
        if (e['teeth'] is List)
          'teeth': [
            for (final t in e['teeth'] as List)
              if (t is Map && selection.contains(_keyOf(t)))
                Map<String, Object?>.from(t),
          ],
      },
  ];
  final present = teethKeysOf(out);
  final toAdd = [
    // م100/7 — toothFromKey يكتب وسم `d:'P'` للمفاتيح اللبنية فقط؛
    // مفاتيح الدائم تنتج {q,n} القديمة بايتاً ببايت.
    for (final key in selection)
      if (!present.contains(key)) toothFromKey(key),
  ];
  if (toAdd.isNotEmpty) {
    if (out.isEmpty) {
      out.add({'id': genId(), 'teeth': <Object?>[], 'service': 'علاج', 'cost': 0});
    }
    out[0] = {
      ...out[0],
      'teeth': [...?(out[0]['teeth'] as List?), ...toAdd],
    };
  }
  return out;
}

num reportTotal(List<JMap> entries) =>
    entries.fold<num>(0, (s, e) => s + jsNumOr0(e['cost']));

class ToothReportResult {
  const ToothReportResult({
    required this.entries,
    required this.meta,
    this.updateAmount,
  });

  final List<JMap> entries;
  final JMap meta;
  final num? updateAmount;
}

/// يفتح الحوار ويعيد النتيجة عند «حفظ»، أو null عند الإلغاء.
Future<ToothReportResult?> showToothReportDialog(
  BuildContext context, {
  List<JMap> entries = const [],
  JMap meta = const {},
  bool teethOnly = false,
  String patientName = '',
  String patientPhone = '',
  List<String> services = const [],
  JMap? patientMedical,
  num formAmount = 0,
  void Function(String name, JMap medical)? onSavePatientMedical,
  // م100 — نظام العرض (Palmer/FDI) يُمرَّر من موضع الاستدعاء (سياق ريفربود).
  // الغياب = FDI حفاظاً على التوافق مع أي مستدعٍ لم يُحدَّث.
  NotationSystem notation = NotationSystem.fdi,
}) {
  return showDialog<ToothReportResult>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _ToothReportBody(
          initialEntries: entries,
          initialMeta: meta,
          teethOnly: teethOnly,
          patientName: patientName,
          patientPhone: patientPhone,
          services: services,
          patientMedical: patientMedical,
          formAmount: formAmount,
          onSavePatientMedical: onSavePatientMedical,
          notation: notation,
        ),
      ),
    ),
  );
}

class _ToothReportBody extends StatefulWidget {
  const _ToothReportBody({
    required this.initialEntries,
    required this.initialMeta,
    required this.teethOnly,
    required this.patientName,
    required this.patientPhone,
    required this.services,
    required this.patientMedical,
    required this.formAmount,
    required this.onSavePatientMedical,
    required this.notation,
  });

  final List<JMap> initialEntries;
  final JMap initialMeta;
  final bool teethOnly;
  final String patientName;
  final String patientPhone;
  final List<String> services;
  final JMap? patientMedical;
  final num formAmount;
  final void Function(String name, JMap medical)? onSavePatientMedical;
  final NotationSystem notation;

  @override
  State<_ToothReportBody> createState() => _ToothReportBodyState();
}

class _ToothReportBodyState extends State<_ToothReportBody> {
  late List<JMap> entries;
  late JMap meta;
  late Set<String> selected;

  /// م100/7 — الطقم المعروض في المخطط (دائم افتراضاً). تبديلُه يبدّل
  /// الهندسة فقط؛ الاختيار مجموعةٌ واحدة تجمع النوعين (إطباق مختلط).
  Dentition dentition = Dentition.adult;

  String currentSvc = '';
  final costCtl = TextEditingController();
  final notesCtl = TextEditingController();
  final diagCtl = TextEditingController();
  final ageCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    entries = [
      for (final e in widget.initialEntries) Map<String, Object?>.from(e),
    ];
    final rm = widget.initialMeta;
    meta = {
      'notes': jsOr(rm['notes'], ''),
      'diagnosis': jsOr(rm['diagnosis'], ''),
      'name': jsOr(rm['name'], widget.patientName),
      'phone': jsOr(rm['phone'], widget.patientPhone),
      'age': jsOr(rm['age'], ''),
      'dob': jsOr(rm['dob'], ''),
      'gender': jsOr(rm['gender'], ''),
      'conditions': [...?(rm['conditions'] as List?)],
    };
    // المصدر الوحيد للحقيقة: معلومات المريض الطبية من الإعدادات تُركَّب فوق meta.
    final med = widget.patientMedical;
    if (med != null) {
      meta['age'] = med['age'] ?? meta['age'];
      meta['gender'] = med['gender'] ?? meta['gender'];
      if (med['conditions'] is List) {
        meta['conditions'] = [...med['conditions'] as List];
      }
      meta['diagnosis'] = med['diagnosis'] ?? meta['diagnosis'];
      meta['notes'] = med['notes'] ?? meta['notes'];
    }
    selected = teethKeysOf(entries);
    // م100/7 — فتحٌ ذكي: ملفٌ كل أسنانه الموثقة لبنية (طفل) يفتح على
    // الطقم اللبني مباشرةً؛ الخليط أو الدائم أو الفارغ يفتح على الدائم.
    if (selected.isNotEmpty && selected.every((k) => k.endsWith(':P'))) {
      dentition = Dentition.primary;
    }
    notesCtl.text = '${meta['notes']}';
    diagCtl.text = '${meta['diagnosis']}';
    ageCtl.text = '${meta['age']}';
  }

  @override
  void dispose() {
    costCtl.dispose();
    notesCtl.dispose();
    diagCtl.dispose();
    ageCtl.dispose();
    super.dispose();
  }

  Set<String> get _doneTeeth => teethKeysOf(entries);

  void _toggle(String key) {
    setState(() {
      if (!selected.remove(key)) selected.add(key);
    });
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  void _addEntry() {
    if (selected.isEmpty) {
      _snack('اختر سناً واحداً على الأقل');
      return;
    }
    if (currentSvc.isEmpty) {
      _snack('اختر نوع الخدمة');
      return;
    }
    final teeth = [
      for (final k in selected) toothFromKey(k),
    ];
    setState(() {
      entries.add({
        // دفعة أول/أ (م67) — معرّف ثابت لكل عنصر تقرير. محرك الدمج يكتشف
        // القوائم كاملة المعرّفات تلقائياً فيدمجها بالمعرّف (لا قيمةً كاملة
        // بترجيح الأحدث)، فطبيبان يوثّقان أسناناً مختلفة في زيارة واحدة
        // ينجو تخطيطهما معاً بدل ضياع أحدهما. العناصر القديمة بلا معرّف
        // تسقط بأمان إلى LWW الكامل عبر حارس _allIdentified.
        'id': genId(),
        'teeth': teeth,
        'service': currentSvc,
        'cost': jsNumOr0(costCtl.text),
      });
      selected = {};
      currentSvc = '';
      costCtl.clear();
    });
    _snack('تمت إضافة المعالجة');
  }

  JMap _metaOut() => {
        ...meta,
        'notes': notesCtl.text,
        'diagnosis': diagCtl.text,
        'age': ageCtl.text,
      };

  Future<void> _confirm() async {
    if (widget.teethOnly) {
      Navigator.pop(
        context,
        ToothReportResult(
          entries: reconcileTeethOnly(entries, {...selected}),
          meta: _metaOut(),
        ),
      );
      return;
    }
    if (entries.isEmpty) {
      _snack('⚠ لم تُضف أي معالجة — التقرير فارغ');
      Navigator.pop(context);
      return;
    }
    num? updateAmount;
    final rTotal = reportTotal(entries);
    final entryAmt = widget.formAmount;
    if (entryAmt > 0 && (rTotal - entryAmt).abs() > 0.01) {
      final sync = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('اختلاف المجموع'),
          content: Text(
              '⚠️ مجموع تكاليف التقرير ($rTotal) يختلف عن قيمة النموذج ($entryAmt).\nتحديث قيمة النموذج تلقائياً؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('تخطي')),
            FilledButton(
                key: const Key('tr-sync-amount'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('تحديث')),
          ],
        ),
      );
      if (sync == true) updateAmount = rTotal;
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      ToothReportResult(
        entries: entries,
        meta: _metaOut(),
        updateAmount: updateAmount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allServices = {...widget.services, ...kDentalServices}.toList();
    final conditions = [...?(meta['conditions'] as List?)];

    return Padding(
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.teethOnly ? 'تحديد الأسنان' : 'تقرير الأسنان',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: BrandColors.goldDark),
                  ),
                ),
                // م100/7 — تبديل الطقم (دائم/لبني) في صف العنوان نفسه:
                // كلفة رأسية صفر، فلا يهبط صندوق «الأسنان المحددة» تحت
                // حافة الرؤية على الهواتف الصغيرة (بلاغ ما بعد 101).
                SizedBox(
                  height: 28,
                  child: SegmentedButton<Dentition>(
                    key: const Key('tr-dentition'),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle:
                          WidgetStatePropertyAll(TextStyle(fontSize: 11)),
                      padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 9)),
                    ),
                    segments: const [
                      ButtonSegment(
                          value: Dentition.adult, label: Text('دائم')),
                      ButtonSegment(
                          value: Dentition.primary, label: Text('لبني')),
                    ],
                    selected: {dentition},
                    onSelectionChanged: (s) =>
                        setState(() => dentition = s.first),
                    showSelectedIcon: false,
                  ),
                ),
                IconButton(
                  key: const Key('tr-close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),

            // ── المخطط ──
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    ToothChart(
                      selected: selected,
                      done: _doneTeeth,
                      onToggle: _toggle,
                      dentition: dentition,
                      system: widget.notation,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 34),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(27, 94, 71, .05),
                        border: Border.all(
                            color: const Color.fromRGBO(27, 94, 71, .15)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: selected.isEmpty
                          ? Text('اختر أسناناً من المخطط',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11, color: BrandColors.mut2))
                          : Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                for (final key in selected)
                                  InputChip(
                                    key: Key('tr-sel-$key'),
                                    // م100 — عرضٌ صحيح (Palmer بإطار ربعي
                                    // أو FDI رقمين) بدل المفتاح الخام UR:6.
                                    label: ToothLabelView(
                                      toothLabelFromKey(key,
                                          system: widget.notation),
                                      color: BrandColors.brand700,
                                      scale: 0.75,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onDeleted: () =>
                                        setState(() => selected.remove(key)),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // ── الخدمة والتكلفة (الوضع الكامل) ──
            if (!widget.teethOnly) ...[
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        key: const Key('tr-service'),
                        initialValue: currentSvc.isEmpty ? null : currentSvc,
                        items: [
                          for (final s in allServices)
                            DropdownMenuItem(value: s, child: Text(s)),
                        ],
                        onChanged: (v) =>
                            setState(() => currentSvc = v ?? ''),
                        decoration:
                            const InputDecoration(labelText: 'اختر الخدمة'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('tr-cost'),
                        controller: costCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'التكلفة (اختياري)'),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('tr-add-entry'),
                          onPressed: _addEntry,
                          icon: const Icon(Icons.add_circle_outline_rounded,
                              size: 16),
                          label: const Text('إضافة المعالجة'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (entries.isEmpty)
                Padding(
                  padding: EdgeInsets.all(10),
                  child: Text('لا توجد معالجات مضافة بعد',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: BrandColors.mut2)),
                )
              else
                for (var i = 0; i < entries.length; i++)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text('${entries[i]['service']}',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        [
                          for (final t in activeTeeth(entries[i]['teeth']))
                            _keyOf(t),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${jsNumOr0(entries[i]['cost'])}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: BrandColors.brand700)),
                          IconButton(
                            key: Key('tr-del-entry-$i'),
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 17, color: BrandColors.red),
                            onPressed: () =>
                                setState(() => entries.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (entries.isNotEmpty)
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        Text('إجمالي التقرير',
                            style: TextStyle(
                                fontSize: 11.5, color: BrandColors.mut2)),
                        Text('${reportTotal(entries)}',
                            key: const Key('tr-total'),
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: BrandColors.goldDark)),
                      ],
                    ),
                  ),
                ),

              // ── معلومات المريض الطبية ──
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('معلومات المريض',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12.5)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('tr-age'),
                              controller: ageCtl,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: 'العمر'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: const Key('tr-gender'),
                              initialValue: '${meta['gender']}'.isEmpty
                                  ? null
                                  : '${meta['gender']}',
                              items: const [
                                DropdownMenuItem(
                                    value: 'ذكر', child: Text('ذكر')),
                                DropdownMenuItem(
                                    value: 'أنثى', child: Text('أنثى')),
                              ],
                              onChanged: (v) =>
                                  setState(() => meta['gender'] = v ?? ''),
                              decoration:
                                  const InputDecoration(labelText: 'الجنس'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          for (final c in kMedicalConditions)
                            FilterChip(
                              key: Key('tr-cond-$c'),
                              label: Text(c,
                                  style: const TextStyle(fontSize: 11)),
                              selected: conditions.contains(c),
                              visualDensity: VisualDensity.compact,
                              onSelected: (on) => setState(() {
                                final list = [
                                  ...?(meta['conditions'] as List?)
                                ];
                                on ? list.add(c) : list.remove(c);
                                meta['conditions'] = list;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('tr-diagnosis'),
                        controller: diagCtl,
                        decoration:
                            const InputDecoration(labelText: 'التشخيص'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('tr-notes'),
                        controller: notesCtl,
                        decoration:
                            const InputDecoration(labelText: 'ملاحظات'),
                      ),
                      if (widget.onSavePatientMedical != null) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            key: const Key('tr-save-medical'),
                            onPressed: () {
                              final name = '${_metaOut()['name']}'.trim();
                              if (name.isEmpty) {
                                _snack('لا يمكن الحفظ بدون اسم المريض');
                                return;
                              }
                              final m = _metaOut();
                              widget.onSavePatientMedical!(name, {
                                'age': jsOr(m['age'], ''),
                                'gender': jsOr(m['gender'], ''),
                                'conditions': [
                                  ...?(m['conditions'] as List?)
                                ],
                                'diagnosis': jsOr(m['diagnosis'], ''),
                                'notes': jsOr(m['notes'], ''),
                              });
                              _snack('تم حفظ معلومات المريض');
                            },
                            child: const Text('حفظ معلومات المريض'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            // ── الحفظ ──
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('tr-confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.gold,
                  foregroundColor: BrandColors.brand900,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: _confirm,
                icon: const Icon(Icons.check_rounded, size: 16),
                label: Text(widget.teethOnly ? 'حفظ' : 'حفظ التقرير',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
