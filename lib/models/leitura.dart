import 'parse.dart';

/// Um registro publicado pelo ESP32 em /sensores/atual e /historico.
/// Os campos espelham exatamente o JSON montado em pushCloud() no main.cpp.
class Leitura {
  final String? id; // chave do Firebase (só no histórico)
  final int ts; // epoch em segundos (0 = ESP32 sem NTP)
  final int uptimeMs;
  final int raw;
  final double solo; // % calibrado
  final double temp; // °C
  final double ar; // % umidade relativa
  final double? altura; // cm (null = HC-SR04 sem leitura)
  final double fuzzyS; // saída do fuzzy já com Kc
  final double mlpMult; // 0,5 .. 1,5
  final double decisaoS; // tempo decidido
  final double irrigadoS; // tempo realmente executado
  final double volumeMl;
  final bool testMode;
  final bool auto;
  final String motivo;
  final String status;
  final DateTime recebidoEm;

  Leitura({
    this.id,
    required this.ts,
    required this.uptimeMs,
    required this.raw,
    required this.solo,
    required this.temp,
    required this.ar,
    required this.altura,
    required this.fuzzyS,
    required this.mlpMult,
    required this.decisaoS,
    required this.irrigadoS,
    required this.volumeMl,
    required this.testMode,
    required this.auto,
    required this.motivo,
    required this.status,
    DateTime? recebidoEm,
  }) : recebidoEm = recebidoEm ?? DateTime.now();

  factory Leitura.fromMap(Map<Object?, Object?> m, {String? id}) => Leitura(
        id: id,
        ts: toI(m['ts']),
        uptimeMs: toI(m['uptime_ms']),
        raw: toI(m['raw']),
        solo: toD(m['solo']),
        temp: toD(m['temp']),
        ar: toD(m['ar']),
        altura: toDn(m['altura']),
        fuzzyS: toD(m['fuzzy_s']),
        mlpMult: toD(m['mlp_mult'], 1),
        decisaoS: toD(m['decisao_s']),
        irrigadoS: toD(m['irrigado_s']),
        volumeMl: toD(m['volume_ml']),
        testMode: toB(m['test_mode']),
        auto: toB(m['auto'], true),
        motivo: toS(m['motivo']),
        status: toS(m['status']),
      );

  /// Instante da leitura: ts do ESP32, senão a chave push, senão a hora de chegada.
  DateTime get momento {
    if (ts > 0) return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return tempoDaChavePush(id) ?? recebidoEm;
  }

  bool get irrigou => irrigadoS > 0;
  bool get bloqueado => status.startsWith('BLOQUEADO');
  bool get manual => status.contains('MANUAL');
  bool get emTeste => status.startsWith('TEST_MODE');

  /// Decisões que interessam ao usuário (o histórico também guarda os ciclos "sem irrigação").
  bool get relevante => irrigou || bloqueado || decisaoS > 0 || emTeste;
}
