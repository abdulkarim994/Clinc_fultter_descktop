/// ============================================================================
///  تفضيلات واجهة سطح المكتب — طبقة الحفظ الوحيدة لحالة الواجهة المكتبية
/// ============================================================================
///
///  قناتان (بنفس أعراف التطبيق الحالية، بلا أي جدول جديد):
///
///  1) **محلي للجهاز** — metadata (نفس قناة dental_theme/dental_font_size):
///     مفتاح واحد `desktop_ui_prefs` بقيمة JSON تجمع كل حالة الواجهة —
///     طيّ الشريط الجانبي، أعمدة كل جدول (عرض/إخفاء/تثبيت/فرز/صفحة)،
///     عرض ألواح التقسيم، وترتيب ودجات الرئيسية. شكل الشاشة خاصية
///     الجهاز نفسه، فلا معنى لمزامنتها إلى هاتفٍ أو جهازٍ آخر.
///
///  2) **مُزامَن** — app.config (قناة الإعدادات المشتركة): وسوم ألوان
///     الصفوف `desktopRowTags` فقط — «الوسم يبقى محفوظاً» عبر الأجهزة
///     والمزامنة، والهاتف يتجاهل المفتاح كلياً (قراءته انتقائية).
///
///  الكتابة المحلية مُخمَّدة (400ms) لأن سحب مقابض تغيير العرض يولّد
///  عشرات التحديثات في الثانية — تُدمج في الذاكرة وتُكتب دفعة واحدة.
library;

import 'dart:async' show Timer;
import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/providers.dart'
    show appConfigProvider, configRevProvider, localDbProvider, reposProvider;

const _kMetaKey = 'desktop_ui_prefs';

/// نبضة إعادة قراءة تفضيلات سطح المكتب المحلية.
final desktopPrefsRevProvider = StateProvider<int>((ref) => 0);

/// تفضيلات سطح المكتب المحلية (خريطة JSON كاملة — للقراءة فقط).
final desktopPrefsProvider = Provider<Map<String, Object?>>((ref) {
  ref.watch(desktopPrefsRevProvider);
  // القيم المعلقة (لم تُكتب بعد بسبب التخميد) تتقدم على المقروء من القرص
  // كي ترى الواجهة أثر تعديلها فوراً.
  final db = ref.watch(localDbProvider);
  Map<String, Object?> out = {};
  try {
    final row = db.queryFirst(
        'SELECT value FROM metadata WHERE key = ?', const [_kMetaKey]);
    final v = jsonDecode('${row?['value'] ?? '{}'}');
    if (v is Map) out = Map<String, Object?>.from(v);
  } catch (_) {
    // تفضيلات تالفة ⇒ البدء بالافتراضي (تحسينية — لا تعطل الواجهة).
  }
  if (_pending.isNotEmpty) out = {...out, ..._pending};
  return out;
});

// ── الكتابة المخمدة ─────────────────────────────────────────────────────────

final Map<String, Object?> _pending = {};
Timer? _flushTimer;

/// حفظ تفضيل محلي (يُخمَّد 400ms ويُدمج مع المعلق).
void saveDesktopPref(WidgetRef ref, String key, Object? value,
    {bool immediate = false}) {
  _pending[key] = value;
  ref.read(desktopPrefsRevProvider.notifier).state++;
  _flushTimer?.cancel();
  void flush() {
    _flushTimer = null;
    if (_pending.isEmpty) return;
    try {
      final db = ref.read(localDbProvider);
      Map<String, Object?> cur = {};
      final row = db.queryFirst(
          'SELECT value FROM metadata WHERE key = ?', const [_kMetaKey]);
      try {
        final v = jsonDecode('${row?['value'] ?? '{}'}');
        if (v is Map) cur = Map<String, Object?>.from(v);
      } catch (_) {}
      cur.addAll(_pending);
      _pending.clear();
      db.execute(
        'INSERT OR REPLACE INTO metadata(key, value, updated_at) '
        'VALUES(?, ?, ?)',
        [_kMetaKey, jsonEncode(cur), DateTime.now().millisecondsSinceEpoch],
      );
    } catch (_) {
      _pending.clear(); // لا نراكم معلقاً فاشلاً — التفضيل تحسيني.
    }
  }

  if (immediate) {
    flush();
  } else {
    _flushTimer = Timer(const Duration(milliseconds: 400), flush);
  }
}

/// تفريغ فوري للمعلق (للاختبارات).
@visibleForTesting
void debugFlushDesktopPrefs() {
  _flushTimer?.cancel();
  _flushTimer = null;
}

// ── وسوم ألوان الصفوف (مُزامَنة عبر app.config) ────────────────────────────

/// وسوم الصفوف: مفتاح الصف («نوع:معرف» مثل r:abc123) ← اسم اللون.
final rowTagsProvider = Provider<Map<String, String>>((ref) {
  final cfg = ref.watch(appConfigProvider);
  final t = cfg['desktopRowTags'];
  if (t is! Map) return const {};
  return {for (final e in t.entries) '${e.key}': '${e.value}'};
});

/// ضبط/إزالة وسم لون لصفٍّ ([color] فارغ = إزالة). يكتب في app.config
/// عبر مستودع الإعدادات نفسه (نفس مسار كتابة بقية إعدادات التطبيق —
/// فيتزامن كما هي) ثم يبعث نبضة الإعدادات.
void setRowTag(WidgetRef ref, String rowKey, String? color) {
  if (rowKey.isEmpty) return;
  final repos = ref.read(reposProvider);
  final cfg = ref.read(appConfigProvider);
  final cur = Map<String, Object?>.from(cfg);
  final raw = cur['desktopRowTags'];
  final tags = raw is Map
      ? Map<String, Object?>.from(raw)
      : <String, Object?>{};
  if (color == null || color.isEmpty) {
    if (!tags.containsKey(rowKey)) return;
    tags.remove(rowKey);
  } else {
    if (tags[rowKey] == color) return;
    tags[rowKey] = color;
  }
  repos.settings.set('app.config', {...cur, 'desktopRowTags': tags});
  ref.read(configRevProvider.notifier).state++;
}

/// ضبط وسمٍ واحد لعدة صفوف دفعةً واحدة (تحديد متعدد ⇒ كتابة واحدة).
void setRowTags(WidgetRef ref, Iterable<String> rowKeys, String? color) {
  final keys = [for (final k in rowKeys) if (k.isNotEmpty) k];
  if (keys.isEmpty) return;
  final repos = ref.read(reposProvider);
  final cfg = ref.read(appConfigProvider);
  final cur = Map<String, Object?>.from(cfg);
  final raw = cur['desktopRowTags'];
  final tags = raw is Map
      ? Map<String, Object?>.from(raw)
      : <String, Object?>{};
  for (final k in keys) {
    if (color == null || color.isEmpty) {
      tags.remove(k);
    } else {
      tags[k] = color;
    }
  }
  repos.settings.set('app.config', {...cur, 'desktopRowTags': tags});
  ref.read(configRevProvider.notifier).state++;
}
