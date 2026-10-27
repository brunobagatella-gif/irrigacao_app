// Conversões tolerantes: o Firebase pode devolver int, double, String ou null.
double toD(Object? v, [double def = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? def;
  return def;
}

double? toDn(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int toI(Object? v, [int def = 0]) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? def;
  return def;
}

bool toB(Object? v, [bool def = false]) => v is bool ? v : def;

String toS(Object? v, [String def = '']) => v == null ? def : v.toString();

const _pushChars = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';

/// As chaves criadas por POST no Firebase (push IDs) guardam o instante de criação
/// nos 8 primeiros caracteres. Serve de relógio quando o ESP32 ainda não
/// sincronizou o NTP e manda ts = 0.
DateTime? tempoDaChavePush(String? key) {
  if (key == null || key.length < 8) return null;
  var ms = 0;
  for (var i = 0; i < 8; i++) {
    final idx = _pushChars.indexOf(key[i]);
    if (idx < 0) return null;
    ms = ms * 64 + idx;
  }
  return DateTime.fromMillisecondsSinceEpoch(ms);
}
