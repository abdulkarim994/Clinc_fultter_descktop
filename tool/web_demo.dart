/// نقطة دخول العرض التفاعلي — تُترجم بـ dart compile js وتكشف نواة الكود
/// المنقول (محرك الدمج، إعادة الاشتقاق، التطبيع العربي، ساعة HLC) للمتصفح
/// عبر دالة واحدة: window.dartDemo(op, argsJson) -> resultJson.
///
/// هذا هو **نفس كود الإنتاج المنقول** — لا إعادة تنفيذ ولا محاكاة.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dental_clinic_flutter/core/utils/ar_normalize.dart';
import 'package:dental_clinic_flutter/data/sync/hlc.dart';
import 'package:dental_clinic_flutter/data/sync/merge/config_merge.dart';
import 'package:dental_clinic_flutter/data/sync/merge/field_merge.dart';
import 'package:dental_clinic_flutter/data/sync/merge/merge_engine.dart';
import 'package:dental_clinic_flutter/data/sync/merge/tombstones.dart';

/// ساعتان حقيقيتان — واحدة لكل "جهاز" في المحاكي.
final Map<String, Hlc> _clocks = {'A': Hlc(), 'B': Hlc()};

Map<String, Object?> _asMap(Object? v) =>
    v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};

Object? _jsonSafe(Object? v) {
  if (identical(v, missing)) return '«leave»';
  return v;
}

String handle(String op, String argsJson) {
  final args = _asMap(argsJson.isEmpty ? {} : jsonDecode(argsJson));
  Object? result;
  switch (op) {
    case 'normalize':
      final text = args['text'] as String? ?? '';
      final phone = args['phone'] as String? ?? '';
      // توأم مضمّن لـ patientKeyFor (يعيش في طبقة المستودعات التي تجرّ FFI؛
      // منطقه الخالص هو بالضبط هذان السطران فوق normAr/normPhone المنقولتين).
      final trimmed = text.trim();
      final legacyKey = trimmed.isEmpty ? null : trimmed;
      final nm = normAr(text);
      final ph = normPhone(phone);
      final phoneKey = (nm.isEmpty && ph.isEmpty)
          ? null
          : (ph.isNotEmpty ? 'p:$ph:$nm' : 'n:$nm');
      result = {
        'arNorm': arNorm(text),
        'normPhone': normPhone(phone),
        'keyLegacy': legacyKey,
        'keyPhoneIdentity': phoneKey,
      };
      break;

    case 'mergeRecord':
      final merged = mergeRecordValues(
        base: args.containsKey('base') ? _asMap(args['base']) : missing,
        local: _asMap(args['local']),
        remote: _asMap(args['remote']),
        localHlc: args['localHlc'] as String?,
        remoteHlc: args['remoteHlc'] as String?,
      );
      result = {'merged': merged};
      break;

    case 'planDebt':
      final plan = planFieldMerge(
        entity: 'debts',
        shadow:
            args.containsKey('shadow') ? _asMap(args['shadow']) : null,
        local: args.containsKey('local') ? _asMap(args['local']) : null,
        remote: _asMap(args['remote']),
        tick: (d) => _clocks['A']!.tick('devA'),
        deviceId: 'devA',
      );
      final row = plan.row;
      final installments = row?['installments'];
      result = {
        'status': plan.status,
        'needsPush': plan.needsPush,
        'row': row,
        'active': activeItems(installments),
        'tombstones': installments is List
            ? installments.where((e) => isItemDeleted(e)).toList()
            : const [],
        'baseline': _jsonSafe(plan.baseline),
      };
      break;

    case 'mergeConfig':
      final plan = planConfigMerge(
        base: args.containsKey('base') ? _asMap(args['base']) : null,
        local: _asMap(args['local']),
        remote: _asMap(args['remote']),
        localHlc: args['localHlc'] as String?,
        remoteHlc: args['remoteHlc'] as String?,
        tick: (d) => _clocks['A']!.tick('devA'),
        deviceId: 'devA',
      );
      result = {
        'status': plan.status,
        'needsPush': plan.needsPush,
        'value': plan.value,
        'hlc': plan.hlc,
      };
      break;

    case 'hlcTick':
      final dev = args['device'] as String? ?? 'A';
      final v = _clocks[dev]!.tick('dev$dev');
      result = {'hlc': v};
      break;

    case 'hlcReceive':
      final dev = args['device'] as String? ?? 'A';
      _clocks[dev]!.receive(args['hlc'] as String?);
      final v = _clocks[dev]!.getState();
      result = {'ms': v.ms, 'counter': v.counter};
      break;

    case 'hlcCompare':
      result = {
        'aNewer': isNewer(args['a'] as String?, args['b'] as String?),
      };
      break;

    default:
      result = {'error': 'unknown op: $op'};
  }
  return jsonEncode(result);
}

void main() {
  globalContext['dartDemo'] = ((JSString op, JSString args) {
    try {
      return handle(op.toDart, args.toDart).toJS;
    } catch (e) {
      return jsonEncode({'error': '$e'}).toJS;
    }
  }).toJS;
}
