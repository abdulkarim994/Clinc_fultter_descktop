/// ============================================================================
///  محفّز إعادة الاتصال — توأم onNetworkChange في sync/engine.js
/// ============================================================================
///
///  الأصل: عند تحول الشبكة إلى «متصل» يجدول `runCycle('reconnect')` بعد
///  مهلة توهين ثانيتين (RECONNECT_DEBOUNCE_MS) — فتُدفع تعديلات الأوفلاين
///  خلال ثوانٍ من عودة الاتصال بدل انتظار نبضة الاستطلاع (حتى ٥ دقائق في
///  الخمول).
///
///  قرار أمانة مقصود: هذا **محفّز فقط لا بوابة** — بوابة `isOnline` تبقى
///  متفائلة كما هي (المحاولة الفاشلة يتكفل بها التراجع الأسي)، فقارئ شبكةٍ
///  مخطئ (يحدث على ويندوز) لا يستطيع أبداً أن يمنع المزامنة، وأسوأ حالاته
///  ركلة زائدة غير مؤذية. الفئة نقية قابلة للاختبار؛ التوصيل بمصدر أحداث
///  connectivity_plus يجري في providers.dart.
library;

import 'dart:async';

/// مهلة التوهين — RECONNECT_DEBOUNCE_MS حرفياً.
const reconnectDebounceMs = 2000;

class ReconnectKick {
  ReconnectKick(this.onReconnect, {this.debounceMs = reconnectDebounceMs});

  /// يُستدعى مرة بعد استقرار عودة الاتصال (ركلة مزامنة + تصريف صور).
  final void Function() onReconnect;

  final int debounceMs;

  Timer? _t;
  bool? _last;

  /// حدث حالة شبكة خام. التكرار على نفس الحالة يُهمل؛ الانقطاع يلغي أي
  /// ركلة معلقة؛ العودة تجدول الركلة بعد مهلة التوهين (تجدد عند التذبذب).
  void onEvent(bool online) {
    if (online == _last) return;
    _last = online;
    _t?.cancel();
    if (!online) return;
    _t = Timer(Duration(milliseconds: debounceMs), onReconnect);
  }

  void dispose() {
    _t?.cancel();
    _t = null;
  }
}
