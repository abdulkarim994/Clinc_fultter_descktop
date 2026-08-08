/// ============================================================================
///  مخزن خطة العلاج — إعادة بناء من الصفر (v29)
/// ============================================================================
///
///  لماذا أُعيد البناء؟ كانت المراحل تعيش داخل **صف إعدادات واحد**
///  (`app.config.treatmentPlans`) مع كل شيء آخر، والخادم يحسم ذلك الصف
///  كاملاً بالساعة الأحدث — فأي دفعة من جهاز تكتب فوق دفعة الآخر، وكل
///  محاولات الدمج داخل الكتلة كانت ترقيعاً فوق نموذج هشّ (نسخة تقول
///  «0/3 مرحلة» وأخرى «0/2»).
///
///  النموذج الجديد: **كل مرحلة صفٌّ مستقل يتزامن بنفسه** في جدول الإعدادات
///  (جدول مفتاح/قيمة عام يتزامن صفاً صفاً بساعة لكل صف — بلا أي تعديل على
///  الخادم):
///      المفتاح = `tp:(مفتاح المريض):(معرّف المرحلة)`
///      القيمة  = { id, desc, done, doneDate, order, patient, clinic }
///
///  ما يضمنه هذا النموذج:
///    • جهازان يضيفان مرحلتين ⇒ صفّان مختلفان: لا تعارض أصلاً ⇒ كلتاهما.
///    • تعليم «منجزة» يمس صف تلك المرحلة وحدها.
///    • الحذف = شاهد قبر على الصف ⇒ ينتشر حتماً ولا يُبعث.
///    • لا كتلة واحدة يمكن أن يكتب أحد فوقها ⇒ العلّة مقطوعة من جذرها.
///
///  البيانات القديمة تُستورد مرة واحدة من `app.config.treatmentPlans`
///  بمعرّفاتها؛ ومرحلة سبق حذفها لا تُستورد (شاهد قبرها موجود).
library;

import '../../core/utils/uid.dart';
import '../../data/repositories/settings_repository.dart';
import 'clinic_scope.dart' show clinicScopedKey, medicalScopedKey;

/// بادئة صفوف المراحل.
const String kPlanRowPrefix = 'tp:';

/// مفتاح صف مرحلة واحدة.
String planRowKey(String patientKey, String stageId) =>
    '$kPlanRowPrefix$patientKey:$stageId';

/// بادئة كل مراحل مريض واحد.
String planRowPrefixFor(String patientKey) =>
    '$kPlanRowPrefix$patientKey:';

/// مرحلة خطة علاج — كائن قراءة نقي.
class PlanStage {
  const PlanStage({
    required this.id,
    required this.desc,
    required this.done,
    required this.doneDate,
    required this.order,
  });

  final String id;
  final String desc;
  final bool done;
  final String doneDate;
  final num order;

  Map<String, Object?> toJson() => {
        'id': id,
        'desc': desc,
        'done': done,
        'doneDate': doneDate,
        'order': order,
      };

  static PlanStage fromJson(Map<String, Object?> m, {String? fallbackId}) =>
      PlanStage(
        id: '${m['id'] ?? fallbackId ?? ''}',
        desc: '${m['desc'] ?? ''}',
        done: m['done'] == true || m['done'] == 1 || m['done'] == '1',
        doneDate: '${m['doneDate'] ?? ''}',
        order: m['order'] is num ? m['order'] as num : 0,
      );
}

/// مخزن المراحل: كل عملية تكتب/تحذف **صفاً واحداً** فقط.
class TreatmentPlanStore {
  const TreatmentPlanStore(this.settings);

  final SettingsRepository settings;

  /// مفتاح المريض المعزول — م35 عيادةً، وم97 **هويةً**: «اسم|عيادة|أرقام
  /// الهاتف» متى عُرف هاتف (توأم مفتاح المعلومات الطبية؛ قرار المالك:
  /// ممنوع تشارك الخطة بين مشابهي الاسم).
  String keyFor(String name, String clinic, [Object? phone]) =>
      medicalScopedKey(name, clinic, phone);

  /// قراءة مراحل مريض مرتبةً (الترتيب ثم المعرّف — حتمي على كل الأجهزة).
  /// تُستورد الخطط القديمة تلقائياً عند أول قراءة (مرة واحدة)، وتُرقّى
  /// صفوف «اسم|عيادة» لمفتاح الهوية متى عُرف الهاتف (م97 — نقلاً).
  List<PlanStage> read(String name, String clinic,
      {Object? phone, Map<String, Object?>? legacyConfig}) {
    final pk = keyFor(name, clinic, phone);
    final plain = clinicScopedKey(name, clinic);
    if (pk != plain) {
      // ترقية م97: القارئ هنا هو صاحب الملف (هاتف صف المريض) — صفوف
      // مفتاح العيادة القديم تُنقل لمفتاح هويته ثم تُقبر.
      for (final s in _readRows(plain)) {
        if (!settings.existsIncludingDeleted(planRowKey(pk, s.id))) {
          _write(pk, s);
        }
        settings.softDelete(planRowKey(plain, s.id));
      }
    }
    if (legacyConfig != null) {
      importLegacy(name, clinic, legacyConfig, phone: phone);
    }
    return _readRows(pk);
  }

