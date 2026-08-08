/// ============================================================================
///  خدمة الشبكة الموحدة — التوأم الحرفي لـ services/network.service.js
/// ============================================================================
///
///  الأصل: «مصدر حقيقة وحيد للاتصال». حالة الوصلة وحدها تكذب على أندرويد
///  (واي-فاي بلا إنترنت/بوابات أسيرة)، لذا يجمع الأصل بين حالة الوصلة
///  (@capacitor/network — هنا connectivity_plus) و**تأكيد وصول حقيقي**
///  بطلب HEAD خفيف إلى Supabase (مهلة PING_TIMEOUT=5000ms) يعاد دورياً
///  كل PING_INTERVAL=15000ms ما دامت الوصلة قائمة، وكل من في التطبيق
///  يشترك هنا بدل قياس الشبكة بنفسه: هيدر «متصل الآن/غير متصل»، بوابة
///  محرك المزامنة (دورة أوفلاين ⇒ حالة offline بلا نداء)، محفز إعادة
///  الاتصال، وأعلام أونلاين الأشعة.
///
///  التصميم قابل للحقن بالكامل (مجرى الوصلة + الفاحص + الفواصل) — توأم
///  فلسفة الاختبار في بقية المشروع.
library;

import 'dart:async';

/// PING_INTERVAL / PING_TIMEOUT — حرفياً من الأصل.
const networkPingInterval = Duration(seconds: 15);
const networkPingTimeout = Duration(seconds: 5);

class NetworkStatus {
  NetworkStatus({
    required this.linkStream,
    required this.probe,
    this.pingInterval = networkPingInterval,
    bool initialLink = true,
  }) : _link = initialLink;

  final Stream<bool> linkStream;

  /// فحص الوصول الحقيقي (HEAD إلى الخلفية). في الوضع المحلي بلا خلفية
  /// يُحقن فاحص «الوصلة تكفي» — سلوك الأصل عند غياب SUPABASE_URL.
  final Future<bool> Function() probe;

  final Duration pingInterval;

  bool _link;
  bool _online = false;
  bool _started = false;
  int _generation = 0; // يبطل فحوصاً طائرة بعد تغير الوصلة/الإيقاف
  StreamSubscription<bool>? _sub;
  Timer? _ping;

  /// أفضل حالة معروفة (وصلة + وصول مؤكد) — getIsOnline حرفياً.
  bool get online => _online;

  /// المستمعون — يُنادَون عند **تغيّر** الحالة فقط (توأم _emit).
  final Set<void Function(bool online)> listeners =
      <void Function(bool)>{};

  void _emit(bool value) {
    if (_online == value) return;
    _online = value;
    for (final cb in [...listeners]) {
      try {
        cb(value);
      } catch (_) {/* أخطاء مستمعٍ لا تسقط البقية */}
    }
  }

  /// idempotent: فحص فوري + اشتراك بالوصلة + جدولة الفحص الدوري.
  void start() {
    if (_started) return;
    _started = true;
    _sub = linkStream.listen(_onLink);
    _schedulePing();
    _recheck();
  }

  void _onLink(bool up) {
    if (up == _link) return;
    _link = up;
    _generation++;
    if (!up) {
      // انقطاع الوصلة حاسم فوراً — لا فحص وصول له معنى.
      _cancelPing();
      _emit(false);
      return;
    }
    _schedulePing();
    _recheck();
  }

  void _schedulePing() {
    _cancelPing();
    _ping = Timer.periodic(pingInterval, (_) => _recheck());
  }

  void _cancelPing() {
    _ping?.cancel();
    _ping = null;
  }

  /// وصلة قائمة ⇒ يؤكد الوصول بالفاحص؛ نتيجة فحصٍ عتيق (سبقه تغيّر
  /// وصلة) تُهمل.
  Future<void> _recheck() async {
    if (!_link) {
      _emit(false);
      return;
    }
    final gen = _generation;
    bool ok;
    try {
      ok = await probe();
    } catch (_) {
      ok = false;
    }
    if (gen != _generation || !_started) return; // عتيق
    _emit(_link && ok);
  }

  void dispose() {
    _started = false;
    _generation++;
    _sub?.cancel();
    _sub = null;
    _cancelPing();
    listeners.clear();
  }
}
