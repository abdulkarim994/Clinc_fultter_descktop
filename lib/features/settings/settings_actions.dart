/// أفعال الإعدادات — نقل حرفي لوظائف SettingsModal/app.store:
///
///  • **renameClinic**: إعادة تسمية متعاقبة — كل سجل/تركيبة/دين/موعد بحقل
///    العيادة القديم يُعاد ختمه بالاسم الجديد (dirty+HLC عبر upsertLocal)
///    وتُحدَّث قائمة config.clinics (كما في الأصل: صفوف البيانات والقائمة
///    فقط — مفاتيح clinicRates لا تُمس، مطابقةً للأصل).
///  • **exportExcel**: ملف .xlsx حقيقي بثلاث أوراق (السجلات/التركيبات/
///    الديون) بنفس أعمدة الأصل — يُبنى يدوياً (zip من XML بخلايا نصية
///    inlineStr) لتعارض حزمة excel مع pdf.
///  • **exportJson/importJson**: نسخة احتياطية بنفس مفاتيح الأصل
///    (records/prosthetics/debts/appointments/config/exportDate)
///    والاستعادة تستبدل البيانات عبر upsertLocal (تتقذر فتتزامن).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/utils/js_compat.dart';
import '../../data/repositories/repositories.dart';

typedef JMap = Map<String, Object?>;

/// renameClinic — يعيد عدد الصفوف المعاد ختمها.
int renameClinicCascade(
    Repositories repos, String oldName, String newName) {
  if (oldName.isEmpty || newName.isEmpty || oldName == newName) return 0;
  var touched = 0;
  void sweep(List<JMap> rows, void Function(JMap) save) {
    for (final r in rows) {
      if (r['clinic'] == oldName) {
        save({...r, 'clinic': newName});
        touched++;
      }
    }
  }

  sweep(repos.records.getAll(), repos.records.upsertLocal);
  sweep(repos.prosthetics.getAll(), repos.prosthetics.upsertLocal);
  sweep(repos.debts.getAll(), repos.debts.upsertLocal);
  sweep(repos.appointments.getAll(), repos.appointments.upsertLocal);

  final v = repos.settings.get('app.config');
  final cfg = v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
  final clinics = [
    for (final c in (cfg['clinics'] as List? ?? const [])) '$c',
  ];
  final idx = clinics.indexOf(oldName);
  if (idx != -1) {
    clinics[idx] = newName;
    repos.settings.set('app.config', {...cfg, 'clinics': clinics});
  }
  return touched;
}

// ── Excel (xlsx يدوي: zip من XML بسيطة بخلايا inlineStr) ────────────────────

String _esc(Object? s) => '${s ?? ''}'
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _sheetXml(List<List<Object?>> rows) {
  final b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>');
  for (var r = 0; r < rows.length; r++) {
    b.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v is num) {
        b.write('<c r="${_cellRef(c, r)}"><v>$v</v></c>');
      } else {
        b.write('<c r="${_cellRef(c, r)}" t="inlineStr">'
            '<is><t xml:space="preserve">${_esc(v)}</t></is></c>');
      }
    }
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

String _cellRef(int col, int row) {
  var c = col;
  var s = '';
  while (true) {
    s = String.fromCharCode(65 + (c % 26)) + s;
    if (c < 26) break;
    c = c ~/ 26 - 1;
  }
  return '$s${row + 1}';
}

/// يبني xlsx من أوراق (اسم ← صفوف).
Uint8List buildXlsx(Map<String, List<List<Object?>>> sheets) {
  final names = sheets.keys.toList();
  final archive = Archive();

  void add(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '${[for (var i = 0; i < names.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
      '</Types>');
  add('_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>');
  add('xl/workbook.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets>'
      '${[for (var i = 0; i < names.length; i++) '<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
      '</sheets></workbook>');
  add('xl/_rels/workbook.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${[for (var i = 0; i < names.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
      '</Relationships>');
  for (var i = 0; i < names.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[names[i]]!));
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// exportExcel — نفس أوراق الأصل وأعمدته.
Uint8List buildBackupXlsx(Repositories repos) {
  final records = repos.records.getAll();
  final pros = repos.prosthetics.getAll();
  final debts = repos.debts.getAll();
  return buildXlsx({
    'السجلات': [
      ['الاسم', 'التاريخ', 'القيمة', 'العيادة', 'الخدمة', 'الدفع'],
      for (final r in records)
        if (!jsTruthy(r['isPros']))
          [
            '${r['name'] ?? ''}', '${r['date'] ?? ''}',
            jsNumOr0(r['amount']),
            '${r['clinic'] ?? ''}', '${r['service'] ?? ''}',
            '${r['payment'] ?? ''}',
          ],
    ],
    'التركيبات': [
      ['الاسم', 'التاريخ', 'الإجمالي', 'المعمل', 'نسبة الطبيب',
        'نسبة العيادة', 'العيادة'],
      for (final p in pros)
        [
          '${p['name'] ?? ''}', '${p['date'] ?? ''}',
          jsNumOr0(p['total']), jsNumOr0(p['labValue']),
          jsNumOr0(p['doctorShare']), jsNumOr0(p['clinicShare']),
          '${p['clinic'] ?? ''}',
        ],
    ],
    'الديون': [
      ['الاسم', 'التاريخ', 'الإجمالي', 'المدفوع', 'المتبقي', 'الهاتف',
        'الحالة'],
      for (final d in debts)
        [
          '${d['name'] ?? ''}', '${d['date'] ?? ''}',
          jsNumOr0(jsOr(d['totalAmount'], d['total'])),
          jsNumOr0(d['paidAmount']), jsNumOr0(d['remaining']),
          '${d['phone'] ?? ''}', '${d['status'] ?? ''}',
        ],
    ],
  });
}

// ── JSON (نفس مفاتيح الأصل) ─────────────────────────────────────────────────

String buildBackupJson(Repositories repos) {
  final v = repos.settings.get('app.config');
  return const JsonEncoder.withIndent('  ').convert({
    'records': repos.records.getAll(),
    'prosthetics': repos.prosthetics.getAll(),
    'debts': repos.debts.getAll(),
    'appointments': repos.appointments.getAll(),
    'config': v is Map ? v : {},
    'exportDate': DateTime.now().toIso8601String(),
  });
}

/// importJSON — الاستعادة تكتب كل صف عبر upsertLocal (يتقذر فيتزامن)
/// وتستبدل الإعدادات. يعيد عدد الصفوف المستوردة.
int restoreBackupJson(Repositories repos, String jsonText) {
  final data = jsonDecode(jsonText);
  if (data is! Map) throw const FormatException('ملف غير صالح');
  var count = 0;
  void importList(Object? list, void Function(JMap) save) {
    if (list is! List) return;
    for (final r in list) {
      if (r is Map && jsTruthy(r['id'])) {
        save(Map<String, Object?>.from(r));
        count++;
      }
    }
  }

  importList(data['records'], repos.records.upsertLocal);
  importList(data['prosthetics'], repos.prosthetics.upsertLocal);
  importList(data['debts'], repos.debts.upsertLocal);
  importList(data['appointments'], repos.appointments.upsertLocal);
  if (data['config'] is Map) {
    repos.settings
        .set('app.config', Map<String, Object?>.from(data['config'] as Map));
  }
  return count;
}