  List<PlanStage> _readRows(String patientKey) {
    final rows = settings.valuesWithPrefix(planRowPrefixFor(patientKey));
    final out = <PlanStage>[];
    rows.forEach((key, value) {
      if (value is! Map) return;
      final id = key.substring(key.lastIndexOf(':') + 1);
      out.add(PlanStage.fromJson(
          Map<String, Object?>.from(value), fallbackId: id));
    });
    out.sort((a, b) {
      final c = a.order.compareTo(b.order);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return out;
  }

  num _nextOrder(String patientKey) {
    final cur = _readRows(patientKey);
    if (cur.isEmpty) return 1;
    var max = cur.first.order;
    for (final s in cur) {
      if (s.order > max) max = s.order;
    }
    return max + 1;
  }

  void _write(String patientKey, PlanStage stage) {
    settings.set(planRowKey(patientKey, stage.id), stage.toJson());
  }

  /// إضافة مرحلة — صف جديد بمعرّف فريد (لا يتعارض مع أي جهاز آخر أبداً).
  PlanStage add(String name, String clinic, String desc, {Object? phone}) {
    final pk = keyFor(name, clinic, phone);
    final stage = PlanStage(
      id: genId(),
      desc: desc,
      done: false,
      doneDate: '',
      order: _nextOrder(pk),
    );
    _write(pk, stage);
    return stage;
  }

  /// تعليم الإنجاز/إلغاؤه — يمس صف المرحلة وحدها.
  void setDone(String name, String clinic, String stageId, bool done,
      {String? doneDate, Object? phone}) {
    final pk = keyFor(name, clinic, phone);
    final cur = _readRows(pk).where((s) => s.id == stageId).toList();
    if (cur.isEmpty) return;
    final s = cur.first;
    _write(
      pk,
      PlanStage(
        id: s.id,
        desc: s.desc,
        done: done,
        doneDate: done
            ? (doneDate ??
                DateTime.now().toIso8601String().split('T').first)
            : '',
        order: s.order,
      ),
    );
  }

  /// تعديل وصف مرحلة.
  void setDesc(String name, String clinic, String stageId, String desc,
      {Object? phone}) {
    final pk = keyFor(name, clinic, phone);
    final cur = _readRows(pk).where((s) => s.id == stageId).toList();
    if (cur.isEmpty) return;
    final s = cur.first;
    _write(
      pk,
      PlanStage(
          id: s.id,
          desc: desc,
          done: s.done,
          doneDate: s.doneDate,
          order: s.order),
    );
  }

  /// حذف مرحلة — شاهد قبر على صفها: ينتشر حتماً ولا يعود.
  void remove(String name, String clinic, String stageId, {Object? phone}) {
    settings.softDelete(planRowKey(keyFor(name, clinic, phone), stageId));
  }

  /// حذف كل مراحل مريض (حذف المريض من الملف) — م97: يشمل مفتاح الهوية
  /// ومفتاح العيادة والإرث بالاسم وحده.
  void removeAllFor(String name, String clinic, {Object? phone}) {
    final keys = <String>{
      keyFor(name, clinic, phone),
      clinicScopedKey(name, clinic),
      if (clinic.isNotEmpty) name, // ما قبل العزل بالعيادة.
    };
    for (final pk in keys) {
      for (final s in _readRows(pk)) {
        settings.softDelete(planRowKey(pk, s.id));
      }
    }
  }

  /// نقل مراحل مريض إلى مفتاح جديد (إعادة تسمية): كتابة صفوف جديدة
  /// بنفس المعرّفات ثم شواهد قبور على القديمة — م97: يُنقل مفتاح الهوية
  /// ومفتاح العيادة القديم كلاهما إلى مفتاح هوية الاسم الجديد.
  void moveTo(String oldName, String newName, String clinic,
      {Object? phone}) {
    final to = keyFor(newName, clinic, phone);
    final froms = <String>{
      keyFor(oldName, clinic, phone),
      clinicScopedKey(oldName, clinic),
    }..remove(to);
    for (final from in froms) {
      for (final s in _readRows(from)) {
        if (!settings.existsIncludingDeleted(planRowKey(to, s.id))) {
          _write(to, s);
        }
        settings.softDelete(planRowKey(from, s.id));
      }
    }
  }

  /// استيراد الخطط القديمة من `app.config.treatmentPlans` مرة واحدة:
  /// تُكتب صفوف المراحل التي لا وجود لمفاتيحها إطلاقاً؛ ومرحلة سبق حذفها
  /// لا تُستورد (شاهد قبرها موجود) فلا يعود المحذوف للحياة.
  ///
  /// م97 — **أُلغي الاستيراد من المدخل العاري بالاسم** (كان يسرّب خطة
  /// مشابه الاسم من عيادةٍ أخرى): هجرة الإقلاع تنقل العاري إلى مفتاح
  /// عيادة أحدث نشاط، وهنا يُقرأ مفتاح العيادة وحده.
  int importLegacy(String name, String clinic, Map<String, Object?> config,
      {Object? phone}) {
    final plans = config['treatmentPlans'];
    if (plans is! Map) return 0;
    var imported = 0;
    final target = keyFor(name, clinic, phone);
    for (final legacyKey in <String>{clinicScopedKey(name, clinic)}) {
      final list = plans[legacyKey];
      if (list is! List) continue;
      var i = 0;
      for (final el in list) {
        i++;
        if (el is! Map) continue;
        final m = Map<String, Object?>.from(el);
        final id = '${m['id'] ?? ''}'.isNotEmpty
            ? '${m['id']}'
            // مرحلة قديمة بلا معرّف: معرّف مشتق ثابت (نفسه على كل جهاز)
            // فلا تتكرر عند الاستيراد من جهازين.
            : 'lg${legacyKey.hashCode.abs()}_$i';
        final rowKey = planRowKey(target, id);
        if (settings.existsIncludingDeleted(rowKey)) continue;
        settings.set(rowKey, {
          'id': id,
          'desc': '${m['desc'] ?? ''}',
          'done': m['done'] == true,
          'doneDate': '${m['doneDate'] ?? ''}',
          'order': m['order'] is num ? m['order'] : i,
        });
        imported++;
      }
    }
    return imported;
  }
}
