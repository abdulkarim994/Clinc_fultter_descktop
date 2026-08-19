/// اختبارات م75 — أرشفة المرضى: الإخفاء/الإظهار، التحديد المتعدد،
/// التزامن بين جهازين، العودة التلقائية عند معالجة جديدة، وسلامة المال.
///
/// المبدأ: الأرشفة إخفاء لا حذف — كل البيانات باقية، والعلم يتزامن كأي
/// تعديل عبر الإعدادات (نفس نمط خطط العلاج).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:dental_clinic_flutter/features/patients/archive_store.dart';
import 'package:dental_clinic_flutter/features/patients/patients_logic.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

class Device {
  Device(String name, FakeSyncServer server)
      : tmp = Directory.systemTemp.createTempSync('m75_${name}_') {
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repos = Repositories(db);
    engine =
        SyncEngine(SyncContext(db: db, repos: repos, transport: server));
    archive = PatientArchiveStore(repos.settings);
  }

  final Directory tmp;
  late final LocalDb db;
  late final Repositories repos;
  late final SyncEngine engine;
  late final PatientArchiveStore archive;

  Future<void> sync() => engine.runCycle('test').then((_) {});
  void dispose() {
    db.close();
    tmp.deleteSync(recursive: true);
  }
}

/// بناء صفوف القائمة كما يفعل التبويب: تجميع ثم وسم ثم ترشيح.
List<ClinicPatientRow> visibleList(
  Repositories repos,
  PatientArchiveStore archive, {
  required String clinic,
  bool showArchived = false,
  String query = '',
}) {
  final recs = repos.records.getAll();
  final map = buildPatientMap(recs, const [], repos.debts.getAll());
  final rows = clinicPatients(
    clinic,
    patientMap: map,
    records: recs,
    prosthetics: const [],
    debts: repos.debts.getAll(),
    archivedKeys: archive.archivedKeys(),
  );
  return filterClinicPatients(
    rows,
    query: query,
    phoneMode: false,
    sortBy: 'name',
    showArchived: showArchived,
  );
}

SaveRecordInput visit(String name, String clinic,
        {String phone = '0910000000'}) =>
    SaveRecordInput(
      name: name,
      phone: phone,
      phone2: '',
      clinic: clinic,
      service: 'حشو',
      amount: 100,
      date: '2026-07-30',
      payment: 'كاش',
      notes: '',
      isDebt: false,
    );

