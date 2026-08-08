/// معرّفات فريدة — توأم utils/uid.js (زمن base36 + لاحقة عشوائية).
library;

import 'dart:math';

final _rand = Random();
const _chars = '0123456789abcdefghijklmnopqrstuvwxyz';

String genId() {
  final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final r = List.generate(8, (_) => _chars[_rand.nextInt(36)]).join();
  return '$t$r';
}
