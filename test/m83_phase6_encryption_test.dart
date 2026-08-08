/// اختبارات م83 — المرحلة السادسة: التشفير عند السكون.
///
///  ⚠ **هذه الاختبارات تُثبت التشفير ولا تصفه.** كل ادّعاء هنا مبنيّ على
///  قراءة بايتات الملف من القرص أو على فتحٍ فعلي بمفتاح خاطئ — لا على
///  استدعاء دالة تُرجع `true`.
///
///  ما هو مُتحقَّق منه هنا: الحماية الفعلية للملف، ودورة المفتاح، وسلامة
///  الترحيل عند الإخفاق.
///
///  ما **ليس** مُتحقَّقاً: حفظ المفتاح في مخزن النظام (Keystore/DPAPI) —
///  يستلزم جهازاً حقيقياً. الواجهة مُختبَرة، والربط بالمنصّة يبقى نقطة
///  تكامل تُفحص على جهاز.
library;

import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:dental_clinic_flutter/data/db/blob_vault.dart';
import 'package:dental_clinic_flutter/data/db/bootstrap.dart';
import 'package:dental_clinic_flutter/data/db/db_boot.dart';
import 'package:dental_clinic_flutter/data/db/db_paths.dart';
import 'package:dental_clinic_flutter/data/db/db_encrypt.dart';
import 'package:dental_clinic_flutter/data/db/db_key.dart';
import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sq;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m83_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String dbPath() => p.join(tmp.path, 'dental_clinic_offline.db');

  /// هل يظهر هذا النصّ في بايتات الملف الخام؟
  ///
  ///  ⚠ **بحثٌ ببايتات UTF-8 لا بسلسلة Dart.** المحاولة الأولى استعملت
  ///  `String.fromCharCodes` على البايتات، وهي تعامل كل بايت محرفاً
  ///  مستقلاً — فالنصّ العربي متعدّد البايتات **لا يُطابَق أبداً**، ويعود
  ///  الفحص `false` سواء أكان الملف مشفَّراً أم مكشوفاً تماماً.
  ///
  ///  أي أن اختبار «الاسم غير مقروء» كان سيمرّ **لسبب خاطئ**. وكشفه
  ///  اختبارُ الضبط أدناه («بلا مفتاح: الاسم مقروء») — وهذا بالضبط سبب
  ///  كتابته: نظيرٌ يُثبت أن المقياس يقيس شيئاً.
  bool bytesContain(String path, String needle) {
    final hay = File(path).readAsBytesSync();
    final pat = utf8.encode(needle);
    if (pat.isEmpty || hay.length < pat.length) return false;
    outer:
    for (var i = 0; i <= hay.length - pat.length; i++) {
      for (var j = 0; j < pat.length; j++) {
        if (hay[i + j] != pat[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  /// رأس الملف — ASCII فيصحّ فيه التحويل المباشر.
  String fileHead(String path) =>
      String.fromCharCodes(File(path).readAsBytesSync().take(16));

  // ══════════════════════════════════════════════════════════════════════
  group('م83/أ — الملف مشفَّر فعلاً على القرص', () {
    test('اسم المريض غير مقروء في بايتات الملف', () {
      final key = generateDbKey();
      final db = LocalDb.open(dbPath(), encryptionKey: key);
      db.execute(
          "INSERT INTO patients (id, name, phone) VALUES ('p1', ?, ?)",
          ['سالم المبروك', '0912345678']);
      db.close();

      expect(fileHead(dbPath()).startsWith('SQLite format 3'), isFalse,
          reason: 'م83: رأس الملف ليس SQLite السادة');
      expect(bytesContain(dbPath(), 'سالم المبروك'), isFalse,
          reason: 'م83: **اسم المريض غير مقروء** — جوهر التشفير عند السكون');
      expect(bytesContain(dbPath(), '0912345678'), isFalse, reason: 'ولا الهاتف');
    });

    test('بلا مفتاح: الاسم مقروء — إثبات أن الاختبار يقيس شيئاً', () {
      // النظير الضروري: لولاه لا يُعرف هل الغياب أعلاه بسبب التشفير أم
      // بسبب أن الاختبار لا يقرأ شيئاً أصلاً.
      final db = LocalDb.open(dbPath());
      db.execute(
          "INSERT INTO patients (id, name) VALUES ('p1', ?)", ['سالم المبروك']);
      db.close();

      expect(fileHead(dbPath()).startsWith('SQLite format 3'), isTrue);
      expect(bytesContain(dbPath(), 'سالم المبروك'), isTrue,
          reason: 'بلا تشفير الاسم مكشوف — وهو الوضع قبل م83');
    });

    test('المفتاح الصحيح يفتح والخاطئ يُرفض', () {
      final key = generateDbKey();
      final db = LocalDb.open(dbPath(), encryptionKey: key);
      db.execute("INSERT INTO patients (id, name) VALUES ('p1','ليلى')");
      db.close();

      final ok = LocalDb.open(dbPath(), encryptionKey: key);
      expect(ok.query('SELECT name FROM patients').single['name'], 'ليلى');
      ok.close();

      expect(
          () => LocalDb.open(dbPath(), encryptionKey: generateDbKey()),
          throwsA(anything),
          reason: 'م83: مفتاح آخر لا يفتح القاعدة');
    });

    test('بلا مفتاح إطلاقاً: القاعدة المشفَّرة لا تُفتح', () {
      final key = generateDbKey();
      LocalDb.open(dbPath(), encryptionKey: key)
        ..execute("INSERT INTO patients (id, name) VALUES ('p1','خالد')")
        ..close();

      expect(() => LocalDb.open(dbPath()), throwsA(anything),
          reason: 'من يأخذ الملف وحده لا يقرأ شيئاً');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م83/ب — دورة حياة المفتاح', () {
    test('المفتاح عشوائي بالطول الصحيح ولا يتكرّر', () {
      final keys = {for (var i = 0; i < 50; i++) generateDbKey()};
      expect(keys, hasLength(50), reason: 'لا تكرار في خمسين توليداً');
      for (final k in keys) {
        expect(k.length, kDbKeyBytes * 2, reason: '256 بت بصيغة hex');
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(k), isTrue);
      }
    });

    test('أول تشغيل يولّد ويحفظ', () async {
      final store = MemoryDbKeyStore();
      final r = await resolveKey(store, encryptedDataExists: false);
      expect(r.isFirstRun, isTrue);
      expect(await store.read(), r.key);
    });

    test('التشغيل التالي يستعمل المحفوظ لا يولّد جديداً', () async {
      final store = MemoryDbKeyStore();
      final first = await resolveKey(store, encryptedDataExists: false);
      final second = await resolveKey(store, encryptedDataExists: false);
      expect(second.key, first.key, reason: 'مفتاح جديد = قاعدة لا تُفتح');
      expect(second.isFirstRun, isFalse);
    });

    test('مفتاح مفقود مع قاعدة مشفَّرة ⇒ خطأ صريح لا توليد صامت', () async {
      markEncrypted(tmp.path);
      final store = MemoryDbKeyStore(); // فارغ — كأن المخزن مُسح

      expect(() => resolveKey(store, encryptedDataExists: true),
          throwsA(isA<DbKeyMissingException>()),
          reason: 'م83: توليدُ مفتاح هنا يُنشئ قاعدة فارغة تبدو كأن '
              'البيانات تبخّرت — أسوأ فشل ممكن لأنه صامت');
      expect(await store.read(), isNull, reason: 'ولم يُكتب شيء');
    });

    test('العلامة تُميّز أول تشغيل من فقدان المفتاح', () {
      expect(isMarkedEncrypted(tmp.path), isFalse);
      markEncrypted(tmp.path);
      expect(isMarkedEncrypted(tmp.path), isTrue);
      markEncrypted(tmp.path); // عديم الأثر
      expect(isMarkedEncrypted(tmp.path), isTrue);
    });

    test('صيغة PRAGMA خام لا مشتقّة — والاقتباس المزدوج جزء منها', () {
      // بلا الاقتباس الخارجي يرمي المحلّل syntax error: `x'...'` وحدها
      // حرفيةُ بايتات لا سلسلة. رُصد بالتشغيل لا بالمراجعة.
      expect(pragmaKeyLiteral('abc123'), '"x\'abc123\'"');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م83/ج — الترحيل من سادة إلى مشفَّرة', () {
    void seedPlain() {
      final db = LocalDb.open(dbPath());
      db.execute(
          "INSERT INTO patients (id, name, phone) VALUES ('p1',?,?)",
          ['سالم المبروك', '0912345678']);
      db.execute(
          "INSERT INTO records (id, patient_name, date, service, amount) "
          "VALUES ('r1','سالم المبروك','2026-03-11','حشو',1250.75)");
      db.close();
    }

    test('الترحيل ينقل كل البيانات ويُشفّر الملف', () {
      seedPlain();
      expect(isPlainDatabase(dbPath()), isTrue);
      expect(bytesContain(dbPath(), 'سالم المبروك'), isTrue);

      final key = generateDbKey();
      final r = migrateToEncrypted(dbPath: dbPath(), hexKey: key);

      expect(r.migrated, isTrue, reason: r.reason);
      expect(isPlainDatabase(dbPath()), isFalse);
      expect(bytesContain(dbPath(), 'سالم المبروك'), isFalse,
          reason: 'م83: بعد الترحيل لا اسم مقروء في البايتات');

      // والبيانات كاملة — بالقيمة الكسرية بالضبط.
      final db = LocalDb.open(dbPath(), encryptionKey: key);
      expect(db.query('SELECT * FROM patients'), hasLength(1));
      final rec = db.queryFirst('SELECT * FROM records WHERE id = ?', ['r1']);
      expect(rec?['amount'], 1250.75, reason: 'المال بلا تقريب');
      expect(db.queryFirst('SELECT * FROM patients')?['name'], 'سالم المبروك');
      db.close();
    });

    test('نسخة احتياطية تُترك بجواره — طوق نجاة', () {
      seedPlain();
      final r = migrateToEncrypted(dbPath: dbPath(), hexKey: generateDbKey());
      expect(r.backupPath, isNotNull);
      expect(hasPlainBackup(dbPath()), isTrue);
      expect(isPlainDatabase(r.backupPath!), isTrue,
          reason: 'النسخة سادة وقابلة للفتح فوراً عند الحاجة');
    });

    test('النسخة لا تُحذف تلقائياً — والحذف فعلٌ صريح', () {
      seedPlain();
      migrateToEncrypted(dbPath: dbPath(), hexKey: generateDbKey());
      expect(hasPlainBackup(dbPath()), isTrue,
          reason: 'م83: حذفها قبل التأكد يُلغي طوق النجاة');

      expect(dropPlainBackup(dbPath()), isTrue);
      expect(hasPlainBackup(dbPath()), isFalse,
          reason: 'وبقاؤها بعد التأكد يُبطل التشفير عملياً');
    });

    test('الترحيل عديم الأثر — إعادته لا تُفسد', () {
      seedPlain();
      final key = generateDbKey();
      expect(migrateToEncrypted(dbPath: dbPath(), hexKey: key).migrated, isTrue);

      final again = migrateToEncrypted(dbPath: dbPath(), hexKey: key);
      expect(again.migrated, isFalse);
      expect(again.reason, contains('مشفَّرة أصلاً'));

      final db = LocalDb.open(dbPath(), encryptionKey: key);
      expect(db.query('SELECT * FROM patients'), hasLength(1));
      db.close();
    });

    test('لا قاعدة بعد ⇒ لا عمل ولا خطأ', () {
      final r = migrateToEncrypted(dbPath: dbPath(), hexKey: generateDbKey());
      expect(r.migrated, isFalse);
      expect(r.reason, contains('لا قاعدة'));
    });

    test('**الأهم**: إخفاق الترحيل يترك الأصل سليماً كما كان', () {
      seedPlain();
      final before = File(dbPath()).readAsBytesSync();

      // ملف تالف يحتل مكان المؤقّت ويمنع التصدير.
      final blocker = Directory('${dbPath()}.enc-tmp');
      blocker.createSync(); // مجلد لا ملف ⇒ الكتابة تفشل حتماً

      final r = migrateToEncrypted(dbPath: dbPath(), hexKey: generateDbKey());
      expect(r.migrated, isFalse, reason: 'أخفق كما هو مقصود');

      // وهذا هو الشرط الذي لا يجوز كسره أبداً:
      expect(File(dbPath()).existsSync(), isTrue, reason: 'م83: الأصل موجود');
      expect(File(dbPath()).readAsBytesSync(), equals(before),
          reason: 'م83: **الأصل لم يتغيّر بايتاً واحداً**');
      expect(isPlainDatabase(dbPath()), isTrue);

      final db = LocalDb.open(dbPath());
      expect(db.query('SELECT * FROM patients'), hasLength(1),
          reason: 'ويُفتح ويُقرأ كما كان');
      db.close();
      blocker.deleteSync(recursive: true);
    });

    test('كشف نوع القاعدة يقرأ البايتات لا يحاول الفتح', () {
      seedPlain();
      expect(isPlainDatabase(dbPath()), isTrue);
      migrateToEncrypted(dbPath: dbPath(), hexKey: generateDbKey());
      expect(isPlainDatabase(dbPath()), isFalse);

      expect(isPlainDatabase(p.join(tmp.path, 'لا-وجود.db')), isFalse);
      final empty = File(p.join(tmp.path, 'فارغ.db'))..writeAsStringSync('');
      expect(isPlainDatabase(empty.path), isFalse, reason: 'ملف فارغ لا يرمي');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م83/د — التوافق: بلا مفتاح لا يتغيّر شيء', () {
    test('الفتح السادّ يعمل كما كان حرفياً', () {
      final db = LocalDb.open(dbPath());
      db.execute("INSERT INTO patients (id, name) VALUES ('p1','منى')");
      expect(db.query('SELECT * FROM patients'), hasLength(1));
      db.close();
      expect(isPlainDatabase(dbPath()), isTrue);
    });

    test('openBootstrappedDb بلا مفتاح لا يُصدر PRAGMA key', () {
      final db = openBootstrappedDb(dbPath());
      db.execute("INSERT INTO patients (id, name) VALUES ('p1','ن')");
      db.close();
      expect(isPlainDatabase(dbPath()), isTrue,
          reason: 'م83: السلوك الافتراضي لم يتغيّر — 614 اختباراً تعتمد عليه');
    });

    test('المكتبة المحمَّلة تدعم PRAGMA key فعلاً', () {
      // لو عادت البيئة إلى SQLite العادية لمرّ كل ما سبق كاذباً: `PRAGMA
      // key` تُتجاهَل بصمت هناك. هذا الاختبار يمنع ذلك الصمت.
      final path = p.join(tmp.path, 'cap.db');
      final db = sq.sqlite3.open(path);
      db.execute("PRAGMA key = \"x'${'ab' * 32}'\";");
      db.execute('CREATE TABLE t(v TEXT)');
      db.execute("INSERT INTO t VALUES ('علامة')");
      db.close();
      expect(bytesContain(path, 'علامة'), isFalse,
          reason: 'م83: المكتبة تشفّر فعلاً — لا SQLite عادية تتجاهل PRAGMA');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  م83/هـ — مجلد البيانات على ويندوز: Roaming ينسخ المرضى إلى خادم الشبكة
  // ══════════════════════════════════════════════════════════════════════
  group('م83/هـ — نقل مجلد البيانات خارج Roaming', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('m83_paths_'));
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    /// يحاكي بنية ويندوز: AppData/Roaming/... وAppData/Local/...
    String roamingDir() => p.join(root.path, 'AppData', 'Roaming', 'dental');

    void seed(String dir) {
      Directory(dir).createSync(recursive: true);
      File(p.join(dir, 'dental_clinic_offline.db')).writeAsStringSync('DB');
      File(p.join(dir, 'cloud_config.json')).writeAsStringSync('{}');
      Directory(p.join(dir, 'exports')).createSync();
      File(p.join(dir, 'exports', 'a.pdf')).writeAsStringSync('PDF');
    }

    test('على غير ويندوز لا يُلمس شيء إطلاقاً', () {
      final d = roamingDir();
      seed(d);
      final r = ensureNonRoamingDataDir(d, isWindows: false);
      expect(r.dir, d);
      expect(r.moved, isFalse);
      expect(File(p.join(d, 'cloud_config.json')).existsSync(), isTrue);
    });

    test('مسارٌ خارج Roaming يعود كما هو حتى على ويندوز', () {
      final d = p.join(root.path, 'AppData', 'Local', 'dental');
      seed(d);
      final r = ensureNonRoamingDataDir(d, isWindows: true);
      expect(r.dir, d);
      expect(r.moved, isFalse);
    });

    test('ينقل المجلد **كله** لا القاعدة وحدها', () {
      // نقل القاعدة وحدها يفصلها عن إعدادها وعلامة تشفيرها وصادراتها.
      final src = roamingDir();
      seed(src);
      final r = ensureNonRoamingDataDir(src, isWindows: true);

      expect(r.moved, isTrue);
      expect(isRoamingPath(r.dir), isFalse, reason: 'م83: خرج من Roaming');
      expect(File(p.join(r.dir, 'dental_clinic_offline.db')).existsSync(), isTrue);
      expect(File(p.join(r.dir, 'cloud_config.json')).existsSync(), isTrue);
      expect(File(p.join(r.dir, 'exports', 'a.pdf')).readAsStringSync(), 'PDF',
          reason: 'م83: الأشجار الفرعية تنتقل بمحتواها');
    });

    test('يترك فتاتَ خبز في المكان القديم', () {
      final src = roamingDir();
      seed(src);
      ensureNonRoamingDataDir(src, isWindows: true);
      final note = File(p.join(src, 'MOVED_TO.txt'));
      expect(note.existsSync(), isTrue);
      expect(note.readAsStringSync(), contains('Local'));
    });

    test('عديم الأثر: النداء الثاني لا ينقل ولا يدمج', () {
      final src = roamingDir();
      seed(src);
      final first = ensureNonRoamingDataDir(src, isWindows: true);

      // بعد النقل: المستخدم يعمل، فتتغيّر بيانات Local.
      File(p.join(first.dir, 'cloud_config.json')).writeAsStringSync('{"new":1}');
      // ثم يظهر شيءٌ قديم في Roaming (مزامنة نطاق متأخّرة مثلاً).
      Directory(src).createSync(recursive: true);
      File(p.join(src, 'cloud_config.json')).writeAsStringSync('{"OLD":1}');

      final second = ensureNonRoamingDataDir(src, isWindows: true);
      expect(second.dir, first.dir);
      expect(second.moved, isFalse);
      expect(File(p.join(first.dir, 'cloud_config.json')).readAsStringSync(),
          '{"new":1}',
          reason: 'م83: الوجهة هي الحقيقة — الدمج قد يُعيد قديماً فوق أحدث');
    });

    test('تثبيت جديد: يبدأ محلياً بلا نقل', () {
      final src = roamingDir();
      final r = ensureNonRoamingDataDir(src, isWindows: true);
      expect(r.moved, isFalse);
      expect(isRoamingPath(r.dir), isFalse);
      expect(Directory(r.dir).existsSync(), isTrue);
    });

    test('حساب التوأم يحفظ بقية المسار حرفياً', () {
      expect(localTwinOf(r'C:\Users\d\AppData\Roaming\com.dental\clinic'),
          r'C:\Users\d\AppData\Local\com.dental\clinic');
      expect(isRoamingPath(r'C:\Users\d\AppData\Roaming\x'), isTrue);
      expect(isRoamingPath(r'C:\Users\d\AppData\Local\x'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  م83/و — متتالية الإقلاع: أخطر تسلسل في التطبيق
  // ══════════════════════════════════════════════════════════════════════
  group('م83/و — إقلاع القاعدة المشفَّرة', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('m83_boot_'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    String dbPath() => p.join(dir.path, kDbFileName);

    /// قاعدة سادة عليها مريض — كما لو كان التطبيق يعمل قبل الترقية.
    void seedPlainDb(String name) {
      final db = LocalDb.open(dbPath());
      db.execute("INSERT INTO patients (id,name) VALUES ('p1',?)", [name]);
      db.close();
    }

    test('أول تشغيل بلا قاعدة: مفتاحٌ يُولَّد وعلامةٌ تُوضع', () async {
      final store = MemoryDbKeyStore();
      final r = await prepareDatabase(
          supportDir: dir.path, keyStore: store, isWindows: false);

      expect(r.status, DbBootStatus.ready);
      expect(r.canOpen, isTrue);
      expect(r.encryptionKey, isNotNull);
      expect(r.encryptionKey!.length, kDbKeyBytes * 2);
      expect(await store.read(), r.encryptionKey, reason: 'حُفظ في المخزن');
      expect(isMarkedEncrypted(dir.path), isTrue);
    });

    test('القاعدة المُنشأة بعد الإقلاع مشفَّرة فعلاً على القرص', () async {
      final r = await prepareDatabase(
          supportDir: dir.path,
          keyStore: MemoryDbKeyStore(),
          isWindows: false);
      final db = LocalDb.open(dbPath(), encryptionKey: r.encryptionKey);
      db.execute("INSERT INTO patients (id,name) VALUES ('p1','سلمى الحلبي')");
      db.close();

      expect(isPlainDatabase(dbPath()), isFalse);
      expect(bytesContain(dbPath(), 'سلمى الحلبي'), isFalse,
          reason: 'م83: الاسم غير مقروء في بايتات الملف');
    });

    test('ترقيةُ تثبيتٍ قائم: تُرحَّل القاعدة وتُحفظ البيانات', () async {
      seedPlainDb('نورا العطّار');
      expect(isPlainDatabase(dbPath()), isTrue);

      final store = MemoryDbKeyStore();
      final r = await prepareDatabase(
          supportDir: dir.path, keyStore: store, isWindows: false);

      expect(r.status, DbBootStatus.migrated);
      expect(r.canOpen, isTrue);
      expect(isPlainDatabase(dbPath()), isFalse);

      final db = LocalDb.open(dbPath(), encryptionKey: r.encryptionKey);
      final rows = db.query("SELECT name FROM patients WHERE id='p1'");
      db.close();
      expect(rows.first['name'], 'نورا العطّار',
          reason: 'م83: الترحيل ينقل البيانات لا يُنشئ فارغاً');
      expect(r.backupPath, isNotNull);
      expect(File(r.backupPath!).existsSync(), isTrue,
          reason: 'طوق النجاة باقٍ حتى يحذفه المالك');
    });

    test('الإقلاع الثاني يفتح بلا ترحيل ولا توليد', () async {
      final store = MemoryDbKeyStore();
      final first = await prepareDatabase(
          supportDir: dir.path, keyStore: store, isWindows: false);
      LocalDb.open(dbPath(), encryptionKey: first.encryptionKey)
        ..execute("INSERT INTO patients (id,name) VALUES ('p1','ريم')")
        ..close();

      final second = await prepareDatabase(
          supportDir: dir.path, keyStore: store, isWindows: false);
      expect(second.status, DbBootStatus.ready);
      expect(second.encryptionKey, first.encryptionKey,
          reason: 'م83: المفتاح لا يتغيّر بين الإقلاعات');

      final db = LocalDb.open(dbPath(), encryptionKey: second.encryptionKey);
      expect(db.query("SELECT name FROM patients").first['name'], 'ريم');
      db.close();
    });

    test('المفتاح مفقود: لا يُفتح شيء ولا يُولَّد بديل — والملف لا يُمسّ',
        () async {
      final store = MemoryDbKeyStore();
      final first = await prepareDatabase(
          supportDir: dir.path, keyStore: store, isWindows: false);
      LocalDb.open(dbPath(), encryptionKey: first.encryptionKey)
        ..execute("INSERT INTO patients (id,name) VALUES ('p1','هدى')")
        ..close();

      final before = File(dbPath()).readAsBytesSync();

      // جهازٌ جديد أو مخزنٌ مُسِح: العلامة موجودة والمفتاح لا.
      final empty = MemoryDbKeyStore();
      final r = await prepareDatabase(
          supportDir: dir.path, keyStore: empty, isWindows: false);

      expect(r.status, DbBootStatus.keyMissing);
      expect(r.canOpen, isFalse, reason: 'م83: لا فتح ولا قاعدة فارغة');
      expect(r.encryptionKey, isNull);
      expect(await empty.read(), isNull,
          reason: 'م83: لم يُولَّد مفتاح جديد فوق قاعدة قائمة');

      final after = File(dbPath()).readAsBytesSync();
      expect(after, orderedEquals(before),
          reason: 'م83: الملف لم يتغيّر بايتاً واحداً — البيانات سليمة');

      // والمفتاح الأصلي ما زال يفتحها: فقدانُ المفتاح لا فقدانُ البيانات.
      final db = LocalDb.open(dbPath(), encryptionKey: first.encryptionKey);
      expect(db.query("SELECT name FROM patients").first['name'], 'هدى');
      db.close();
    });

    test('إخفاق مخزن النظام يُبلَّغ ولا يرتدّ إلى السادة', () async {
      final r = await prepareDatabase(
          supportDir: dir.path,
          keyStore: _ThrowingKeyStore(),
          isWindows: false);
      expect(r.status, DbBootStatus.keyMissing);
      expect(r.canOpen, isFalse,
          reason: 'م83: الارتداد الصامت إلى نصٍّ مقروء تخفيضٌ أمني');
      expect(r.encryptionKey, isNull);
      expect(r.detail, contains('مخزن مفاتيح النظام'));
    });

    test('علم DB_PLAINTEXT يوقف التشفير صراحةً لا صمتاً', () async {
      final store = MemoryDbKeyStore();
      final r = await prepareDatabase(
          supportDir: dir.path,
          keyStore: store,
          isWindows: false,
          plaintextOverride: true);
      expect(r.status, DbBootStatus.plaintextByFlag);
      expect(r.canOpen, isTrue);
      expect(r.encryptionKey, isNull);
      expect(await store.read(), isNull, reason: 'لا مفتاح يُولَّد أصلاً');
      expect(isMarkedEncrypted(dir.path), isFalse,
          reason: 'م83: لا علامة كاذبة تمنع تشفيراً لاحقاً');
    });

    test('الإقلاع ينقل مجلد ويندوز ثم يعمل داخل الوجهة', () async {
      // الترتيب يهمّ: نقلٌ بعد وضع العلامة يتركها في المكان الخطأ.
      final roaming = p.join(dir.path, 'AppData', 'Roaming', 'dental');
      Directory(roaming).createSync(recursive: true);
      File(p.join(roaming, 'cloud_config.json')).writeAsStringSync('{}');

      final r = await prepareDatabase(
          supportDir: roaming,
          keyStore: MemoryDbKeyStore(),
          isWindows: true);

      expect(r.dirMoved, isTrue);
      expect(isRoamingPath(r.dataDir), isFalse);
      expect(isMarkedEncrypted(r.dataDir), isTrue,
          reason: 'م83: العلامة في المسار الجديد لا القديم');
      expect(isMarkedEncrypted(roaming), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  م83/ز — حراسة الإعداد: القيمة الخاطئة تُسرّب بلا صوت
  // ══════════════════════════════════════════════════════════════════════
  group('م83/ز — إعداد البناء محروس', () {
    test('pubspec يعلن source: sqlcipher لا بديلاً محلياً', () {
      // السيناريو الذي يمنعه هذا الاختبار: مطوّرٌ على لينكس قديم يوجّه
      // المصدر إلى مكتبة محلية ليُشغّل الاختبارات، ثم يودع التبديل سهواً.
      // النتيجة على ويندوز: `source: system` يلتقط sqlite3.dll النظام —
      // SQLite عادية — فتُتجاهل `PRAGMA key` صامتةً وتُكتب بيانات المرضى
      // نصّاً مقروءاً. لا اختبار آخر يكشف ذلك: كلها تمرّ.
      // ⚠ التعليقات تُستبعد قبل الفحص. أول صياغة فحصت الملف نصّاً كاملاً،
      // فطابقت `source: system` المذكورة في **تعليق pubspec التوثيقي**
      // نفسه — فصار الحارس أحمر دائماً بالتبديل وبدونه، أي عديم القيمة:
      // الانحدارُ الذي وُضع لصيده لا يُغيّر شيئاً في نتيجته. (كشفتها
      // مراجعة، بعد أن نسبتُ فشله إلى تبديلي المحلي.)
      final active = File('pubspec.yaml')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      expect(active, contains('source: sqlcipher'),
          reason: 'م83: مصدر المكتبة يجب أن يكون sqlcipher في ما يُشحن');
      expect(active, isNot(contains('source: system')),
          reason: 'م83: تبديلٌ محلي تسرّب إلى الإيداع — أعده قبل البناء');
    });

    test('الحارس الوقتي يرفض مكتبةً لا تشفّر', () {
      // إثباتٌ إيجابي أن المؤشّر الذي يعتمده الحارس حقيقي: SQLCipher
      // يعيد إصداره، والعادية تعيد صفر صفوف فيرمي الحارس.
      final db = sq.sqlite3.openInMemory();
      final v = db.select('PRAGMA cipher_version');
      db.close();
      expect(v, isNotEmpty,
          reason: 'م83: المكتبة المحمَّلة ليست SQLCipher — الحارس سيوقف الإقلاع');
      expect(v.first.values.first.toString(), contains('4.'));
    });

    test('minSdk له أرضية صريحة لا موروثة', () {
      final g = File('android/app/build.gradle.kts').readAsStringSync();
      // م88 — الأرضية ارتفعت 23→24: حزمة app_links (عودة deep-link لدخول
      // Google) تشترط 24. مقصدُ الحارس باقٍ كما هو: أرضيةٌ **صريحة**
      // تحمي متطلّب Keystore (23+) من تخفيضٍ صامت لافتراض الأدوات —
      // و24 تفي به بداهةً.
      expect(g, contains('maxOf(flutter.minSdkVersion, 24)'),
          reason: 'م83+م88: أرضية صريحة تغطي Keystore (23+) وapp_links (24)');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  م83/ح — خزنة الأشعة: أخطر بيانٍ كان خارج التشفير
  // ══════════════════════════════════════════════════════════════════════
  group('م83/ح — صور الأشعة داخل التشفير', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('m83_vault_'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    /// بايتات فيها توقيعٌ نصّي نبحث عنه في الملف الخام.
    Uint8List fakeImage(String marker) =>
        Uint8List.fromList([0xFF, 0xD8, 0xFF, ...utf8.encode(marker), 0xFF, 0xD9]);

    test('الخزنة السادة تحفظ السلوك القديم حرفياً', () {
      final v = PlainFileVault(dir.path);
      v.write('a.jpg', fakeImage('x'));
      expect(File(p.join(dir.path, 'a.jpg')).existsSync(), isTrue,
          reason: 'م83: بلا مفتاح يبقى ملفاً بالاسم نفسه');
      expect(v.read('a.jpg'), isNotNull);
      v.delete('a.jpg');
      expect(v.exists('a.jpg'), isFalse);
      v.close();
    });

    test('الخزنة المشفَّرة: البايتات تعود كما دخلت', () {
      final v = EncryptedBlobVault(dir: dir.path, hexKey: generateDbKey());
      final src = fakeImage('محتوى-الأشعة');
      v.write('scan.jpg', src);
      expect(v.exists('scan.jpg'), isTrue);
      expect(v.read('scan.jpg'), orderedEquals(src));
      expect(v.read('غائب.jpg'), isNull);
      v.delete('scan.jpg');
      expect(v.read('scan.jpg'), isNull);
      v.close();
    });

    test('ملف الخزنة مشفَّر ولا يحوي محتوى الصورة ولا اسم المريض', () {
      final v = EncryptedBlobVault(dir: dir.path, hexKey: generateDbKey());
      v.write('xray_أحمد_سعيد.jpg', fakeImage('بيانات-حسّاسة-جداً'));
      v.close();

      final vaultFile = p.join(dir.path, EncryptedBlobVault.fileName);
      expect(File(vaultFile).existsSync(), isTrue);
      expect(isPlainDatabase(vaultFile), isFalse,
          reason: 'م83: رأس الملف ليس SQLite السادة');
      expect(bytesContain(vaultFile, 'بيانات-حسّاسة-جداً'), isFalse);
      expect(bytesContain(vaultFile, 'أحمد_سعيد'), isFalse,
          reason: 'م83: حتى اسم المدخل مخفيّ — كان اسمَ ملف مقروءاً');
    });

    test('مفتاحٌ خاطئ لا يفتح الخزنة', () {
      final key = generateDbKey();
      EncryptedBlobVault(dir: dir.path, hexKey: key)
        ..write('a.jpg', fakeImage('س'))
        ..close();

      final wrong = EncryptedBlobVault(dir: dir.path, hexKey: generateDbKey());
      expect(() => wrong.read('a.jpg'), throwsA(anything));
      wrong.close();
    });

    test('الترحيل ينقل الصور القائمة ثم يحذف السادّ — بعد التحقق', () {
      final imagesDir = Directory(p.join(dir.path, 'xray_images'))
        ..createSync(recursive: true);
      final a = fakeImage('أشعة-واحد');
      final b = fakeImage('أشعة-اثنان');
      File(p.join(imagesDir.path, 'p1.jpg')).writeAsBytesSync(a);
      File(p.join(imagesDir.path, 'p2.thumb.jpg')).writeAsBytesSync(b);
      // ملفٌ ليس صورة — لا يُلمس.
      File(p.join(imagesDir.path, 'notes.txt')).writeAsStringSync('x');

      final v = EncryptedBlobVault(dir: imagesDir.path, hexKey: generateDbKey());
      final r = migratePlainImagesIntoVault(imagesDir: imagesDir.path, vault: v);

      expect(r.moved, 2);
      expect(r.failed, 0);
      expect(v.read('p1.jpg'), orderedEquals(a));
      expect(v.read('p2.thumb.jpg'), orderedEquals(b));
      expect(File(p.join(imagesDir.path, 'p1.jpg')).existsSync(), isFalse,
          reason: 'م83: السادّ يُحذف بعد التحقق لا قبله');
      expect(File(p.join(imagesDir.path, 'notes.txt')).existsSync(), isTrue,
          reason: 'م83: ما ليس صورة لا يُلمس');
      v.close();
    });

    test('الترحيل عديم الأثر — إعادته لا تكرّر ولا تُفسد', () {
      final imagesDir = Directory(p.join(dir.path, 'xray_images'))
        ..createSync(recursive: true);
      final a = fakeImage('صورة');
      File(p.join(imagesDir.path, 'p1.jpg')).writeAsBytesSync(a);

      final v = EncryptedBlobVault(dir: imagesDir.path, hexKey: generateDbKey());
      migratePlainImagesIntoVault(imagesDir: imagesDir.path, vault: v);
      final second =
          migratePlainImagesIntoVault(imagesDir: imagesDir.path, vault: v);
      expect(second.moved, 0);
      expect(v.read('p1.jpg'), orderedEquals(a));
      v.close();
    });

    test('صورةٌ لم تصل تبقى سادةً ولا تُحذف', () {
      final imagesDir = Directory(p.join(dir.path, 'xray_images'))
        ..createSync(recursive: true);
      File(p.join(imagesDir.path, 'p1.jpg')).writeAsBytesSync(fakeImage('س'));

      final r = migratePlainImagesIntoVault(
          imagesDir: imagesDir.path, vault: _SwallowingVault());
      expect(r.moved, 0);
      expect(r.failed, 1);
      expect(File(p.join(imagesDir.path, 'p1.jpg')).existsSync(), isTrue,
          reason: 'م83: لا يُحذف ما لم يُتحقق من وصوله');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  م83/ط — سيناريوهات الانقطاع: ما كشفته المراجعة ولم يكن مُختبَراً
  // ══════════════════════════════════════════════════════════════════════
  group('م83/ط — الانقطاع لا يُفقد ولا يُنشئ فارغاً', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('m83_crash_'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    String dbPath() => p.join(dir.path, kDbFileName);

    void seedPlain(String name) {
      LocalDb.open(dbPath())
        ..execute("INSERT INTO patients (id,name) VALUES ('p1',?)", [name])
        ..close();
    }

    test('موتٌ في نافذة الإبدال: الإقلاع يستعيد بدل أن يُنشئ فارغة', () async {
      // نُحاكي الحالة على القرص حرفياً: لا قاعدة في مكانها، وكلُّ البيانات
      // في `.enc-tmp` مشفَّراً. كان الإقلاع يرى «لا قاعدة» فيُنشئ فارغةً
      // فوق عيادة كاملة — وهي أسوأ نتيجة في المتتالية كلها.
      final store = MemoryDbKeyStore();
      final boot = await prepareDatabase(
          supportDir: dir.path, keyStore: store, isWindows: false);
      LocalDb.open(dbPath(), encryptionKey: boot.encryptionKey)
        ..execute("INSERT INTO patients (id,name) VALUES ('p1','مها')")
        ..close();
      File(dbPath()).renameSync('${dbPath()}.enc-tmp');
      expect(File(dbPath()).existsSync(), isFalse);

      final again = await prepareDatabase(
          supportDir: dir.path, keyStore: store, isWindows: false);
      expect(again.canOpen, isTrue);
      expect(again.detail, contains('استُعيد'));

      final db = LocalDb.open(dbPath(), encryptionKey: again.encryptionKey);
      expect(db.query('SELECT name FROM patients').first['name'], 'مها',
          reason: 'م83: البيانات عادت — لا قاعدة فارغة');
      db.close();
      expect(File('${dbPath()}.enc-tmp').existsSync(), isFalse);
    });

    test('مؤقّتٌ بمفتاح آخر لا يُلمس ولا يُعتمد', () {
      seedPlain('س');
      File(dbPath()).renameSync('${dbPath()}.enc-tmp');
      final ok = recoverInterruptedMigration(
          dbPath: dbPath(), hexKey: generateDbKey());
      expect(ok, isFalse, reason: 'م83: ما لا يفتح بمفتاحنا ليس لنا');
      expect(File('${dbPath()}.enc-tmp').existsSync(), isTrue);
    });

    test('علامةٌ مفقودة فوق قاعدة مشفَّرة: لا يُولَّد مفتاح فوقها', () async {
      final store = MemoryDbKeyStore();
      final boot = await prepareDatabase(
          supportDir: dir.path, keyStore: store, isWindows: false);
      LocalDb.open(dbPath(), encryptionKey: boot.encryptionKey)
        ..execute("INSERT INTO patients (id,name) VALUES ('p1','ليان')")
        ..close();
      final before = File(dbPath()).readAsBytesSync();

      // تنظيفُ مجلد أو استعادةٌ ناقصة تمحو العلامة، والمخزن فارغ.
      cipherMarker(dir.path).deleteSync();
      final empty = MemoryDbKeyStore();
      final r = await prepareDatabase(
          supportDir: dir.path, keyStore: empty, isWindows: false);

      expect(r.status, DbBootStatus.keyMissing,
          reason: 'م83: الحاكم رأسُ الملف لا وجود العلامة');
      expect(await empty.read(), isNull,
          reason: 'م83: مفتاحٌ جديد فوق مشفَّرة يجعل الفقد نهائياً');
      expect(File(dbPath()).readAsBytesSync(), orderedEquals(before));

      final db = LocalDb.open(dbPath(), encryptionKey: boot.encryptionKey);
      expect(db.query('SELECT name FROM patients').first['name'], 'ليان');
      db.close();
    });

    test('علامةٌ شاردة بلا بيانات: أول تشغيل لا طريقٌ مسدود', () async {
      markEncrypted(dir.path);
      expect(isMarkedEncrypted(dir.path), isTrue);
      final r = await prepareDatabase(
          supportDir: dir.path,
          keyStore: MemoryDbKeyStore(),
          isWindows: false);
      expect(r.canOpen, isTrue,
          reason: 'م83: لا يُرفض الإقلاع حمايةً لبياناتٍ لا وجود لها');
      expect(r.encryptionKey, isNotNull);
    });

    test('مفتاحٌ مخزَّن تالف: يُبلَّغ ولا يُستبدل', () async {
      final store = MemoryDbKeyStore();
      await store.write('ليس-مفتاحاً-hex');
      final r = await prepareDatabase(
          supportDir: dir.path, keyStore: store, isWindows: false);
      expect(r.canOpen, isFalse);
      expect(await store.read(), 'ليس-مفتاحاً-hex',
          reason: 'م83: لا يُكتب فوق مفتاح قد يكون مسترجَعاً');
    });

    test('النسخة السادة تُحذف بعد إقلاع يُثبت سلامة المشفَّرة', () async {
      seedPlain('غيداء');
      final store = MemoryDbKeyStore();
      final first = await prepareDatabase(
          supportDir: dir.path, keyStore: store, isWindows: false);
      expect(first.status, DbBootStatus.migrated);
      expect(hasPlainBackup(dbPath()), isTrue,
          reason: 'م83: الطوق يبقى خلال إقلاع الترحيل');
      expect(isPlainDatabase('${dbPath()}.plain-backup'), isTrue,
          reason: 'وهو مقروء بلا مفتاح — ولذلك لا يجوز بقاؤه');

      final second = await prepareDatabase(
          supportDir: dir.path, keyStore: store, isWindows: false);
      expect(hasPlainBackup(dbPath()), isFalse,
          reason: 'م83: نسخةٌ سادة باقية تُبطل التشفير كله');
      expect(second.detail, contains('حُذفت النسخة السادة'));

      final db = LocalDb.open(dbPath(), encryptionKey: second.encryptionKey);
      expect(db.query('SELECT name FROM patients').first['name'], 'غيداء');
      db.close();
    });

    test('نسخة الترحيل تشمل ما في WAL لا الملف الرئيس وحده', () {
      // الترحيل يجري عند الإقلاع — أي غالباً بعد انطفاء مفاجئ، وهي اللحظة
      // التي يحمل فيها WAL آخر ما أُودع. نسخةٌ أقدم من الناتج تُفقد جلسةً
      // كاملة عند الاستعادة، بصمت.
      final db = LocalDb.open(dbPath());
      db.execute("INSERT INTO patients (id,name) VALUES ('p1','أ')");
      db.execute("INSERT INTO patients (id,name) VALUES ('p2','ب')");
      // بلا إغلاق: الإيداعات في WAL والملف الرئيس ما يزال ناقصاً.
      expect(File('${dbPath()}-wal').existsSync(), isTrue);

      final r = migrateToEncrypted(dbPath: dbPath(), hexKey: generateDbKey());
      db.close();
      expect(r.migrated, isTrue);

      final backup = sq.sqlite3.open(r.backupPath!);
      final n = backup.select('SELECT count(*) AS n FROM patients').first['n'];
      backup.close();
      expect(n, 2, reason: 'م83: الطوق يساوي الناتج لا يقلّ عنه');
    });

    test('نسخٌ مقطوع لا يُعتمد وجهةً — المصدر يبقى الحقيقة', () {
      // نحاكي أثر انقطاعٍ في المسار الاحتياطي: مجلد `.partial` متروك.
      final roaming = p.join(dir.path, 'AppData', 'Roaming', 'app');
      Directory(roaming).createSync(recursive: true);
      File(p.join(roaming, kDbFileName)).writeAsStringSync('DB');
      final target = localTwinOf(roaming);
      Directory('$target.partial').createSync(recursive: true);
      File(p.join('$target.partial', 'cloud_config.json')).writeAsStringSync('{}');

      final r = ensureNonRoamingDataDir(roaming, isWindows: true);
      expect(File(p.join(r.dir, kDbFileName)).existsSync(), isTrue,
          reason: 'م83: البقايا الجزئية لا تُعتمد مكان المصدر السليم');
    });

    test('تصنيف الملف يميّز الغائب من السادّ من المشفَّر', () {
      expect(classifyDb(dbPath()), DbFileState.absent);
      seedPlain('س');
      expect(classifyDb(dbPath()), DbFileState.plain);
      migrateToEncrypted(dbPath: dbPath(), hexKey: generateDbKey());
      expect(classifyDb(dbPath()), DbFileState.encrypted);
    });
  });
}

/// مخزنٌ يُخفق دائماً — يحاكي منصّةً بلا خدمة أسرار.
class _ThrowingKeyStore implements DbKeyStore {
  @override
  Future<String?> read() async => throw StateError('keystore unavailable');
  @override
  Future<void> write(String key) async => throw StateError('keystore unavailable');
  @override
  Future<void> delete() async {}
}

/// خزنةٌ تبتلع الكتابة — تحاكي قرصاً ممتلئاً أو خزنةً معطوبة.
class _SwallowingVault implements BlobVault {
  @override
  bool exists(String name) => false;
  @override
  Uint8List? read(String name) => null;
  @override
  void write(String name, Uint8List bytes) {/* لا شيء */}
  @override
  void delete(String name) {}
  @override
  void close() {}
}