void main() {
  late Device d;
  setUp(() => d = Device('a', FakeSyncServer()));
  tearDown(() => d.dispose());

  // مريضان بسجلات فعلية كي يظهرا في القائمة.
  void seedTwo() {
    saveNewRecord(d.repos, const {}, visit('نوري سالم', 'الرئيسية'));
    saveNewRecord(d.repos, const {}, visit('هدى علي', 'الرئيسية'));
  }

  group('م75 — الإخفاء والإظهار', () {
    test('الأرشفة تُخفي من القائمة، والإظهار يعيد بشارة', () {
      seedTwo();
      expect(visibleList(d.repos, d.archive, clinic: 'الرئيسية').length, 2);

      d.archive.archive('نوري سالم', 'الرئيسية');
      final hidden = visibleList(d.repos, d.archive, clinic: 'الرئيسية');
      expect(hidden.map((r) => r.agg.name), ['هدى علي'],
          reason: 'المؤرشف يختفي افتراضياً');

      final shown = visibleList(d.repos, d.archive,
          clinic: 'الرئيسية', showArchived: true);
      expect(shown.length, 2);
      final nuri = shown.firstWhere((r) => r.agg.name == 'نوري سالم');
      expect(nuri.archived, isTrue, reason: 'يظهر ببشارة مؤرشف');
    });

    test('المؤرشف يختفي من البحث أيضاً لا القائمة فقط', () {
      seedTwo();
      d.archive.archive('نوري سالم', 'الرئيسية');
      final hit = visibleList(d.repos, d.archive,
          clinic: 'الرئيسية', query: 'نوري');
      expect(hit, isEmpty, reason: 'البحث لا يتسلّل حوله');
      final hitShown = visibleList(d.repos, d.archive,
          clinic: 'الرئيسية', query: 'نوري', showArchived: true);
      expect(hitShown.single.agg.name, 'نوري سالم');
    });

    test('إلغاء الأرشفة يعيده للقائمة', () {
      seedTwo();
      d.archive.archive('نوري سالم', 'الرئيسية');
      d.archive.unarchive('نوري سالم', 'الرئيسية');
      expect(visibleList(d.repos, d.archive, clinic: 'الرئيسية').length, 2);
      expect(d.archive.isArchived('نوري سالم', 'الرئيسية'), isFalse);
    });
  });

  group('م75 — التحديد المتعدد', () {
    test('أرشفة دفعة ثم إلغاء دفعة', () {
      seedTwo();
      saveNewRecord(d.repos, const {}, visit('سالم خالد', 'الرئيسية'));
      d.archive.archiveAll([
        (name: 'نوري سالم', clinic: 'الرئيسية', phone: ''),
        (name: 'هدى علي', clinic: 'الرئيسية', phone: ''),
      ]);
      expect(visibleList(d.repos, d.archive, clinic: 'الرئيسية')
          .map((r) => r.agg.name), ['سالم خالد']);

      d.archive.unarchiveAll([
        (name: 'نوري سالم', clinic: 'الرئيسية', phone: ''),
        (name: 'هدى علي', clinic: 'الرئيسية', phone: ''),
      ]);
      expect(visibleList(d.repos, d.archive, clinic: 'الرئيسية').length, 3);
    });
  });

  group('م75 — العودة التلقائية', () {
    test('معالجة جديدة تُعيد المؤرشف نشطاً', () {
      seedTwo();
      d.archive.archive('نوري سالم', 'الرئيسية');
      expect(d.archive.isArchived('نوري سالم', 'الرئيسية'), isTrue);

      // زيارة جديدة لنفس المريض ⇒ يعود تلقائياً (قرار المالك)
      saveNewRecord(d.repos, const {}, visit('نوري سالم', 'الرئيسية'));
      expect(d.archive.isArchived('نوري سالم', 'الرئيسية'), isFalse);
      expect(visibleList(d.repos, d.archive, clinic: 'الرئيسية')
          .any((r) => r.agg.name == 'نوري سالم'), isTrue);
    });

    test('حفظ سجل لمريض غير مؤرشف لا يكتب شاهد قبر بلا داعٍ', () {
      seedTwo();
      saveNewRecord(d.repos, const {}, visit('نوري سالم', 'الرئيسية'));
      // لا مفاتيح أرشفة إطلاقاً (لا شواهد زائدة)
      expect(d.archive.archivedKeys(), isEmpty);
    });
  });

  group('م75 — العزل بالعيادة والمال', () {
    test('نفس الاسم في عيادتين: أرشفة إحداهما لا تمسّ الأخرى', () {
      saveNewRecord(d.repos, const {}, visit('نوري سالم', 'الرئيسية'));
      saveNewRecord(d.repos, const {}, visit('نوري سالم', 'الفرع'));
      d.archive.archive('نوري سالم', 'الرئيسية');
      expect(d.archive.isArchived('نوري سالم', 'الرئيسية'), isTrue);
      expect(d.archive.isArchived('نوري سالم', 'الفرع'), isFalse);
    });

    test('الأرشفة لا تمسّ السجلات ولا الديون', () {
      saveNewRecord(d.repos, const {},
          SaveRecordInput(
            name: 'نوري سالم', phone: '0910000000', phone2: '',
            clinic: 'الرئيسية', service: 'حشو', amount: 300,
            date: '2026-07-30', payment: 'دين', notes: '', isDebt: true,
            firstPay: 100,
          ));
      final recsBefore = d.repos.records.getAll().length;
      final debtsBefore = d.repos.debts.getAll().length;
      d.archive.archive('نوري سالم', 'الرئيسية');
      expect(d.repos.records.getAll().length, recsBefore);
      expect(d.repos.debts.getAll().length, debtsBefore);
      expect(d.repos.debts.getAll().first['name'], 'نوري سالم');
    });
  });

  group('م75 — التزامن بين جهازين', () {
    test('الأرشفة من جهاز تصل الآخر عبر المزامنة', () async {
      final server = FakeSyncServer();
      final a = Device('sync_a', server);
      final b = Device('sync_b', server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      saveNewRecord(a.repos, const {}, visit('نوري سالم', 'الرئيسية'));
      await a.sync();
      await b.sync();
      expect(b.repos.records.getAll().any((r) => r['name'] == 'نوري سالم'),
          isTrue);

      a.archive.archive('نوري سالم', 'الرئيسية');
      await a.sync();
      await b.sync();
      expect(b.archive.isArchived('نوري سالم', 'الرئيسية'), isTrue,
          reason: 'علم الأرشفة يتزامن كأي إعداد');

      // وإلغاء الأرشفة يتزامن أيضاً (شاهد قبر)
      a.archive.unarchive('نوري سالم', 'الرئيسية');
      await a.sync();
      await b.sync();
      expect(b.archive.isArchived('نوري سالم', 'الرئيسية'), isFalse);
    });
  });
}
