/// اختبارات م4ج — مخطط الأسنان والأشعة والمختبرات والأرشيف:
/// كشف نقر المخطط بنفس مستطيلات TOOTH_DATA، توفيق «تحديد الأسنان» الحرفي
/// (إسقاط الملغى + إضافة الجديد لمعالجة حاضنة)، الحالة المالية لحالات
/// المختبر من الدين المرتبط، حسابات الأرشيف الشهري بكل استثناءاتها —
/// ثم رحلات الواجهة: تقرير سن يُحفظ على السجل من شاشة الإضافة، محرر أسنان
/// الملف يكتب على الصف والدين المرتبط، رفع/تسمية/حذف أشعة حتى القاعدة
/// والملف المحلي، وتبويب المختبرات وشاشة الأرشيف بأرقام محسوبة يدوياً.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/archive/month_stats.dart';
import 'package:dental_clinic_flutter/features/labs/labs_logic.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:dental_clinic_flutter/features/records/tooth_chart.dart';
import 'package:dental_clinic_flutter/features/records/tooth_report_dialog.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_section.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_store.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;

  Map<String, Object?> config() => {
    'centerName': 'مركز الاختبار',
    'doctorPct': 50,
    'clinicRates': {
      'clinics': {
        'ع1': {
          'treatments': {'حشو': 40},
          'prosthetics': 30,
        },
      },
    },
    'clinics': ['ع1'],
    'services': ['حشو', 'تركيبات'],
    'payments': ['كاش', 'تحويل'],
    'labs': ['مخبر النور'],
    'labTypes': [
      {'name': 'زيركون', 'defaultPrice': 150},
    ],
  };

  setUp(() => tmp = Directory.systemTemp.createTempSync('m4c_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> seedAndBoot(
    WidgetTester tester, {
    void Function(ProviderContainer c)? seed,
    XrayPick? pick,
  }) async {
    final c = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', config());
    seed?.call(c);
    c.dispose();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
          if (pick != null) xrayFilePickProvider.overrideWithValue(pick),
        ],
        child: const DentalApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // م36 — الافتراضي صار «الرئيسية»: اختبارات هذا الملف تبدأ من السجلات.
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// أول Scrollable عمودي — يتفادى الالتقاط العرَضي لقابل تمرير حقلٍ نصي
  /// أفقي (editable) من مسار سابق أثناء إطار الانتقال الأخير.
  Finder vScrollable() => find
      .byWidgetPredicate(
        (w) =>
            w is Scrollable &&
            axisDirectionToAxis(w.axisDirection) == Axis.vertical,
      )
      .first;

  /// نقرة على سنّ في المخطط بإحداثياته المنطقية مُسقطةً على العنصر المرسوم.
  Future<void> tapTooth(WidgetTester tester, String q, int n) async {
    final rect = tester.getRect(find.byKey(const Key('tooth-chart')));
    final scale = rect.width / chartLogicalSize.width;
    final c = toothRect(q, n).center;
    await tester.tapAt(rect.topLeft + Offset(c.dx * scale, c.dy * scale));
    await tester.pump();
  }

  group('مخطط الأسنان — الإحداثيات وكشف النقر', () {
    test('مستطيلات الفكين بنفس معادلة renderSVG', () {
      // UR:1 — x144 w14 h34 ⇒ الفك العلوي ry = 107−34 = 73.
      expect(toothRect('UR', 1), const Rect.fromLTWH(144, 73, 14, 34));
      // LL:8 — x287 w17 h22 ⇒ الفك السفلي ry = 113.
      expect(toothRect('LL', 8), const Rect.fromLTWH(287, 113, 17, 22));
      expect(toothData.length, 32);
    });

    test('toothAt يصيب السن الصحيح ويعيد null خارج الأسنان', () {
      expect(toothAt(toothRect('UR', 8).center), 'UR:8');
      expect(toothAt(toothRect('LR', 3).center), 'LR:3');
      expect(toothAt(const Offset(160, 110)), isNull); // بين الفكين
      expect(toothAt(const Offset(1, 1)), isNull);
    });
  });

  group('توفيق «تحديد الأسنان» — reconcileTeethOnly حرفياً', () {
    test('اختيار جديد بلا معالجات ⇒ معالجة حاضنة «علاج» بكلفة 0', () {
      final out = reconcileTeethOnly([], {'LL:3', 'UR:1'});
      expect(out, hasLength(1));
      expect(out[0]['service'], 'علاج');
      expect(jsNumOr0(out[0]['cost']), 0);
      expect(teethKeysOf(out), {'LL:3', 'UR:1'});
    });

    test('إلغاء تحديد سن يسقطه من كل المعالجات ويبقي الباقي', () {
      final entries = [
        {
          'teeth': [
            {'q': 'UR', 'n': 1},
            {'q': 'UL', 'n': 2},
          ],
          'service': 'حشو',
          'cost': 50,
        },
        {
          'teeth': [
            {'q': 'UL', 'n': 2},
          ],
          'service': 'تنظيف',
          'cost': 20,
        },
      ];
      final out = reconcileTeethOnly(entries, {'UR:1'});
      expect(teethKeysOf(out), {'UR:1'});
      expect(out[1]['teeth'], isEmpty); // أُفرغت لا حُذفت — غير هدّام
      expect(out[0]['service'], 'حشو'); // الخدمات والكلف كما هي
    });

    test('الإضافة تذهب للمعالجة الأولى والمسح الكامل يثبت', () {
      final entries = [
        {
          'teeth': [
            {'q': 'UR', 'n': 1},
          ],
          'service': 'حشو',
          'cost': 50,
        },
      ];
      final out = reconcileTeethOnly(entries, {'UR:1', 'LR:5'});
      expect(activeTeeth(out[0]['teeth']), hasLength(2));

      final cleared = reconcileTeethOnly(entries, {});
      expect(teethKeysOf(cleared), isEmpty);
    });
  });

  group('حالات المختبر — labCases حرفياً', () {
    test(
      'غير الدين محصّل بتاريخه؛ الدين المفتوح «دين»؛ المسدد بتاريخ آخر دفعة',
      () {
        final pros = [
          {
            'id': 'p1',
            'labName': 'مخبر النور',
            'labValue': 200,
            'date': '2026-07-01',
            'clinic': 'ع1',
            'prosUnits': 2,
          },
          {
            'id': 'p2',
            'labName': 'مخبر النور',
            'labValue': 300,
            'date': '2026-07-02',
            'clinic': 'ع1',
            'isDebt': true,
          },
          {
            'id': 'p3',
            'labName': 'مخبر النور',
            'labValue': 100,
            'date': '2026-07-03',
            'clinic': 'ع1',
            'isDebt': true,
          },
        ];
        final debts = [
          {
            'id': 'd2',
            'prostheticId': 'p2',
            'status': 'partial',
            'remaining': 250,
            'labPaid': 50,
            'date': '2026-07-02',
          },
          {
            'id': 'd3',
            'prostheticId': 'p3',
            'status': 'paid',
            'remaining': 0,
            'labPaid': 100,
            'date': '2026-07-03',
          },
        ];
        final records = [
          {
            'id': 'r1',
            'isDebtPayment': true,
            'debtId': 'd3',
            'date': '2026-07-20',
          },
          {
            'id': 'r2',
            'isDebtPayment': true,
            'debtId': 'd3',
            'date': '2026-07-10',
          },
        ];

        final cases = labCases(
          'مخبر النور',
          prosthetics: pros,
          debts: debts,
          records: records,
        );
        expect(cases, hasLength(3));
        final byId = {for (final c in cases) c.row['id']: c};
        expect(byId['p1']!.financialStatus, 'محصّل');
        expect(byId['p1']!.statusDate, '2026-07-01');
        expect(byId['p2']!.financialStatus, 'دين');
        expect(byId['p2']!.statusDate, '2026-07-02');
        expect(byId['p3']!.financialStatus, 'محصّل');
        expect(byId['p3']!.statusDate, '2026-07-20'); // آخر دفعة لا تاريخ الدين

        // المجاميع: وحدات 2+1+1 (الافتراضي 1)، إجمالي 600، محصّل 300، ديون 300.
        expect(labTotalUnits(cases), 4);
        expect(labTotalAll(cases), 600);
        expect(labTotalCollected(cases), 300);
        expect(labTotalDebt(cases), 300);

        // labPaid ≥ labValue يجعلها محصّلة ولو بقي دين علاجي.
        final cases2 = labCases(
          'مخبر النور',
          prosthetics: [pros[1]],
          debts: [
            {...debts[0], 'labPaid': 300},
          ],
          records: const [],
        );
        expect(cases2.single.financialStatus, 'محصّل');
      },
    );

    test('الترتيب: العيادة أولاً ثم التاريخ صعوداً/نزولاً', () {
      final pros = [
        {'id': 'a', 'labName': 'م', 'clinic': 'ب', 'date': '2026-01-01'},
        {'id': 'b', 'labName': 'م', 'clinic': 'أ', 'date': '2026-03-01'},
        {'id': 'c', 'labName': 'م', 'clinic': 'أ', 'date': '2026-02-01'},
      ];
      final oldest = labCases(
        'م',
        prosthetics: pros,
        debts: const [],
        records: const [],
      );
      expect([for (final c in oldest) c.row['id']], ['c', 'b', 'a']);
      final newest = labCases(
        'م',
        prosthetics: pros,
        debts: const [],
        records: const [],
        sortOrder: 'newest',
      );
      expect([for (final c in newest) c.row['id']], ['b', 'c', 'a']);
    });
  });

  group('حسابات الأرشيف — month_stats حرفياً', () {
    final debts = [
      {'id': 'dr', 'type': 'regular'},
      {'id': 'dp', 'type': 'prosthetic'},
    ];
    final records = [
      // نقدية صافية
      {'id': '1', 'date': '2026-06-05', 'amount': 100, 'payment': 'كاش'},
      {'id': '2', 'date': '2026-06-06', 'amount': 200, 'payment': 'تحويل'},
      // مستثناة: سجل دين + سجل تركيبة + خارج الشهر
      {
        'id': '3',
        'date': '2026-06-07',
        'amount': 999,
        'payment': 'دين',
        'isDebt': true,
      },
      {
        'id': '4',
        'date': '2026-06-08',
        'amount': 555,
        'isPros': true,
        'payment': 'كاش',
      },
      {'id': '5', 'date': '2026-07-01', 'amount': 777, 'payment': 'كاش'},
      // دفعة دين عادية (تدخل الكاش) ودفعة دين تركيبة (تدخل التركيبات)
      {
        'id': '6',
        'date': '2026-06-09',
        'amount': 50,
        'isDebtPayment': true,
        'debtId': 'dr',
        'payment': 'كاش',
      },
      {
        'id': '7',
        'date': '2026-06-10',
        'amount': 250,
        'isDebtPayment': true,
        'debtId': 'dp',
        'payment': 'كاش',
        '_docAmount': 30,
      },
    ];
    final pros = [
      {
        'id': 'p1',
        'date': '2026-06-11',
        'total': 500,
        'payment': 'كاش',
        'doctorShare': 90,
      },
      {
        'id': 'p2',
        'date': '2026-06-12',
        'total': 400,
        'isDebt': true,
        'payment': 'دين',
        'doctorShare': 0,
      },
    ];

    test('monthData: الاستثناءات والكاش والتحويل والتركيبات والإجمالي', () {
      final d = monthData(
        '2026-06',
        records: records,
        prosthetics: pros,
        debts: debts,
      );
      expect(d.cash, 150); // 100 + دفعة عادية 50
      expect(d.xfer, 200);
      // تركيبات = غير الدين 500 + دفعة دين التركيبة 250
      expect(d.prosTotal, 750);
      // حصة الطبيب = 90 + _docAmount 30 (لا مبلغ الدفعة)
      expect(d.prosDoc, 120);
      expect(d.total, 150 + 200 + 750);
      expect(d.inMem, isTrue);
      expect(
        monthData(
          '2025-01',
          records: records,
          prosthetics: pros,
          debts: debts,
        ).inMem,
        isFalse,
      );
    });

    test('monthsOf تنازلياً وdetailRecords بمحتواه المضبوط', () {
      expect(monthsOf(records, pros), ['2026-07', '2026-06']);
      final det = detailRecords(
        '2026-06',
        records: records,
        prosthetics: pros,
        debts: debts,
      );
      // نقديتان + دفعتان + تركيبة غير الدين = 5 (لا سجل الدين ولا تركيبته)
      expect(det, hasLength(5));
      expect([for (final r in det) r['id']], isNot(contains('3')));
      expect([for (final r in det) r['id']], isNot(contains('p2')));
    });

    test('byNewestFirst: النشاط ثم التاريخ ثم المعرف تنازلياً', () {
      final a = {'id': 'a', 'date': '2026-06-01', '_activityAt': 5};
      final b = {'id': 'b', 'date': '2026-06-30'}; // تاريخ أحدث لكن بلا نشاط
      final sorted = sortByNewest([a, b]);
      // مفتاح b = زمن 2026-06-30 (ضخم) > 5 ⇒ b أولاً.
      expect(sorted.first['id'], 'b');
      // تعادل تام ⇒ المعرف الأكبر أولاً.
      final t1 = {'id': 'x', 'date': '2026-06-01'};
      final t2 = {'id': 'y', 'date': '2026-06-01'};
      expect(sortByNewest([t1, t2]).first['id'], 'y');
    });
  });

  group('مخزن الأشعة', () {
    test('الإدخال: ملف محلي + صف pending بمصغرة + مرايا الإعدادات', () {
      final c = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      final store = XrayStore(repos: repos, baseDir: tmp.path, uid: 'u1');

      final im = img.Image(width: 60, height: 40);
      img.fill(im, color: img.ColorRgb8(200, 30, 30));
      final bytes = img.encodePng(im);

      final r = store.ingest('هدى', 'scan.png', bytes);
      expect(r.key, startsWith('xray/u1/هدى/'));
      expect(r.thumbDataUrl, startsWith('data:image/jpeg;base64,'));

      final row = repos.xrays.getByPatient('هدى').single;
      expect(row['upload_status'], 'pending');
      expect(row['file_key'], r.key);
      expect(store.thumbnailBytes(r.key), isNotNull);
      expect(store.fullImageBytes(r.key), isNotNull);
      // م65 — ملفان محليان الآن: النسخة الكاملة **والمصغرة**. المصغرة صارت
      // تُكتب ملفاً عند الإدخال (لا في الصف وحده) كي يبقى العرض سليماً بعد
      // إخراجها من حمولة المزامنة حين يكون R2 مفعّلاً.
      final files = Directory(
        '${tmp.path}/xray_images',
      ).listSync().whereType<File>().map((f) => f.path).toList();
      expect(files.length, 2);
      expect(files.where((p) => p.endsWith('.thumb.jpg')).length, 1);
      expect(files.where((p) => !p.endsWith('.thumb.jpg')).length, 1);

      // مرايا الإعدادات
      var cfg = addXrayKeyToConfig(config(), 'هدى', r.key, 'scan.png');
      expect(xrayKeysFor(cfg, 'هدى'), [r.key]);
      expect(xrayMetaFor(cfg, r.key)['name'], 'scan'); // الامتداد مقصوص
      cfg = renameXrayInConfig(cfg, r.key, 'بانوراما');
      expect(xrayMetaFor(cfg, r.key)['name'], 'بانوراما');
      cfg = removeXrayKeyFromConfig(cfg, 'هدى', r.key);
      expect(xrayKeysFor(cfg, 'هدى'), isEmpty);
      expect(xrayMetaFor(cfg, r.key), isEmpty);

      // الحذف: شاهدة + زوال الملف
      store.deleteXray(r.key);
      expect(repos.xrays.getByPatient('هدى'), isEmpty);
      expect(
        Directory('${tmp.path}/xray_images').listSync().whereType<File>(),
        isEmpty,
      );
      final raw = c.read(localDbProvider).queryFirst(
        'SELECT _deleted, _dirty FROM xrays WHERE id = ?',
        [r.key],
      )!;
      expect(raw['_deleted'], 1); // شاهدة تتزامن لا حذف فيزيائي
      expect(raw['_dirty'], 1);
    });
  });

  group('الواجهة — تقرير الأسنان من شاشة الإضافة', () {
    // م133 — نموذج الإدخال rec-* لم يبق على تبويب الرئيسية (صار DailyIncomeScreen،
    // م121+)؛ انتقل لورقة سفلية تُفتح بالزر العائم Key('fab-add') (app_shell.dart).
    testWidgets('تحديد سن وحفظ السجل يخزّن report {entries, meta} في القاعدة', (
      tester,
    ) async {
      await seedAndBoot(tester);
      await tester.tap(find.byKey(const Key('fab-add')), warnIfMissed: false);
      await settle(tester);

      await tester.enterText(find.byKey(const Key('rec-name')), 'وليد');
      await tester.enterText(find.byKey(const Key('rec-amount')), '120');
      await tester.pump();

      await tester.scrollUntilVisible(
        find.byKey(const Key('rec-report-tgl')),
        200,
        scrollable: vScrollable(),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('rec-report-tgl')),
        warnIfMissed: false,
      );
      await settle(tester);

      // الحوار مفتوح (رقاقة التبديل تحمل النص نفسه الآن — حرفية الأصل).
      expect(find.text('تحديد الأسنان'), findsWidgets);
      await tapTooth(tester, 'UR', 1);
      await tapTooth(tester, 'LL', 3);
      expect(find.byKey(const Key('tr-sel-UR:1')), findsOneWidget);
      expect(find.byKey(const Key('tr-sel-LL:3')), findsOneWidget);
      // إلغاء LL:3 بنقرة ثانية على المخطط نفسه.
      await tapTooth(tester, 'LL', 3);
      expect(find.byKey(const Key('tr-sel-LL:3')), findsNothing);

      await tester.tap(
        find.byKey(const Key('tr-confirm')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('تحديد الأسنان (1)'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('rec-save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rec-save')), warnIfMissed: false);
      await settle(tester);

      final chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(chk.dispose);
      final rec = chk.read(reposProvider).records.getAll().single;
      final report = rec['report'] as Map;
      final entries = report['entries'] as List;
      expect(entries, hasLength(1));
      expect((entries[0] as Map)['service'], 'علاج');
      final teeth = (entries[0] as Map)['teeth'] as List;
      expect(teeth, hasLength(1));
      expect((teeth[0] as Map)['q'], 'UR');
      expect(jsNumOr0((teeth[0] as Map)['n']), 1);
      expect(report['meta'], isA<Map>());
    });
  });

  group('الواجهة — محرر أسنان الملف', () {
    testWidgets('الحفظ يكتب على السجل والدين المرتبط ويظهر سطر الأسنان', (
      tester,
    ) async {
      // م27 (تكافؤ Vue): أصل الدين يُخفى من الزيارات؛ فنختبر تحرير
      // الأسنان على سجلٍ ظاهرٍ له دين مرتبط عبر recordId — الحفظ يكتب
      // على السجل وينسخ على الدين المرتبط (مسار _writeTeethToDebt).
      await seedAndBoot(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          repos.records.upsertLocal({
            'id': 'r1',
            'name': 'سالم',
            'patient_name': 'سالم',
            'clinic': 'ع1',
            'amount': 300,
            'date': getCurrentDate(),
            'service': 'حشو',
            'payment': 'كاش',
          });
          repos.debts.upsertLocal({
            'id': 'd1',
            'name': 'سالم',
            'patient_name': 'سالم',
            'clinic': 'ع1',
            'recordId': 'r1',
            'totalAmount': 300,
            'paidAmount': 100,
            'remaining': 200,
            'status': 'partial',
            'date': getCurrentDate(),
          });
        },
      );
      await tester.enterText(find.byKey(const Key('patient-search')), 'سالم');
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('patient-card-سالم')),
        warnIfMissed: false,
      );
      await settle(tester);

      // تحديد الأسنان عبر قائمة ⋮ لبطاقة السجل (م11).
      await tester.ensureVisible(find.byKey(const Key('rr-kebab-0')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('rr-kebab-0')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('rr-teeth-0')),
        warnIfMissed: false,
      );
      await settle(tester);

      await tapTooth(tester, 'LR', 6);
      await tester.tap(
        find.byKey(const Key('tr-confirm')),
        warnIfMissed: false,
      );
      await settle(tester);

      // الصف الظاهر يعرض رقاقة السن «6» بعد الحفظ (م11: رقاقة رقم بالمر).
      expect(find.text('6'), findsWidgets);

      final chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(chk.dispose);
      final repos = chk.read(reposProvider);
      final original = repos.records
          .getAll()
          .where((r) => jsNumOr0(r['isDebtPayment']) != 1)
          .single;
      // ملف المريض يخزن التقرير مصفوفةً (كما في Vue) لا {entries}.
      final report = original['report'] as List;
      expect(
        ((report[0] as Map)['teeth'] as List).single,
        containsPair('q', 'LR'),
      );
      // النسخة القانونية على الدين المرتبط أيضاً.
      final debt = repos.debts.getAll().single;
      expect(debt['report'], isA<List>());
      expect(((debt['report'] as List)[0] as Map)['teeth'], hasLength(1));
      // تعديل إداري: الصف مقذّر للمزامنة.
      final raw = chk.read(localDbProvider).queryFirst(
        'SELECT _dirty FROM records WHERE id = ?',
        [original['id']],
      )!;
      expect(raw['_dirty'], 1);
    });
  });

  group('الواجهة — الأشعة في الملف', () {
    testWidgets('رفع وإعادة تسمية وحذف حتى القاعدة والإعدادات والملف المحلي', (
      tester,
    ) async {
      final im = img.Image(width: 80, height: 50);
      img.fill(im, color: img.ColorRgb8(20, 120, 220));
      final png = img.encodePng(im);

      await seedAndBoot(
        tester,
        seed: (c) {
          saveNewRecord(
            c.read(reposProvider),
            config(),
            SaveRecordInput(
              name: 'هدى',
              date: getCurrentDate(),
              amount: 100,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'كاش',
            ),
          );
        },
        pick: () async => [('scan.png', png)],
      );
      await tester.enterText(find.byKey(const Key('patient-search')), 'هدى');
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('patient-card-هدى')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('psec-xrays')),
        warnIfMissed: false,
      );
      await settle(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('xray-upload')),
        300,
        scrollable: vScrollable(),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('xray-upload')));
      // م39 — ورقة المصدر: نختار «من الملفات» (المنتقي المحقون).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('xr-src-files')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      await settle(tester);

      expect(find.byKey(const Key('xray-thumb-0')), findsOneWidget);
      var chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      final row = chk.read(reposProvider).xrays.getByPatient('هدى').single;
      expect(row['upload_status'], 'pending');
      final key = '${row['id']}';
      var cfg = Map<String, Object?>.from(
        chk.read(reposProvider).settings.get('app.config') as Map,
      );
      expect(xrayKeysFor(cfg, 'هدى'), [key]);
      expect(xrayMetaFor(cfg, key)['name'], 'scan');
      chk.dispose();

      // العرض التفصيلي: إعادة التسمية تصل config.xrayMeta.
      await tester.tap(
        find.byIcon(Icons.view_list_rounded),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('بانتظار الرفع'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('xray-rename-btn-0')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.enterText(find.byKey(const Key('xray-rename')), 'بانوراما');
      await tester.tap(
        find.byKey(const Key('xray-rename-save')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('بانوراما'), findsOneWidget);

      chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      cfg = Map<String, Object?>.from(
        chk.read(reposProvider).settings.get('app.config') as Map,
      );
      expect(xrayMetaFor(cfg, key)['name'], 'بانوراما');
      chk.dispose();

      // العارض: فتح من الشبكة ثم حذف بتأكيد.
      await tester.tap(
        find.byIcon(Icons.grid_view_rounded),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('xray-thumb-0')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.byKey(const Key('xv-rotate')), findsOneWidget);
      await tester.tap(find.byKey(const Key('xv-invert')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('xv-delete')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('xv-delete-confirm')));
      await settle(tester);
      // م142 — حذف الأشعة صار مؤجَّلاً خلف نافذة تراجع 3ث: العارض يُغلق ويظهر
      // شريط «تراجع» على الشبكة، ولا تُحذف الصورة (ولا صفّها ولا ملفها المحلي)
      // إلا بعد انقضاء المؤقت. نتحقق من بقائها لحظة التأجيل ثم نمرّر الزمن.
      expect(find.byKey(const Key('xray-thumb-0')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      expect(find.byKey(const Key('xray-thumb-0')), findsNothing);
      chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(chk.dispose);
      cfg = Map<String, Object?>.from(
        chk.read(reposProvider).settings.get('app.config') as Map,
      );
      expect(xrayKeysFor(cfg, 'هدى'), isEmpty);
      expect(chk.read(reposProvider).xrays.getByPatient('هدى'), isEmpty);
      expect(
        Directory('${tmp.path}/xray_images').listSync().whereType<File>(),
        isEmpty,
      );
    });
  });

  group('الواجهة — تبويب المختبرات', () {
    testWidgets('قائمة المختبرات ثم تفصيل بحالتين محصّلة ودين ومجاميع صحيحة', (
      tester,
    ) async {
      await seedAndBoot(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          final today = getCurrentDate();
          // تركيبة نقدية: مخبر 200، نوع زيركون ×2.
          saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'أ',
              date: today,
              amount: 500,
              clinic: 'ع1',
              service: 'تركيبات',
              payment: 'كاش',
              labValue: 200,
              labName: 'مخبر النور',
              prosType: 'زيركون',
              prosUnits: 2,
            ),
          );
          // تركيبة دين مفتوحة: مخبر 300 (labPaid 100 < 300).
          saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'ب',
              date: today,
              amount: 600,
              clinic: 'ع1',
              service: 'تركيبات',
              payment: 'كاش',
              labValue: 300,
              labName: 'مخبر النور',
              isDebt: true,
              firstPay: 100,
            ),
          );
        },
      );

      // م(هذه الدفعة) — المختبر صار داخل تبويب «إضافي»: نضغط التبويب ثم
      // بطاقة «المختبر» التي تفتح شاشة المختبرات المستقلة.
      await tester.tap(find.text('إضافي'), warnIfMissed: false);
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('extra-labs')),
        warnIfMissed: false,
      );
      await settle(tester);
      // م161 — بطاقة المختبر الصفّية: الاسم وعدد حالات الشهر.
      expect(find.byKey(const Key('lab-مخبر النور')), findsOneWidget);
      expect(find.textContaining('2 حالة'), findsWidgets);

      await tester.tap(
        find.byKey(const Key('lab-مخبر النور')),
        warnIfMissed: false,
      );
      await settle(tester);
      // م161 — شاشة المختبر المستقلة: جدول بأعمدته وصف الإجمالي.
      expect(find.text('نوع التركيب'), findsOneWidget);
      expect(find.text('زيركون'), findsWidgets);
      expect(find.byKey(const Key('lab-detail-total')), findsOneWidget);
      // إجمالي القيم = 200 + 300 = 500 (القيمة = قيمة المختبر).
      expect(find.textContaining('500'), findsWidgets);

      // الرجوع للقائمة: زر شريط تطبيق شاشة المختبر المستقلة (الأعلى).
      final back = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackButton),
      );
      await tester.tap(back.last, warnIfMissed: false);
      await settle(tester);
      expect(find.byKey(const Key('lab-مخبر النور')), findsOneWidget);
    });
  });

  group('الواجهة — الأرشيف', () {
    testWidgets('أشهر ببطاقات مجاميع صحيحة وتفصيل شهر بسجلاته', (tester) async {
      await seedAndBoot(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          // يونيو: نقدية 100 + دين بدفعة أولى 100 + تركيبة 500.
          saveNewRecord(
            repos,
            config(),
            const SaveRecordInput(
              name: 'أ',
              date: '2026-06-10',
              amount: 100,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'كاش',
            ),
          );
          saveNewRecord(
            repos,
            config(),
            const SaveRecordInput(
              name: 'ب',
              date: '2026-06-12',
              amount: 250,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'كاش',
              isDebt: true,
              firstPay: 100,
            ),
          );
          saveNewRecord(
            repos,
            config(),
            const SaveRecordInput(
              name: 'ج',
              date: '2026-06-15',
              amount: 500,
              clinic: 'ع1',
              service: 'تركيبات',
              payment: 'كاش',
              labValue: 200,
            ),
          );
          // يوليو: نقدية 300.
          saveNewRecord(
            repos,
            config(),
            const SaveRecordInput(
              name: 'د',
              date: '2026-07-05',
              amount: 300,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'كاش',
            ),
          );
        },
      );

      await tester.tap(find.text('المالية'), warnIfMissed: false);
      await settle(tester);
      // مدخل الأرشيف انتقل لموضعه الأصلي: قسم الأرباح.
      await tester.tap(
        find.byKey(const Key('fin-seg-profits')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('fin-archive')),
        300,
        scrollable: vScrollable(),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('fin-archive')),
        warnIfMissed: false,
      );
      await settle(tester);

      // الشهران موجودان والأحدث أولاً.
      expect(find.byKey(const Key('arch-month-2026-07')), findsOneWidget);
      expect(find.byKey(const Key('arch-month-2026-06')), findsOneWidget);
      final julY = tester
          .getTopLeft(find.byKey(const Key('arch-month-2026-07')))
          .dy;
      final junY = tester
          .getTopLeft(find.byKey(const Key('arch-month-2026-06')))
          .dy;
      expect(julY, lessThan(junY));

      // يونيو: كاش 100+100=200، تركيبات 500، الإجمالي 700.
      await tester.tap(
        find.byKey(const Key('arch-month-2026-06')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('700.00'), findsWidgets);
      expect(find.text('200.00'), findsWidgets);
      // سجلات الشهر: النقدية والدفعة والتركيبة (لا سجل الدين نفسه).
      expect(find.text('أ'), findsOneWidget);
      expect(find.textContaining('دفعة أولى (دين)'), findsOneWidget);
      expect(find.text('ج'), findsOneWidget);
      expect(find.textContaining('| حشو').first, findsOneWidget);

      await tester.tap(find.byKey(const Key('arch-back')), warnIfMissed: false);
      await settle(tester);
      expect(find.byKey(const Key('arch-month-2026-07')), findsOneWidget);
    });
  });

  group('الواجهة — إعدادات المختبرات', () {
    testWidgets('إضافة نوع تركيبة بسعر يصل config.labTypes ويملأ قيمة المخبر', (
      tester,
    ) async {
      await seedAndBoot(tester);
      await tester.tap(find.byTooltip('الإعدادات'));
      await settle(tester);

      // قسم «إعدادات المختبرات» ثم صف النوع الجديد السطري.
      // م92 — scrollUntilVisible لا ensureVisible: الصف خارج نطاق البناء
      // الكسول في قائمة أطول، وensureVisible لا يبني العناصر البعيدة.
      await tester.scrollUntilVisible(
        find.byKey(const Key('group-labs')),
        250,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('group-labs')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('add-labtype')),
        250,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('new-labtype-name')),
        'بورسلين',
      );
      await tester.enterText(find.byKey(const Key('new-labtype-price')), '80');
      await tester.ensureVisible(find.byKey(const Key('add-labtype')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('add-labtype')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('save-labtypes')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('save-labtypes')),
        warnIfMissed: false,
      );
      await settle(tester);

      final chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(chk.dispose);
      final cfg = Map<String, Object?>.from(
        chk.read(reposProvider).settings.get('app.config') as Map,
      );
      // م162 — الحفظ صار لقائمة المختبر المحدد (labTypesByLab):
      // المحرر حُمِّل بالتراجع من القائمة العامة (زيركون) ثم أُضيف
      // بورسلين ⇒ قائمة «مخبر النور» الخاصة بها النوعان.
      final byLab = cfg['labTypesByLab'] as Map;
      final types = byLab['مخبر النور'] as List;
      expect(types, hasLength(2));
      expect(
        types.any(
          (t) =>
              (t as Map)['name'] == 'بورسلين' &&
              jsNumOr0(t['defaultPrice']) == 80,
        ),
        isTrue,
      );

      // العودة وفتح نموذج الإدخال: اختيار النوع يملأ قيمة المخبر (وحدات × سعر).
      // م92 — رجوعان: صفحة القسم ثم شاشة الإعدادات.
      // م133 — نموذج الإدخال rec-* لم يبق على تبويب الرئيسية (صار DailyIncomeScreen،
      // م121+)؛ انتقل لورقة سفلية تُفتح بالزر العائم Key('fab-add') (app_shell.dart).
      await tester.tap(
        find.byKey(const Key('settings-section-back')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.byType(BackButton).first, warnIfMissed: false);
      await settle(tester);
      // م172 — «+» صار في «الرئيسية» فقط: نعود إليها أولاً (مع استقرار
      // حركة تكبير الزر العائم قبل نقره).
      await tester.tap(find.text('الرئيسية'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fab-add')), warnIfMissed: false);
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('rec-service')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('تركيبات').last, warnIfMissed: false);
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('rec-prostype')),
        200,
        scrollable: vScrollable(),
      );
      await tester.pump();
      // م162 — الأنواع صارت لكل مختبر: نختار المختبر أولاً فتظهر أنواعه.
      await tester.tap(
        find.byKey(const Key('rec-labname')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('مخبر النور').last, warnIfMissed: false);
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('rec-prostype')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('بورسلين').last, warnIfMissed: false);
      await settle(tester);
      final labField = tester.widget<TextField>(
        find.byKey(const Key('rec-lab')),
      );
      expect(labField.controller!.text, '80'); // 1 × 80
      // وحدتان ⇒ 160.
      await tester.enterText(find.byKey(const Key('rec-prosunits')), '2');
      await settle(tester);
      expect(labField.controller!.text, '160');
    });
  });
}
