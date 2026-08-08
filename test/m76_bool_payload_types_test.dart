/// اختبارات م76 — لا علَم منطقي يُخزَّن أو يُدفع. الأعلام أرقام دائماً.
///
///  العلة
///  ─────
///  مسار التركيبات في [saveNewRecord] كان يكتب `'isDebt': f.isDebt` منطقيةً
///  خاماً، بينما مسار السجل العادي يكتب `f.isDebt ? 1 : 0`. حقلٌ واحد،
///  كتابتان مختلفتان — ونجا أحدهما بالمصادفة لا بالتصميم:
///
///    • `records._columns`   يضمّ `isDebt` ⇒ يذهب إلى عمود SQLite، فينقذه
///      `_bindable` صامتاً بتحويله 0/1.
///    • `prosthetics._columns` **لا يضمّه** ⇒ يسلكه `prepareForStorage` إلى
///      كتلة `data` عبر `jsonEncode`، ولا منقذ هناك: تُخزَّن
///      `"isDebt": false` منطقيةً، وتُدفع كما هي إلى الخادم.
///
///  الأثر
///  ─────
///  محلياً: **لا أثر** — `json_extract` في SQLite يُطبّع المنطقي إلى 0/1،
///  ولهذا ظلّت العلة غير مرئية من داخل التطبيق طوال الوقت.
///  على الخادم: `payload->>'isDebt'` يُرجع النصّ `'true'` فيرفضه `::int`
///  بـ`22P02`، و**صفٌّ واحد فاسد يُسقط التقرير الشهري كلّه لا سطراً منه**.
///
///  لماذا فات على الفحص السابق
///  ──────────────────────────
///  فُحص كيان `records` فوجد نظيفاً، فاستُنتج أن العميل أُصلح. الفحص كان
///  صحيحاً والاستنتاج خاطئاً: الكيان المصاب `prosthetics` ولم يُفحص.
///  لذلك تؤكّد الاختبارات هنا على **الكيانين معاً**، وتقرأ الكتلة الخام
///  من SQL لا الرؤية المدموجة — فالرؤية المدموجة هي بالضبط ما كان يغطّي
///  العلة.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/data/dto/record_dto.dart'
    show toRecordDb;
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/push.dart'
    show buildOp, normalizeWireFlags;
