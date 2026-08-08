/// اختبارات م96 — عزل المعلومات الطبية الكامل (منطق نقيّ بلا قاعدة):
/// مفتاح الهوية (اسم|عيادة|هاتف)، القراءة بلا تسريب عارٍ بالاسم، عزل
/// توأمَي الاسم داخل العيادة، هجرة المفاتيح، وإعادة التسمية/الحذف
/// الشاملان لمفاتيح الهاتف.
library;

import 'package:dental_clinic_flutter/features/patients/clinic_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('مفتاح الهوية: بلا هاتف = اسم|عيادة، وبهاتف تُلحق أرقامه فقط', () {
    expect(medicalScopedKey('أحمد', 'ع1', ''), 'أحمد|ع1');
    expect(medicalScopedKey('أحمد', 'ع1', '091-234 567'), 'أحمد|ع1|091234567');
    expect(medicalScopedKey('أحمد', '', '0912'), 'أحمد|0912');
    expect(phoneDigits('+218 91/23'), '2189123');
  });

  test('القراءة: مفتاح الهاتف أولاً ثم مفتاح العيادة — ولا قراءة عارية', () {
    final map = {
      'أحمد': {'notes': 'قديم عارٍ'},
      'أحمد|ع1': {'notes': 'عيادة'},
      'أحمد|ع1|0911': {'notes': 'هوية'},
    };
    // مفتاح الهاتف يفوز.
    expect(
        (medicalScopedRead(map, 'أحمد', 'ع1', '0911') as Map)['notes'],
        'هوية');
    // بلا هاتف سياق: هاتف الصف يقود للمفتاح الهوياتي.
    expect(
        (medicalScopedRead(map, 'أحمد', 'ع1', '', rowPhone: '0911')
            as Map)['notes'],
        'هوية');
    // بلا أي هاتف: مفتاح العيادة.
    expect((medicalScopedRead(map, 'أحمد', 'ع1', '') as Map)['notes'],
        'عيادة');
    // عيادة أخرى بلا مدخل: لا شيء — **لا** سقوط للمدخل العاري.
    expect(medicalScopedRead(map, 'أحمد', 'ع2', ''), isNull);
    expect(medicalScopedRead(map, 'أحمد', 'ع2', '0955'), isNull);
  });

  test('عزل توأمَي الاسم داخل العيادة الواحدة بهاتفين مختلفين', () {
    var map = <String, Object?>{};
    // التوأم الأول يحفظ بهاتفه.
    map = medicalScopedWrite(map, 'أحمد', 'ع1', '0911', {'age': 40});
    // التوأم الثاني (هاتف مختلف): لا يرى بيانات الأول.
    expect(
        medicalScopedRead(map, 'أحمد', 'ع1', '0922', rowPhone: '0911'),
        isNull);
    // ويحفظ بياناته منفصلة.
    map = medicalScopedWrite(map, 'أحمد', 'ع1', '0922', {'age': 25});
    expect((medicalScopedRead(map, 'أحمد', 'ع1', '0911') as Map)['age'], 40);
    expect((medicalScopedRead(map, 'أحمد', 'ع1', '0922') as Map)['age'], 25);
    expect(map.length, 2);
  });

  test('توافق: بيانات اسم|عيادة تبقى مرئية لصاحبها (هاتف الصف يطابق)', () {
    final map = {
      'أحمد|ع1': {'notes': 'قبل الترقية'},
    };
    // نفس المريض (هاتف السياق = هاتف الصف): يرى بياناته القديمة.
    expect(
        (medicalScopedRead(map, 'أحمد', 'ع1', '0911', rowPhone: '0911')
            as Map)['notes'],
        'قبل الترقية');
    // توأم جديد بهاتف مختلف عن هاتف الصف: معزول.
    expect(medicalScopedRead(map, 'أحمد', 'ع1', '0922', rowPhone: '0911'),
        isNull);
  });

  test('الكتابة تذهب لمفتاح الهوية (هاتف السياق وإلا هاتف الصف)', () {
    var map = medicalScopedWrite({}, 'أحمد', 'ع1', '', {'a': 1},
        rowPhone: '0911');
    expect(map.containsKey('أحمد|ع1|0911'), isTrue);
    map = medicalScopedWrite(map, 'أحمد', 'ع1', '', {'b': 2});
    expect(map.containsKey('أحمد|ع1'), isTrue); // بلا أي هاتف
  });

  test('الهجرة 1: العاري بالاسم يُنقل لعيادة أحدث نشاط (نقلاً لا نسخاً)', () {
    final migrated = migrateMedicalKeys(
      {
        'أحمد': {'notes': 'قديم'},
        'خامل': {'notes': 'بلا نشاط'},
      },
      latestClinicOf: (nm) => nm == 'أحمد' ? 'ع2' : null,
      rowPhoneOf: (_) => '',
    )!;
    expect(migrated.containsKey('أحمد'), isFalse);
    expect((migrated['أحمد|ع2'] as Map)['notes'], 'قديم');
    // بلا نشاط: يبقى خاملاً كما هو (غير مقروء بعد اليوم).
    expect(migrated.containsKey('خامل'), isTrue);
  });

  test('الهجرة 2: اسم|عيادة يرتقي بهاتف الصف، والهدف الموجود يفوز', () {
    final migrated = migrateMedicalKeys(
      {
        'أحمد|ع1': {'src': 'قديم'},
        'سالم|ع1': {'src': 'بلا هاتف'},
        'وليد|ع1': {'src': 'قديم'},
        'وليد|ع1|0955': {'src': 'أحدث'},
      },
      latestClinicOf: (_) => null,
      rowPhoneOf: (nm) => switch (nm) {
        'أحمد' => '0911',
        'وليد' => '0955',
        _ => '',
      },
    )!;
    expect((migrated['أحمد|ع1|0911'] as Map)['src'], 'قديم');
    expect(migrated.containsKey('أحمد|ع1'), isFalse);
    // بلا هاتف صف: يبقى على مفتاح العيادة.
    expect(migrated.containsKey('سالم|ع1'), isTrue);
    // الهدف موجود مسبقاً (كُتب بعد العزل): يفوز ويُسقط المصدر.
    expect((migrated['وليد|ع1|0955'] as Map)['src'], 'أحدث');
    expect(migrated.containsKey('وليد|ع1'), isFalse);
  });

  test('م97: هجرة كتلة خطة العلاج بالعيادة فقط (بلا ترقية هاتف للكتلة)', () {
    final migrated = migrateMedicalKeys(
      {
        'أحمد': [
          {'id': 's1', 'desc': 'حشو', 'done': false},
        ],
        'وليد|ع1': [
          {'id': 's2', 'desc': 'تنظيف', 'done': true},
        ],
      },
      latestClinicOf: (nm) => nm == 'أحمد' ? 'ع2' : null,
      rowPhoneOf: (_) => '0911', // متوفر — لكن الكتلة لا تُرقّى هاتفياً
      upgradePhones: false,
    )!;
    // العاري انتقل لمفتاح العيادة (بلا لاحقة هاتف).
    expect(migrated.containsKey('أحمد|ع2'), isTrue);
    expect(migrated.containsKey('أحمد'), isFalse);
    expect(migrated.containsKey('أحمد|ع2|0911'), isFalse);
    // «اسم|عيادة» يبقى كما هو (ترقية الهاتف لصفوف المخزن عند القراءة).
    expect(migrated.containsKey('وليد|ع1'), isTrue);
  });

  test('الهجرة عديمة الأثر تعيد null (لا كتابة عبثية عند كل إقلاع)', () {
    expect(
        migrateMedicalKeys(
          {
            'أحمد|ع1|0911': {'a': 1},
            'خامل': {'notes': 'بلا نشاط'},
          },
          latestClinicOf: (_) => null,
          rowPhoneOf: (_) => '',
        ),
        isNull);
  });

  test('إعادة التسمية تشمل مفاتيح الهاتف بلاحقتها', () {
    final out = clinicScopedRename(
      {
        'أحمد|ع1': {'a': 1},
        'أحمد|ع1|0911': {'b': 2},
        'أحمد|ع2': {'c': 3},
      },
      'أحمد',
      'أحمد علي',
      'ع1',
      othersStillUseLegacy: false,
    );
    expect(out.containsKey('أحمد علي|ع1'), isTrue);
    expect(out.containsKey('أحمد علي|ع1|0911'), isTrue);
    expect(out.containsKey('أحمد|ع1'), isFalse);
    expect(out.containsKey('أحمد|ع1|0911'), isFalse);
    expect(out.containsKey('أحمد|ع2'), isTrue); // عيادة أخرى لا تُمس
  });

  test('الحذف يشمل مفاتيح الهاتف داخل العيادة', () {
    final out = clinicScopedRemove(
      {
        'أحمد|ع1': {'a': 1},
        'أحمد|ع1|0911': {'b': 2},
        'أحمد|ع2|0911': {'c': 3},
        'أحمد': {'legacy': true},
      },
      'أحمد',
      'ع1',
      removeLegacy: true,
    );
    expect(out.containsKey('أحمد|ع1'), isFalse);
    expect(out.containsKey('أحمد|ع1|0911'), isFalse);
    expect(out.containsKey('أحمد|ع2|0911'), isTrue);
    expect(out.containsKey('أحمد'), isFalse);
  });
}
