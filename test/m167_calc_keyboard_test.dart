/// م167/ج — الآلة الحاسبة بالكيبورد: أرقام وعمليات وناتج ومسح وEsc —
/// كلها تمر بمحرك _tap القائم حرفياً.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m167c_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  List<Override> ov() => [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ];

  testWidgets('كيبورد الحاسبة: 12+3= ⇒ 15، ومسح خلفي، وEsc يغلق',
      (t) async {
    t.view.physicalSize = const Size(420, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c0 = ProviderContainer(overrides: ov());
    final auth = c0.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c0.read(reposProvider).settings.set('app.config', {
      'centerName': 'م',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش'],
    });
    c0.dispose();
    await t.pumpWidget(
        ProviderScope(overrides: ov(), child: const DentalApp()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    await t.tap(find.byKey(const Key('fab-add')), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('rec-calc')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('calc-display')), findsOneWidget);

    // 12 + 3 = ⇒ 15 (أرقام وعملية وناتج من الكيبورد).
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
    await t.sendKeyEvent(LogicalKeyboardKey.digit3);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(
        t.widget<Text>(find.byKey(const Key('calc-display'))).data, '15');

    // مسح خلفي ⇒ 1.
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pump();
    expect(
        t.widget<Text>(find.byKey(const Key('calc-display'))).data, '1');

    // Esc يغلق الحوار.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('calc-display')), findsNothing);
  });
}
