/// نافذة المعلومات الطبية — التوأم البصري الحرفي لـ MedicalInfoCard.vue:
///   • ترويسة: أيقونة + «المعلومات الطبية» + عنوان فرعي + زر إغلاق.
///   • البيانات الأساسية: العمر (حقل ضيّق) + الجنس (زرّا ذكر/أنثى مجزّآن).
///   • الأمراض العامة (م109 — كانت «الأمراض المزمنة والحساسية»):
///     رقائق الثمانية الحرفية — المفعّلة حمراء
///     بعلامة صح + شارة عدد.
///   • التشخيص وملاحظات طبية: أسطر قابلة للتحرير (نقطة + حقل + حذف) مع
///     صف إضافة سفلي — تُخزَّن نصاً مفصولاً بأسطر (نفس نموذج بيانات الأصل).
///   • تذييل: زر «حفظ المعلومات» أخضر عريض.
/// التخزين يبقى config.patientMedical[الاسم] = {gender, age, conditions[],
/// diagnosis, notes} — يقرؤه تقرير الأسنان وطباعة الملف كما هو.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// القائمة الحرفية — MED_CONDITIONS.
const medConditions = [
  'السكري', 'ضغط الدم', 'حمل', 'أمراض القلب',
  'الغدة الدرقية', 'حساسية الأدوية', 'الربو', 'أمراض الكلى',
];

/// يفتح المحرر ويعيد الخريطة المحفوظة أو null عند الإلغاء.
Future<Map<String, Object?>?> showMedicalInfoDialog(
  BuildContext context, {
  required String patientName,
  Map<String, Object?> initial = const {},
}) {
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) =>
        _MedicalDialog(patientName: patientName, initial: initial),
  );
}