import 'package:dental_clinic_flutter/features/finance/debt_actions.dart'
    show payDebtInstallment;
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m76_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> config() => {
        'centerName': 'مركز',
        'doctorPct': 50,
        'clinics': ['الصفوة'],
        'services': ['حشو', 'تركيبات'],
        'payments': ['كاش'],
      };

  ProviderContainer boot() {
    final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    addTearDown(c.dispose);
    return c;
  }

  /// كتلة `data` الخام كما هي على القرص — لا الصف المدموج.
  /// قراءة الرؤية المدموجة كانت ستُظهر العلة سليمةً، لأن `parseRowData`
  /// يعيد منطقي JSON قيمةً منطقية في Dart فتبدو «صحيحة» للمستدعي.
  Map<String, Object?> rawBlob(ProviderContainer c, String table, String id) {
    final r = c
        .read(localDbProvider)
        .query('SELECT data FROM $table WHERE id = ?', [id]).single;
    final s = r['data'];
    if (s == null || '$s'.isEmpty) return {};
    return Map<String, Object?>.from(jsonDecode('$s') as Map);
  }

  /// محاكاة دقيقة لما يفعله الخادم: `(payload->>'k')::int`.
  /// المعامل `->>` يُرجع **نصّ** قيمة JSON، فمنطقي JSON يصير `'true'`/
  /// `'false'` ويرفضه التحويل إلى عدد صحيح. هذه الدالة تُخفق حيث يُخفق
  /// Postgres تماماً، فتصير خضرة الاختبار دليلاً على سلامة الخادم لا على
  /// سلامة العميل وحده.
  int pgCastToInt(Object? jsonValue) {
    final asText = jsonValue == null ? null : jsonEncode(jsonValue);
    if (asText == null) return 0;
    final unquoted =
        asText.startsWith('"') ? asText.substring(1, asText.length - 1) : asText;
    final n = int.tryParse(unquoted);
    if (n == null) {
      fail('ERROR 22P02: invalid input syntax for type integer: "$unquoted" '
          '— قيمة JSON منطقية وصلت الخادم؛ هذه هي علّة م76 عائدةً.');
    }
    return n;
  }

  // ──────────────────────────────────────────────────────────────────────
  group('م76 — التخزين المحلي: الكتلة لا تحمل منطقياً', () {
    for (final isDebt in [true, false]) {
      test('تركيبة بـisDebt=$isDebt تُخزَّن رقماً في كتلة data', () {
        final c = boot();
        final repos = c.read(reposProvider);

        final res = saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'سالم', date: getCurrentDate(), amount: 1000,
              clinic: 'الصفوة', service: 'تركيبات', payment: 'كاش',
              isDebt: isDebt, firstPay: isDebt ? 200 : 0, labValue: 300,
            ));
        expect(res.isPros, isTrue, reason: 'المسار المقصود هو مسار التركيبات');

        final blob = rawBlob(c, 'prosthetics', res.entryId);
        expect(blob.containsKey('isDebt'), isTrue,
            reason: 'isDebt ليس عموداً في prosthetics ⇒ مكانه الكتلة');
        expect(blob['isDebt'], isNot(isA<bool>()),
            reason: 'م76: الكتلة كانت تحمل منطقي JSON — هذا جذر العلة');
        expect(blob['isDebt'], isDebt ? 1 : 0);
        expect(pgCastToInt(blob['isDebt']), isDebt ? 1 : 0,
            reason: 'يجب أن ينجو من ::int على الخادم');
      });
    }

    test('سجل عادي: الأعلام تصل الأعمدة رقماً — تثبيت المسار الناجي', () {
      final c = boot();
      final repos = c.read(reposProvider);
      final res = saveNewRecord(
          repos,
          config(),
          SaveRecordInput(
            name: 'ليلى', date: getCurrentDate(), amount: 500,
            clinic: 'الصفوة', service: 'حشو', payment: 'كاش', isDebt: true,
            firstPay: 100,
          ));

      final row = c.read(localDbProvider).query(
          'SELECT isDebt, isPros, isDebtPayment FROM records WHERE id = ?',
          [res.entryId]).single;
      for (final k in ['isDebt', 'isPros', 'isDebtPayment']) {
        expect(row[k], isNot(isA<bool>()), reason: '$k عمود رقمي');
      }
      expect(row['isDebt'], 1);
    });

    test('سجل دفعة دين: أعلامه رقمية في العمود وفي الكتلة معاً', () {
      final c = boot();
      final repos = c.read(reposProvider);
      saveNewRecord(
          repos,
          config(),
          SaveRecordInput(
            name: 'منى', date: getCurrentDate(), amount: 1000,
            clinic: 'الصفوة', service: 'حشو', payment: 'كاش',
            isDebt: true, firstPay: 200,
          ));
      final debt = repos.debts.getAll().single;
      payDebtInstallment(repos, config(), debt,
          amount: 300, date: getCurrentDate(), payment: 'كاش');

      final payRecs = c.read(localDbProvider).query(
          'SELECT id, isDebt, isPros, isDebtPayment, data FROM records '
          'WHERE COALESCE(isDebtPayment,0) = 1');
      expect(payRecs, isNotEmpty, reason: 'أُنشئ سجل دفعة واحد على الأقل');
      for (final r in payRecs) {
        for (final k in ['isDebt', 'isPros', 'isDebtPayment']) {
          expect(r[k], isNot(isA<bool>()), reason: 'العمود $k رقمي');
        }
        final blob = rawBlob(c, 'records', '${r['id']}');
        for (final e in blob.entries) {
          expect(e.value, isNot(isA<bool>()),
              reason: 'م76: لا منطقي في كتلة سجل الدفعة — المفتاح ${e.key}');
        }
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  group('م76 — حمولة السلك: الحارس يُغلق الفئة لا الحالة', () {
    SyncContext ctxOf(ProviderContainer c) => SyncContext(
          db: c.read(localDbProvider),
          repos: c.read(reposProvider),
          transport: c.read(transportProvider),
        );

    test('حمولة التركيبة الحقيقية تخلو من المنطقيات وتنجو من ::int', () {
      final c = boot();
      final repos = c.read(reposProvider);
      final res = saveNewRecord(
          repos,
          config(),
          SaveRecordInput(
            name: 'خالد', date: getCurrentDate(), amount: 800,
            clinic: 'الصفوة', service: 'جسر', payment: 'كاش', isDebt: true,
            firstPay: 100, labValue: 200,
          ));

      final row = repos.prosthetics.getById(res.entryId)!;
      final op = buildOp(ctxOf(c), 'prosthetics', Map<String, Object?>.from(row));

      for (final e in op.row.entries) {
        expect(e.value, isNot(isA<bool>()),
            reason: 'م76: المفتاح ${e.key} غادر منطقياً إلى الشبكة');
      }
      expect(pgCastToInt(op.row['isDebt']), 1);

      // الشرط الحاسم على السلك: النصّ المُرسَل نفسه.
      final wire = jsonEncode(op.toWire());
      expect(wire, isNot(contains('"isDebt":true')));
      expect(wire, isNot(contains('"isDebt":false')));
      expect(wire, contains('"isDebt":1'));
    });

    test('منطقي مهرَّب من كتلة data لا يعبر الحارس — ولو من جيل عميل آخر',
        () {
      final c = boot();
      final repos = c.read(reposProvider);
      final res = saveNewRecord(
          repos,
          config(),
          SaveRecordInput(
            name: 'نادر', date: getCurrentDate(), amount: 400,
            clinic: 'الصفوة', service: 'حشو', payment: 'كاش',
          ));

      // محاكاة صفٍّ كتبه جيل عميل قديم: منطقيات محفوظة في الكتلة، تعود
      // منطقيات Dart بعد parseRowData. بلا الحارس تُدفع كما هي فتُعيد
      // تسميم الخادم عند أول تعديل محلي على الصف.
      final poisoned = <String, Object?>{
        ...repos.records.getById(res.entryId)!,
        'isDebt': false,
        'isPros': true,
        'isDebtPayment': false,
        'legacyFlag': true,
      };
      final op = buildOp(ctxOf(c), 'records', poisoned);

      for (final e in op.row.entries) {
        expect(e.value, isNot(isA<bool>()),
            reason: 'م76: ${e.key} تسلّل منطقياً عبر الحارس');
      }
      expect(op.row['isDebt'], 0);
      expect(op.row['isPros'], 1);
      expect(op.row['legacyFlag'], 1,
          reason: 'الحارس يغطي الفئة كلها لا الأعلام الثلاثة المعروفة');
      expect(pgCastToInt(op.row['isPros']), 1);
    });

    test('نطاق الحارس مقصود: المتداخل لا يُمسّ ولو مرّ عليه الحارس', () {
      // ١) خط الدفاع الأول أن buildOp لا يستدعي الحارس على الإعدادات أصلاً
      //    (يُثبَّت في الاختبار التالي). وهذا خط الدفاع الثاني: حتى لو
      //    استُدعي عليها، فمنطقيات `value` المشروعة (أعلام الواجهة) تنجو
      //    لأن التطبيع لا يتجاوز المستوى الأعلى.
      final settingsPayload = normalizeWireFlags(<String, Object?>{
        'id': 'app.config',
        'value': {'darkMode': true, 'compact': false},
      });
      final v = settingsPayload['value'] as Map;
      expect(v['darkMode'], isTrue,
          reason: 'تطبيع إعدادات الحساب يفسد دلالتها');
      expect(v['compact'], isFalse);

      // ٢) المتداخل لا يُمسّ — الأعلام المسطّحة وحدها هي فئة العلة.
      final rowPayload = normalizeWireFlags(<String, Object?>{
        'isDebt': true,
        'report': {'entries': [{'done': true}]},
        'installments': [{'paid': false}],
      });
      expect(rowPayload['isDebt'], 1, reason: 'المسطّح يُطبَّع');
      expect(((rowPayload['report'] as Map)['entries'] as List).first,
          {'done': true},
          reason: 'المتداخل يبقى بدلالته');
      expect((rowPayload['installments'] as List).first, {'paid': false});
    });

    test('حمولة settings الحقيقية عبر buildOp تحتفظ بمنطقياتها', () {
      final c = boot();
      final repos = c.read(reposProvider);
      repos.settings.set('app.config', {'darkMode': true});

      final raw = c
          .read(localDbProvider)
          .query("SELECT * FROM settings WHERE id LIKE 'cfg:%' OR id = ?",
              ['app.config']);
      expect(raw, isNotEmpty, reason: 'كُتب صف إعدادات واحد على الأقل');

      final op = buildOp(
          ctxOf(c), 'settings', Map<String, Object?>.from(raw.first));
      expect(op.entity, 'settings');
      // لا تأكيد على شكل القيمة (v30 يفكّكها لصفوف مفاتيح) — المهم أن
      // مسار الإعدادات لم يمرّ بالحارس أصلاً، فلا تطبيع يُطبَّق عليه.
      expect(op.row.containsKey('value'), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  group('م76 — toRecordDb: سلك التفجير المنزوع', () {
    test('المفاتيح الغائبة تُنتج صفراً لا false', () {
      final out = toRecordDb({'id': 'r1', 'name': 'س', 'amount': 10});
      for (final k in ['isDebt', 'isDebtPayment', 'isPros']) {
        expect(out[k], isNot(isA<bool>()), reason: '$k احتياطيّه رقمي');
        expect(out[k], 0);
      }
    });

    test('المنطقي الوارد يُطبَّع — تصحيح الاحتياطي وحده كان نصف علاج', () {
      // `jsOr(true, false)` كان يُرجع `true` كما هو: العلة لم تكن في
      // الاحتياطي فقط بل في تمرير الطرف الصادق دون تطبيع.
      final out = toRecordDb({
        'id': 'r2', 'isDebt': true, 'isPros': true, 'isDebtPayment': true,
      });
      expect(out['isDebt'], 1);
      expect(out['isPros'], 1);
      expect(out['isDebtPayment'], 1);
      for (final k in ['isDebt', 'isDebtPayment', 'isPros']) {
        expect(out[k], isNot(isA<bool>()));
      }
    });

    test('الأرقام الواردة تمرّ كما هي', () {
      final out = toRecordDb({'id': 'r3', 'isDebt': 1, 'isPros': 0});
      expect(out['isDebt'], 1);
      expect(out['isPros'], 0);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  test('م76 — مسح شامل: لا منطقي في أي كتلة data بعد سيناريو كامل', () {
    final c = boot();
    final repos = c.read(reposProvider);
    final cfg = config();

    saveNewRecord(
        repos,
        cfg,
        SaveRecordInput(
          name: 'أحمد', date: getCurrentDate(), amount: 1200,
          clinic: 'الصفوة', service: 'تركيبات', payment: 'كاش',
          isDebt: true, firstPay: 300, labValue: 400,
        ));
    saveNewRecord(
        repos,
        cfg,
        SaveRecordInput(
          name: 'هدى', date: getCurrentDate(), amount: 250,
          clinic: 'الصفوة', service: 'حشو', payment: 'كاش',
        ));
    final debt = repos.debts.getAll().first;
    payDebtInstallment(repos, cfg, debt,
        amount: 200, date: getCurrentDate(), payment: 'كاش');

    final db = c.read(localDbProvider);
    final offenders = <String>[];
    for (final table in ['records', 'prosthetics', 'debts', 'patients']) {
      for (final r in db.query('SELECT id, data FROM $table')) {
        final s = r['data'];
        if (s == null || '$s'.isEmpty) continue;
        final decoded = jsonDecode('$s');
        if (decoded is! Map) continue;
        decoded.forEach((k, v) {
          if (v is bool) offenders.add('$table.${r['id']}.$k = $v');
        });
      }
    }
    expect(offenders, isEmpty,
        reason: 'م76: كل قيمة منطقية هنا صفٌّ سيكسر ::int على الخادم');
  });
}
