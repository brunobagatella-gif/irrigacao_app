import 'parse.dart';

/// Nó /config no Firebase: dados do cultivo compartilhados entre celular, site e ESP32.
///   plantio       epoch (s) do dia do plantio; 0 = não definido
///   timer_regas   regas por dia do temporizador fixo usado na comparação de economia
///   timer_s       segundos por rega desse temporizador
class ConfigCultivo {
  final int plantioEpoch;
  final int timerRegas;
  final double timerS;

  const ConfigCultivo({this.plantioEpoch = 0, this.timerRegas = 2, this.timerS = 12});

  factory ConfigCultivo.fromMap(Object? v) {
    if (v is! Map) return const ConfigCultivo();
    return ConfigCultivo(
      plantioEpoch: toI(v['plantio']),
      timerRegas: toI(v['timer_regas'], 2).clamp(1, 12).toInt(),
      timerS: toD(v['timer_s'], 12).clamp(1, 60).toDouble(),
    );
  }

  Map<String, Object> toMap() =>
      {'plantio': plantioEpoch, 'timer_regas': timerRegas, 'timer_s': timerS};

  DateTime? get plantio =>
      plantioEpoch > 0 ? DateTime.fromMillisecondsSinceEpoch(plantioEpoch * 1000) : null;

  /// Segundos de bomba por dia do temporizador fixo.
  double get timerSegundosDia => timerRegas * timerS;

  ConfigCultivo copyWith({int? plantioEpoch, int? timerRegas, double? timerS}) => ConfigCultivo(
        plantioEpoch: plantioEpoch ?? this.plantioEpoch,
        timerRegas: timerRegas ?? this.timerRegas,
        timerS: timerS ?? this.timerS,
      );
}
