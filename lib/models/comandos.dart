import 'parse.dart';

/// Nó /comandos lido pelo ESP32 em pullCommands(): {"auto":true,"ml":true,"manual_s":0}
class Comandos {
  final bool auto;
  final bool ml;
  final double manualS; // > 0 = pedido de irrigação manual pendente

  const Comandos({this.auto = true, this.ml = true, this.manualS = 0});

  factory Comandos.fromMap(Object? v) {
    if (v is! Map) return const Comandos();
    return Comandos(
      auto: toB(v['auto'], true),
      ml: toB(v['ml'], true),
      manualS: toD(v['manual_s']),
    );
  }

  Comandos copyWith({bool? auto, bool? ml, double? manualS}) => Comandos(
        auto: auto ?? this.auto,
        ml: ml ?? this.ml,
        manualS: manualS ?? this.manualS,
      );
}
