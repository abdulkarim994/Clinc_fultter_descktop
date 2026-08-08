/// طب الأسنان الرقمي — نسخة Flutter.
/// بوابة الدخول: جلسة محفوظة ⇒ الصدفة مباشرة، وإلا شاشة تسجيل الدخول
/// (توأم حارس المسارات في router/index.js).
library;

import 'dart:async' show runZonedGuarded, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/cloud_boot.dart';
import 'app/providers.dart';
import 'core/error_log.dart' show initErrorLog, recordError;
import 'core/theme/font_calibration.dart';
import 'core/theme/app_theme.dart';
import 'data/cloud/cloud_config.dart' show applyBuildTimeFlags;
import 'data/db/db_boot.dart';
import 'data/db/secure_key_store.dart';
import 'features/auth/post_login_gate.dart';
import 'features/desktop/desktop_gate.dart' show isDesktopPlatform;
import 'features/desktop/security/temp_cleaner.dart' show sweepEphemeral;
import 'features/login/login_screen.dart';

/// م44 — نمط شريط النظام الثابت: شريط **شفاف** فيتصل تدرج هيدر الصدفة
/// من أول بكسل (لون واحد بلا فاصل — كان اللون المعتم في v18 يفصل بين
/// الشريط والتدرج الأفتح)، والأيقونات **بيضاء دائماً** — الشاشات الفاتحة
/// (ملف المريض) ترسم شريحتها العلوية بنفسها بتدرج الهوية.
const kDentalSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent, // متصل بالهيدر — بلا فاصل
  statusBarIconBrightness: Brightness.light, // أندرويد: أيقونات بيضاء
  statusBarBrightness: Brightness.dark, // iOS: نص أبيض
  systemNavigationBarColor: Color(0xFF0A3024),
  systemNavigationBarIconBrightness: Brightness.light,
);

/// بعض الأنظمة تعيد ضبط نمط الشريط عند العودة من الخلفية — يعاد تأكيده
/// عند كل استئناف (سبب «تحول الخط من الأبيض للأسود عند التصغير»).
class _SystemUiGuard with WidgetsBindingObserver {
  void attach() {
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(kDentalSystemUiStyle);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setSystemUIOverlayStyle(kDentalSystemUiStyle);
    }
  }
}

final _systemUiGuard = _SystemUiGuard();

Future<void> main() async {
  // م77 — حدّ الأخطاء العام. كان غائباً تماماً: لا `FlutterError.onError`
  // ولا `runZonedGuarded`، فأي استثناء غير ملتقَط في مسار كتابة يختفي بلا
  // أثر — لا المستخدم يعلم ولا المطوّر. المنطقة تلتقط الأخطاء غير
  // المتزامنة، و`FlutterError.onError` يلتقط أخطاء شجرة الواجهة، ومعاً
  // يغطّيان ما كان يسقط صامتاً.
  //
  // التهيئة **داخل** المنطقة شرط لا تفصيل: رابط Flutter المُهيّأ خارجها
  // يبلّغ إلى المنطقة الجذر فلا يمرّ بالمعالج إطلاقاً.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      recordError(details.exception, details.stack,
          context: 'flutter:${details.library ?? '-'}');
      prev?.call(details); // يبقى سلوك وضع التطوير (الشاشة الحمراء) كما هو
    };

    // أعلام بيئة البناء (توأم VITE_* في .env.production) — قبل بناء أي شيء.
    applyBuildTimeFlags();
    _systemUiGuard.attach();
    final support = await getApplicationSupportDirectory();

    // م83 — تهيئة القاعدة المشفَّرة **قبل** أي فتح: نقل مسار ويندوز، ثم
    // حسم المفتاح من مخزن النظام، ثم ترحيل القاعدة السادة إن وُجدت.
    // المنطق كله في `prepareDatabase` كي يُختبر؛ وهنا التوصيل فقط.
    // حتى `prepareDatabase` نفسها قد ترمي على منصّة تُقفل الملفات (ويندوز
    // مع نسخة ثانية من التطبيق أو مضاد فيروسات ممسكٍ بملف). وبلا هذا
    // الالتقاط يهرب الاستثناء إلى المنطقة قبل تهيئة سجل الأعطال — فلا
    // شاشة ولا سطر تشخيص، شاشةٌ سوداء وحسب.
    late final DbBootResult boot;
    try {
      boot = await prepareDatabase(
        supportDir: support.path,
        keyStore: const SecureDbKeyStore(),
      );
    } catch (e, st) {
      initErrorLog(support.path);
      recordError(e, st, context: 'db-boot:threw');
      runApp(_DbBootFailureApp(
        result: DbBootResult(
          dataDir: support.path,
          status: DbBootStatus.migrationFailed,
          detail: 'أخفق تجهيز القاعدة قبل أي تعديل — ملفّك سليم كما كان: $e',
        ),
      ));
      return;
    }

    // وجهة السجلّ تُعرف الآن فقط — وبالمسار **بعد** النقل لا قبله.
    initErrorLog(boot.dataDir);

    if (!boot.canOpen) {
      // لا تُفتح قاعدة ولا تُنشأ بديلة: البيانات سليمة على القرص خلف مفتاح
      // مفقود، والشاشة تشرح ذلك بدل بياضٍ صامت أو قاعدةٍ فارغة مفزعة.
      recordError(StateError(boot.detail), StackTrace.current,
          context: 'db-boot:${boot.status.name}');
      runApp(_DbBootFailureApp(result: boot));
      return;
    }

    if (boot.status == DbBootStatus.migrated) {
      recordError(StateError(boot.detail), StackTrace.current,
          context: 'db-boot:migrated');
    }

    // م88 — الإقلاع السحابي: المخزن الآمن للجلسة + الحزمة الرسمية (PKCE)
    // وزرّ Google الحقيقي. كل خطوةٍ فيه تتدهور رشيقاً عند الفشل (يُسجَّل
    // ويُتجاوز) — فلا يؤخّر الأوفلاين ولا يمنع الإقلاع أبداً.
    final cloudOverrides = await buildCloudAuthOverrides(boot.dataDir);

    // نسخة الكمبيوتر (قرار المالك §خامساً): كنس المؤقتات والصادرات عند
    // الإقلاع — تنظيف ما خلّفته جلسةٌ أُغلقت فجأة. أفضل جهد، لا يعطّل
    // الإقلاع، ولا أثر على الهاتف (المسارات نفسها خاليةٌ هناك عادةً).
    if (isDesktopPlatform()) {
      unawaited(sweepEphemeral(boot.dataDir)
          .catchError((_) => 0));
    }

    runApp(
      ProviderScope(
        overrides: [
          dbDirProvider.overrideWithValue(boot.dataDir),
          dbEncryptionKeyProvider.overrideWithValue(boot.encryptionKey),
          // مخزن مفتاح القاعدة الحقيقي (DPAPI/Keystore) — يُقرأ في المسح
          // المصنعي لحذف المفتاح نهائياً. الاختبارات تُبقي الافتراض الذاكري.
          dbKeyStoreProvider.overrideWithValue(const SecureDbKeyStore()),
          ...cloudOverrides,
        ],
        child: const DentalApp(),
      ),
    );
  }, (error, stack) => recordError(error, stack, context: 'zone'));
}

