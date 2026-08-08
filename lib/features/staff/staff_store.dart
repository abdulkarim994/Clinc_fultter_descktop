/// م118 — حسابات الموظفين (نسخة الاستعلامات): المرحلة 1 من نظام
/// الصلاحيات (قرار المالك بعد دراسة OWASP وأنظمة نقاط البيع).
///
///  • كل موظف صفُّ إعداداتٍ متزامنٌ `staff:<id>`: اسم دخول فريد، هاش
///    كلمة المرور (PBKDF2-HMAC-SHA256 بمغلّف م68 القابل للترقية — لا نص
///    صريح أبداً، والقاعدة أصلاً مشفرة بـSQLCipher)، الاسم الظاهر، الدور
///    (admin/staff)، الوردية، خريطة صلاحيات، ونشط/موقوف.
///  • الإيقاف بدل الحذف: يحفظ تاريخ الموظف في سجل التدقيق للأبد.
///  • قفل المحاولات الفاشلة: بعد خمس محاولاتٍ خاطئة يُقفل الحساب مؤقتاً
///    بمدة تتضاعف (30 ثانية × 2^n) — الصف `stafflock:<username>`.
library;

import 'dart:math' show Random;

import '../../core/utils/js_compat.dart';
import '../../core/utils/uid.dart';
import '../../data/repositories/settings_repository.dart';
import '../auth/password_hash.dart';

typedef JMap = Map<String, Object?>;

const String kStaffRowPrefix = 'staff:';
const String kStaffLockPrefix = 'stafflock:';

/// مفاتيح الصلاحيات وتسمياتها — تُعرض في شاشة الإدارة وتُفرض في المرحلة 2.
const List<({String key, String label})> kStaffPerms = [
  (key: 'records.add', label: 'إضافة زيارات ودفعات'),
  (key: 'records.edit', label: 'تعديل السجلات'),
  (key: 'records.delete', label: 'حذف السجلات'),
  (key: 'debts.pay', label: 'تسجيل دفعات الديون'),
  (key: 'debts.manage', label: 'تعديل/مسامحة/حذف الديون'),
  (key: 'expenses.add', label: 'إضافة مصروفات وسحوبات'),
  (key: 'expenses.delete', label: 'حذف المصروفات والسحوبات'),
  (key: 'dayclose', label: 'قفل اليوم وطباعة تقريره'),
  (key: 'dayreopen', label: 'إعادة فتح يوم مقفول'),
  (key: 'patients.view', label: 'عرض ملفات المرضى'),
  // م122 — أقسام المالية كلٌّ بصلاحيته المستقلة (قرار المالك؛ كانت
  // صلاحية واحدة finance.view — تبقى محترمةً كإرثٍ لحسابات أُنشئت قبلها).
  (key: 'treasury.view', label: 'عرض الخزينة'),
  (key: 'profits.view', label: 'عرض الأرباح'),
  (key: 'statement.view', label: 'عرض كشف الحساب'),
  (key: 'archive.view', label: 'عرض الأرشيف'),
  (key: 'labs.view', label: 'عرض المختبر'),
  (key: 'print', label: 'الطباعة والمشاركة'),
  // م121 — صلاحيات دقيقة (قرار المالك): إخفاء بصري + منع فعلي.
  (key: 'salaries.view', label: 'عرض الرواتب وإدارة موظفي الرواتب'),
  // م125 — دلالة مصححة: بدونها تظهر بطاقات العيادات وتفاصيلها فقط،
  // وتُخفى المجاميع الإجمالية والمحصّل والصوافي وذيل الديون.
  (key: 'treasury.details', label: 'عرض مجاميع الخزينة الإجمالية'),
  (key: 'clinics.sums', label: 'عرض مجموع الدخل على بطاقات العيادات'),
  (key: 'patients.medical', label: 'عرض المعلومات الطبية'),
  (key: 'patients.phones', label: 'عرض أرقام هواتف المرضى'),
  (key: 'months.nav', label: 'التنقل بين الأشهر السابقة'),
];

/// قالب «موظف استعلامات» الجاهز (يعدّله المالك كما يشاء): يعمل بشغله
/// فقط — إدخال وقبض ومصروف يومي وقفل يومه — بلا مالية ولا حذف.
const Map<String, bool> kReceptionistTemplate = {
  'records.add': true,
  'records.edit': false,
  'records.delete': false,
  'debts.pay': true,
  'debts.manage': false,
  'expenses.add': true,
  'expenses.delete': false,
  'dayclose': true,
  'dayreopen': false,
  'patients.view': true,
  'treasury.view': false,
  'profits.view': false,
  'statement.view': false,
  'archive.view': false,
  'labs.view': false,
  'print': true,
  // م121 — المساعد يسحب ويعرف المسحوب، لا الرواتب الأساسية ولا تفاصيل
  // الخزينة ولا المعلومات الطبية ولا أشهر الماضي؛ الهواتف نعم (يدخلها).
  'salaries.view': false,
  'treasury.details': false,
  'clinics.sums': false,
  'patients.medical': false,
  'patients.phones': true,
  'months.nav': false,
};