/// نص متعدد الأسطر → أسطر مشذّبة (توأم تقسيم diagnosis/notes في الأصل).
List<String> _splitLines(Object? v) {
  final s = '${v ?? ''}';
  if (s.trim().isEmpty) return [];
  return s
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

class _MedicalDialog extends StatefulWidget {
  const _MedicalDialog({required this.patientName, required this.initial});

  final String patientName;
  final Map<String, Object?> initial;

  @override
  State<_MedicalDialog> createState() => _MedicalDialogState();
}

class _MedicalDialogState extends State<_MedicalDialog> {
  late String gender;
  late final TextEditingController ageCtl;
  late Set<String> conditions;
  late final List<String> diagnosisLines;
  late final List<String> notesLines;
  final newDiagnosisCtl = TextEditingController();
  final newNoteCtl = TextEditingController();

  // م66 — وضعا النافذة: «ورقة» عرض غير قابلة للتعديل عند وجود بيانات،
  // والقلم بجانب X يحوّل لنموذج التحرير. الإضافة الأولى (بلا بيانات)
  // تفتح النموذج مباشرة كما كانت.
  late bool viewMode;

  bool _hasAnyData() =>
      gender.isNotEmpty ||
      ageCtl.text.trim().isNotEmpty ||
      conditions.isNotEmpty ||
      diagnosisLines.isNotEmpty ||
      notesLines.isNotEmpty;

  @override
  void initState() {
    super.initState();
    gender = '${widget.initial['gender'] ?? ''}';
    ageCtl = TextEditingController(text: '${widget.initial['age'] ?? ''}');
    conditions = {
      for (final c in (widget.initial['conditions'] as List? ?? const []))
        '$c',
    };
    diagnosisLines = _splitLines(widget.initial['diagnosis']);
    notesLines = _splitLines(widget.initial['notes']);
    viewMode = _hasAnyData();
  }

  @override
  void dispose() {
    ageCtl.dispose();
    newDiagnosisCtl.dispose();
    newNoteCtl.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(context, {
      'gender': gender,
      'age': ageCtl.text.trim(),
      'conditions': conditions.toList(),
      'diagnosis': diagnosisLines.join('\n'),
      'notes': notesLines.join('\n'),
    });
  }

  // ── عناصر البناء ──────────────────────────────────────────────────────────

  Widget _sectionHead(String title, {int? count}) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(children: [
          Container(
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              color: BrandColors.gold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: BrandColors.brand700)),
          if (count != null && count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: BrandColors.brand600.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text('$count',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.brand600)),
            ),
          ],
        ]),
      );

  Widget _genderBtn(String g, IconData icon) {
    final active = gender == g;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: InkWell(
          key: Key('med-gender-$g'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => gender = active ? '' : g),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? BrandColors.gold.withValues(alpha: .16)
                  : BrandColors.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: active ? BrandColors.gold : BrandColors.line,
                  width: active ? 1.3 : .8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 15,
                    color: active
                        ? BrandColors.goldDark
                        : BrandColors.mut2),
                const SizedBox(width: 5),
                Text(g,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: active
                            ? BrandColors.goldDark
                            : BrandColors.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _conditionChip(String c) {
    final active = conditions.contains(c);
    return InkWell(
      key: Key('med-cond-$c'),
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() {
        if (active) {
          conditions.remove(c);
        } else {
          conditions.add(c);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? BrandColors.red.withValues(alpha: .12)
              : BrandColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active
                  ? BrandColors.red.withValues(alpha: .55)
                  : BrandColors.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (active) ...[
            const Icon(Icons.check_rounded,
                size: 13, color: BrandColors.red),
            const SizedBox(width: 3),
          ],
          Text(c,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: active ? BrandColors.red : BrandColors.ink)),
        ]),
      ),
    );
  }

  /// صف سطر قابل للتحرير — نقطة + حقل + زر حذف.
  Widget _listRow(List<String> lines, int i, String hint, String keyBase) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: const BoxDecoration(
              color: BrandColors.gold, shape: BoxShape.circle),
        ),
        Expanded(
          child: TextFormField(
            key: Key('$keyBase-$i'),
            initialValue: lines[i],
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9)),
            ),
            onChanged: (v) => lines[i] = v,
          ),
        ),
        IconButton(
          key: Key('$keyBase-del-$i'),
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => lines.removeAt(i)),
          icon: const Icon(Icons.close_rounded,
              size: 16, color: BrandColors.red),
        ),
      ]),
    );
  }

  /// صف الإضافة السفلي — أيقونة + حقل + زر «إضافة».
  Widget _addRow(TextEditingController ctl, List<String> lines,
      String hint, String keyName) {
    return Row(children: [
      const Icon(Icons.add_rounded, size: 16, color: BrandColors.brand600),
      const SizedBox(width: 4),
      Expanded(
        child: TextField(
          key: Key(keyName),
          controller: ctl,
          style: const TextStyle(fontSize: 12.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
          ),
          onSubmitted: (_) => _commitAdd(ctl, lines),
        ),
      ),
      TextButton(
        key: Key('$keyName-btn'),
        onPressed: () => _commitAdd(ctl, lines),
        child: const Text('إضافة', style: TextStyle(fontSize: 12)),
      ),
    ]);
  }

  void _commitAdd(TextEditingController ctl, List<String> lines) {
    final v = ctl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      lines.add(v);
      ctl.clear();
    });
  }

  // ═══ م66 — وضع الورقة (عرض غير قابل للتعديل، كورقة طبية مرتبة) ═══

  /// عنوان قسم في الورقة (شريط ذهبي + عنوان) — يُعرض فقط عند وجود محتوى.
  Widget _sheetSection(String title, List<Widget> body) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Row(children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                    color: BrandColors.gold,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.brand700)),
            ]),
          ),
          ...body,
        ],
      );

  /// سطر مسطّر (حقل: قيمة) بخط سفلي خفيف يوحي بورقة حقيقية.
  Widget _sheetField(String label, String value) => Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: BrandColors.line, width: .8)),
        ),
        child: Row(children: [
          Text('$label: ',
              style: TextStyle(fontSize: 12, color: BrandColors.mut2)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  /// سطر مرقّم/بنقطة للتشخيص والملاحظات.
  Widget _sheetBullet(String glyph, String text, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(glyph,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12.5, height: 1.5)),
          ),
        ]),
      );

  Widget _sheetBody() {
    final age = ageCtl.text.trim();
    final basic = <Widget>[
      if (age.isNotEmpty) _sheetField('العمر', age),
      if (gender.isNotEmpty) _sheetField('الجنس', gender),
    ];
    return SingleChildScrollView(
      key: const Key('med-sheet'),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: BrandColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BrandColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (basic.isNotEmpty)
              _sheetSection('البيانات الأساسية', basic),
            if (conditions.isNotEmpty)
              _sheetSection('الأمراض العامة', [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in medConditions)
                      if (conditions.contains(c))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: BrandColors.red.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color:
                                    BrandColors.red.withValues(alpha: .3)),
                          ),
                          child: Text(c,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: BrandColors.red)),
                        ),
                  ],
                ),
              ]),
            if (diagnosisLines.isNotEmpty)
              _sheetSection('التشخيص', [
                for (var i = 0; i < diagnosisLines.length; i++)
                  _sheetBullet('${i + 1}.', diagnosisLines[i],
                      BrandColors.brand600),
              ]),
            if (notesLines.isNotEmpty)
              _sheetSection('ملاحظات طبية', [
                for (final ln in notesLines)
                  _sheetBullet('•', ln, BrandColors.goldDark),
              ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: BrandColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── الترويسة ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: BrandColors.brand600.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.medical_information_rounded,
                      size: 21, color: BrandColors.brand600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          viewMode
                              ? 'الملف الطبي — ${widget.patientName}'
                              : 'المعلومات الطبية',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: BrandColors.brand700)),
                      Text(
                          viewMode
                              ? 'اضغط القلم للتعديل'
                              : 'تُحفظ ضمن ملف المريض وتتزامن تلقائياً',
                          style: TextStyle(
                              fontSize: 11.5, color: BrandColors.mut2)),
                    ],
                  ),
                ),
                // م66 — قلم التحرير (في وضع الورقة فقط) بجانب X.
                if (viewMode)
                  IconButton(
                    key: const Key('med-edit'),
                    tooltip: 'تعديل',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => viewMode = false),
                    icon: const Icon(Icons.edit_rounded,
                        size: 19, color: BrandColors.goldDark),
                  ),
                IconButton(
                  key: const Key('med-close'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ]),
            ),
            const Divider(height: 1),

            // ── الجسم: ورقة عرض (viewMode) أو نموذج تحرير ──
            if (viewMode)
              Flexible(child: _sheetBody())
            else
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // البيانات الأساسية
                    _sectionHead('البيانات الأساسية'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('العمر',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: BrandColors.mut2)),
                              const SizedBox(height: 4),
                              TextField(
                                key: const Key('med-age'),
                                controller: ageCtl,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 12.5),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'مثال: 32',
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 9),
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(9)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('الجنس',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: BrandColors.mut2)),
                              const SizedBox(height: 4),
                              Row(children: [
                                _genderBtn('ذكر', Icons.male_rounded),
                                _genderBtn('أنثى', Icons.female_rounded),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // الأمراض المزمنة والحساسية
                    _sectionHead('الأمراض العامة',
                        count: conditions.length),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in medConditions) _conditionChip(c),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // التشخيص
                    _sectionHead('التشخيص'),
                    for (var i = 0; i < diagnosisLines.length; i++)
                      _listRow(diagnosisLines, i, 'تشخيص...', 'med-dx'),
                    _addRow(newDiagnosisCtl, diagnosisLines,
                        'أضف تشخيصاً جديداً...', 'med-dx-add'),
                    const SizedBox(height: 14),

                    // ملاحظات طبية
                    _sectionHead('ملاحظات طبية'),
                    for (var i = 0; i < notesLines.length; i++)
                      _listRow(notesLines, i, 'معلومة طبية...', 'med-nt'),
                    _addRow(newNoteCtl, notesLines,
                        'أضف ملاحظة طبية جديدة...', 'med-nt-add'),
                  ],
                ),
              ),
            ),
            // م66 — التذييل (حفظ) في وضع النموذج فقط؛ الورقة بلا حفظ.
            if (!viewMode) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('med-save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.brand600,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      // التقاط أي نص في حقلي الإضافة لم يُضَف بعد.
                      _commitAdd(newDiagnosisCtl, diagnosisLines);
                      _commitAdd(newNoteCtl, notesLines);
                      _save();
                    },
                    icon: const Icon(Icons.save_rounded, size: 17),
                    label: const Text('حفظ المعلومات',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