class DentalApp extends ConsumerWidget {
  const DentalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final fontScale = ref.watch(fontScaleProvider);
    // م40 — معايرة قاعدة الخط على الأصل: جسم Vue الأساس 18px ومكوناته
    // 14–16px بينما مقاسات Flutter المكتوبة أصغر — معامل 1.12 يجعل
    // «عادي» معادلاً لحجم Vue الفعلي وتتدرج البقية نسبياً كما في الأصل.
    final isDark = ref.watch(themeModeProvider) == 'dark';
    // الرموز المتكيفة تُقرأ أثناء بناء الشاشات — تُضبط قبل بناء النسق.
    BrandColors.darkMode = isDark;
    return MaterialApp(
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        // م43 — تثبيت النمط على مستوى الشجرة كلها (كل الشاشات والمسارات).
        value: kDentalSystemUiStyle,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler:
                TextScaler.linear(fontScale * kVueFontCalibration),
          ),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      title: 'طب الأسنان الرقمي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(dark: isDark),
      home: switch (auth) {
        // م31 — البوابة الإجبارية: الرئيسية لا تفتح إلا عبرها (ترحيب
        // للقديم، وإعداد إلزامي للجديد يصمد عبر الإغلاق والخروج).
        SignedIn() => const PostLoginGate(),
        SignedOut() => const LoginScreen(),
      },
    );
  }
}

/// شاشة إخفاق إقلاع القاعدة — عربية صريحة تقول ما جرى وما العمل.
///
/// عمداً بلا `ProviderScope`: كل شيء فوق المزوّدات يفترض قاعدةً مفتوحة،
/// وهذه الحالة تعني أنها ليست كذلك.
class _DbBootFailureApp extends StatelessWidget {
  const _DbBootFailureApp({required this.result});

  final DbBootResult result;

  @override
  Widget build(BuildContext context) {
    final missing = result.status == DbBootStatus.keyMissing;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF0A3024),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline, color: Colors.white, size: 56),
                  const SizedBox(height: 18),
                  Text(
                    missing
                        ? 'تعذّر فتح قاعدة البيانات'
                        : 'تعذّر تجهيز قاعدة البيانات',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    missing
                        ? 'القاعدة مشفَّرة ومفتاحها غير متاح على هذا الجهاز.\n\n'
                            'بياناتك **لم تُحذف** — هي سليمة على القرص، لكن '
                            'فتحها يحتاج المفتاح الأصلي.\n\n'
                            'ما العمل:\n'
                            '• إن كان هذا جهازاً جديداً، سجّل الدخول بحسابك '
                            'لاسترجاع بياناتك من السحابة.\n'
                            '• إن كان الجهاز نفسه بعد استعادة نسخة احتياطية، '
                            'أعد الاستعادة متضمّنةً بيانات التطبيق.\n'
                            '• لا تحذف التطبيق قبل ذلك.'
                        : 'لم يكتمل تجهيز القاعدة، ولم يُمسّ ملفك الأصلي — '
                            'هو سليم كما كان.\n\nأعد تشغيل التطبيق، وإن '
                            'تكرّر الأمر تواصل مع الدعم بالنص أدناه.',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 15, height: 1.7),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      result.detail,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
