/// م75 — أرشفة المرضى: إخفاء مريض غير نشط من القائمة والبحث بلا حذف.
///
/// «الأرشفة» هنا غير «الأرشفة الباردة» (م70): تلك تلقائية على الخادم لتوفير
/// التخزين؛ وهذه يدوية في الواجهة لترتيب العرض. المريض المؤرشف تبقى كل
/// بياناته ومعالجاته وديونه، ويعود بضغطة — أو تلقائياً عند أول معالجة جديدة.
///
/// التخزين — نفس نمط TreatmentPlanStore بالضبط
/// ────────────────────────────────────────────
/// حالة الأرشفة صفٌّ في `settings` بمفتاح مشتق من هوية المريض
/// (اسم|عيادة، م35)، فيرث التزامن وHLC والدمج الحقلي وشواهد القبور مجاناً:
/// الأرشفة من الاستقبال تُخفيه عند الطبيب خلال ثوانٍ بلا أي شيفرة تزامن
/// إضافية، وبلا مهاجرة أو تغيير خادمي.
///
///   وجود الصف  = مؤرشف     (القيمة {at: طابع زمني})
///   شاهد قبر    = نشط       (softDelete — يتزامن كإلغاء أرشفة)
///
/// الهوية مركّبة (اسم|عيادة): نفس الاسم في عيادتين حالتان مستقلتان — توأم
/// قرار المالك في م35 وفي مخزن خطط العلاج.
library;

import '../../data/repositories/settings_repository.dart';
import 'clinic_scope.dart' show clinicScopedKey, medicalScopedKey;

/// بادئة مفاتيح الأرشفة في الإعدادات. مستقلة عن بادئة الخطط فلا تتقاطع.
const String archiveKeyPrefix = 'patient.archived:';

String archiveKey(String patientKey) => '$archiveKeyPrefix$patientKey';

class PatientArchiveStore {
  const PatientArchiveStore(this.settings);

  final SettingsRepository settings;

  /// مفتاح المريض المعزول — م35 عيادةً، وم-عزل الهوية **هويةً**:
  /// «اسم|عيادة|هاتف» متى عُرف هاتف (توأم مفتاح المعلومات الطبية وخطة
  /// العلاج) — فأرشفةُ سميٍّ لا تُخفي سميّه. غيابُ الهاتف يُبقي «اسم|عيادة»
  /// حرفياً (السلوك القائم — م35).
  String keyFor(String name, String clinic, [Object? phone]) =>
      medicalScopedKey(name, clinic, phone);

  /// هل المريض مؤرشف؟ (وجود صف حيّ = مؤرشف).
  /// م-عزل الهوية — **قراءة متدرجة**: مفتاح الهوية «اسم|عيادة|هاتف» أولاً
  /// ثم مفتاح «اسم|عيادة» القديم — فلا يُفقد أرشفةٌ سبقت ترقية الهاتف.
  bool isArchived(String name, String clinic, [Object? phone]) {
    if (settings.get(archiveKey(keyFor(name, clinic, phone))) != null) {
      return true;
    }
    final legacy = clinicScopedKey(name, clinic);
    if (legacy != keyFor(name, clinic, phone)) {
      return settings.get(archiveKey(legacy)) != null;
    }
    return false;
  }

  /// مجموعة مفاتيح المرضى المؤرشفين حالياً — لترشيح القائمة دفعةً بلا
  /// استعلام لكل صف.
  Set<String> archivedKeys() {
    final rows = settings.valuesWithPrefix(archiveKeyPrefix);
    return {
      for (final k in rows.keys) k.substring(archiveKeyPrefix.length),
    };
  }

  /// أرشفة مريض واحد. idempotent — إعادتها لا تضرّ.
  /// م-عزل الهوية — [phone] (متى مُرِّر) يؤرشف هوية السميّ وحدها.
  void archive(String name, String clinic, [Object? phone]) {
    final k = keyFor(name, clinic, phone);
    settings.set(archiveKey(k), {'at': DateTime.now().millisecondsSinceEpoch});
  }

  /// إلغاء أرشفة مريض واحد (شاهد قبر يتزامن كإلغاء).
  /// م-عزل الهوية — يرفع شاهدَي المفتاح الهوياتي والقديم كليهما، فلا يبقى
  /// المريض مؤرشفاً عبر مدخلٍ قديم بعد إلغاء الأرشفة.
  void unarchive(String name, String clinic, [Object? phone]) {
    settings.softDelete(archiveKey(keyFor(name, clinic, phone)));
    final legacy = clinicScopedKey(name, clinic);
    if (legacy != keyFor(name, clinic, phone) &&
        settings.get(archiveKey(legacy)) != null) {
      settings.softDelete(archiveKey(legacy));
    }
  }

  /// أرشفة/إلغاء دفعةً — للتحديد المتعدد.
  ///
  /// م189 — [phone] صار جزءاً من الحمولة **إلزاماً**: كانت الدفعة تؤرشف
  /// بمفتاح «اسم|عيادة» وحده، فأرشفةُ أحد السميَّين تُخفي الآخر وإلغاؤها
  /// تُظهرهما معاً — «نظام الأرشفة يعتبرهم شخصاً واحداً» (بلاغ المالك).
  void archiveAll(
      Iterable<({String name, String clinic, String phone})> patients) {
    for (final p in patients) {
      archive(p.name, p.clinic, p.phone);
    }
  }

  void unarchiveAll(
      Iterable<({String name, String clinic, String phone})> patients) {
    for (final p in patients) {
      unarchive(p.name, p.clinic, p.phone);
    }
  }

  /// العودة التلقائية (قرار المالك): مريض مؤرشف تُضاف له معالجة/زيارة
  /// جديدة يعود نشطاً بحكم الفعل. تُستدعى من مسار حفظ السجل. لا تفعل شيئاً
  /// إن لم يكن مؤرشفاً (لا شاهد قبر بلا داعٍ).
  void autoReactivateOnActivity(String name, String clinic, [Object? phone]) {
    if (isArchived(name, clinic, phone)) {
      unarchive(name, clinic, phone);
    }
  }
}