/// تطبيع اسم الدخول: حروف صغيرة بلا فراغات.
String normalizeUsername(String s) => s.trim().toLowerCase();

/// نتيجة محاولة دخول.
enum StaffLoginStatus { ok, wrongPassword, notFound, inactive, locked }

class StaffLoginResult {
  const StaffLoginResult(this.status, {this.user, this.lockedForSeconds = 0});
  final StaffLoginStatus status;
  final JMap? user;
  final int lockedForSeconds;
}

/// مخزن الموظفين فوق صفوف الإعدادات المتزامنة.
class StaffStore {
  const StaffStore(this.settings);

  final SettingsRepository settings;

  static String rowKey(String id) => '$kStaffRowPrefix$id';
  static String lockKey(String username) =>
      '$kStaffLockPrefix${normalizeUsername(username)}';

  /// كل الموظفين (النشطون والموقوفون) — للإدارة.
  List<JMap> listAll() {
    final rows = settings.valuesWithPrefix(kStaffRowPrefix);
    final out = <JMap>[];
    rows.forEach((key, value) {
      if (value is Map) {
        out.add({...Map<String, Object?>.from(value), 'id': key.substring(kStaffRowPrefix.length)});
      }
    });
    out.sort((a, b) => '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}'));
    return out;
  }

  List<JMap> listActive() =>
      [for (final u in listAll()) if (u['active'] != false) u];

  bool get hasAnyUser => listAll().isNotEmpty;

  bool get hasActiveAdmin => listActive().any((u) => u['role'] == 'admin');

  JMap? byUsername(String username) {
    final un = normalizeUsername(username);
    for (final u in listAll()) {
      if (normalizeUsername('${u['username'] ?? ''}') == un) return u;
    }
    return null;
  }

  /// إنشاء/تحديث موظف (بلا كلمة المرور — لها [setPassword]).
  String upsert({
    String? id,
    required String username,
    required String name,
    required String role, // admin | staff
    String shift = '',
    Map<String, bool> perms = const {},
    bool active = true,
  }) {
    final uid = id ?? genId();
    final existing = settings.get(rowKey(uid));
    final base = existing is Map
        ? Map<String, Object?>.from(existing)
        : <String, Object?>{'createdAt': jsNow()};
    settings.set(rowKey(uid), {
      ...base,
      'username': normalizeUsername(username),
      'name': name.trim(),
      'role': role == 'admin' ? 'admin' : 'staff',
      'shift': shift,
      'perms': perms,
      'active': active,
    });
    return uid;
  }

  /// تعيين كلمة المرور (هاش فقط — المغلّف القابل للترقية).
  void setPassword(String id, String password) {
    final existing = settings.get(rowKey(id));
    if (existing is! Map) return;
    settings.set(rowKey(id), {
      ...Map<String, Object?>.from(existing),
      'hash': hashPassword(password),
    });
  }

  // ══ رمز الاسترداد (استعادة كلمة المرور المنسية) ══
  //
  //  كلمة المرور تحمي واجهة التطبيق فقط، لا تشفّر البيانات (مفتاح
  //  SQLCipher في مخزن النظام مستقلٌّ عنها) — فاستعادتها لا تُفقد شيئاً.
  //  الرمز يُخزَّن **مُجزّأً** بنفس مغلّف كلمة المرور (PBKDF2)، فلا يُقرأ
  //  من القاعدة حتى لو فُتحت، ويُعرَض للمستخدم مرةً واحدة عند توليده.

  /// يولّد رمز استرداد مقروءاً: أربع مجموعات من أربعة محارف من أبجدية
  /// خالية من الملتبِس (بلا 0/O/1/I/L) — مثل `7K4M-9QRT-2FWX-H3PN`.
  static String generateRecoveryCode([Random? rng]) {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = rng ?? Random.secure();
    final buf = StringBuffer();
    for (var g = 0; g < 4; g++) {
      if (g > 0) buf.write('-');
      for (var i = 0; i < 4; i++) {
        buf.write(alphabet[r.nextInt(alphabet.length)]);
      }
    }
    return buf.toString();
  }

  /// تطبيع الرمز للمقارنة: أحرف كبيرة بلا فراغات/شرطات (يتسامح مع لصقٍ
  /// أو كتابةٍ بحالةٍ مختلفة).
  static String _normCode(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// يضبط رمز استرداد للحساب [id] (يُخزَّن مُجزّأً). يعيد الرمز الخام
  /// لعرضه مرةً واحدة على المستخدم.
  String setRecoveryCode(String id, [String? code]) {
    final raw = code ?? generateRecoveryCode();
    final existing = settings.get(rowKey(id));
    if (existing is! Map) return raw;
    settings.set(rowKey(id), {
      ...Map<String, Object?>.from(existing),
      'recovery': hashPassword(_normCode(raw)),
    });
    return raw;
  }

  bool hasRecoveryCode(String id) {
    final v = settings.get(rowKey(id));
    return v is Map && '${v['recovery'] ?? ''}'.isNotEmpty;
  }

  /// يتحقق من رمز الاسترداد للحساب [id] (مقارنةٌ بعد التطبيع).
  bool verifyRecoveryCode(String id, String code) {
    final v = settings.get(rowKey(id));
    if (v is! Map) return false;
    final stored = '${v['recovery'] ?? ''}';
    if (stored.isEmpty) return false;
    return verifyPassword(_normCode(code), stored);
  }

  /// إعادة تعيين كلمة المرور برمز الاسترداد. عند النجاح: تُضبط الجديدة،
  /// ويُبطَل قفل المحاولات، **ويُستهلَك الرمز** (استعمالٌ واحد) — على
  /// المستدعي توليد رمزٍ جديد وعرضه. يعيد true عند النجاح.
  bool resetPasswordWithRecovery(String id, String code, String newPassword) {
    if (!verifyRecoveryCode(id, code)) return false;
    final un = normalizeUsername(
        '${(settings.get(rowKey(id)) as Map?)?['username'] ?? ''}');
    setPassword(id, newPassword);
    final existing = settings.get(rowKey(id));
    if (existing is Map) {
      final m = Map<String, Object?>.from(existing)..remove('recovery');
      settings.set(rowKey(id), m);
    }
    if (un.isNotEmpty) _clearFails(un);
    return true;
  }

  /// إعادة تعيين كلمة مرور حسابٍ مباشرةً (بعد إثباتٍ خارجي: حسابٌ سحابي
  /// أو إدارةٌ أخرى وقّعت). يُبطل قفل المحاولات. المسؤولية على المستدعي
  /// في التحقق من الإذن قبل النداء.
  void adminResetPassword(String id, String newPassword) {
    final un = normalizeUsername(
        '${(settings.get(rowKey(id)) as Map?)?['username'] ?? ''}');
    setPassword(id, newPassword);
    if (un.isNotEmpty) _clearFails(un);
  }

  /// إيقاف نظام الموظفين كلياً والعودة للوضع الفردي — يحذف كل صفوف
  /// الموظفين وأقفال محاولاتهم. **لا يمسّ أي بيانات مريض** (المرضى
  /// والسجلات والمالية في جداولها لا في صفوف الإعدادات هذه). عمليةٌ
  /// حسّاسة: على المستدعي التحقق من صلاحية الإدارة قبلها.
  void disableStaffSystem() {
    for (final u in listAll()) {
      final un = normalizeUsername('${u['username'] ?? ''}');
      settings.softDelete(rowKey('${u['id']}'));
      if (un.isNotEmpty) settings.softDelete(lockKey(un));
    }
  }

  // ── قفل المحاولات الفاشلة ──
  ({int fails, num until}) _lockState(String username) {
    final v = settings.get(lockKey(username));
    if (v is! Map) return (fails: 0, until: 0);
    return (fails: jsNumOr0(v['fails']).toInt(), until: jsNumOr0(v['until']));
  }

  void _registerFail(String username) {
    final s = _lockState(username);
    final fails = s.fails + 1;
    // بعد الخامسة: قفل 30ث يتضاعف مع كل فشلٍ إضافي (حد أقصى 30 دقيقة).
    num until = 0;
    if (fails >= 5) {
      final factor = fails - 4;
      final secs = (30 * (1 << (factor - 1))).clamp(30, 1800);
      until = jsNow() + secs * 1000;
    }
    settings.set(lockKey(username), {'fails': fails, 'until': until});
  }

  void _clearFails(String username) {
    final s = _lockState(username);
    if (s.fails > 0) {
      settings.set(lockKey(username), {'fails': 0, 'until': 0});
    }
  }

  /// محاولة دخول كاملة: تتحقق وتدير عدّاد الفشل والقفل المؤقت.
  StaffLoginResult login(String username, String password) {
    final u = byUsername(username);
    if (u == null) return const StaffLoginResult(StaffLoginStatus.notFound);
    if (u['active'] == false) {
      return const StaffLoginResult(StaffLoginStatus.inactive);
    }
    final s = _lockState(username);
    final now = jsNow();
    if (s.until > now) {
      return StaffLoginResult(StaffLoginStatus.locked,
          lockedForSeconds: ((s.until - now) / 1000).ceil());
    }
    final hash = '${u['hash'] ?? ''}';
    if (hash.isEmpty || !verifyPassword(password, hash)) {
      _registerFail(username);
      final after = _lockState(username);
      return StaffLoginResult(StaffLoginStatus.wrongPassword,
          lockedForSeconds: after.until > now
              ? ((after.until - now) / 1000).ceil()
              : 0);
    }
    _clearFails(username);
    // ترحيل شفاف للمغلفات القديمة عند أول دخول ناجح (نمط م68).
    if (needsRehash(hash)) setPassword('${u['id']}', password);
    return StaffLoginResult(StaffLoginStatus.ok, user: u);
  }
}
