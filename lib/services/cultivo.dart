import 'dart:math' as math;

/// Parâmetros do feijoeiro usados no relatório (seções 7.2 a 7.4).
class Fase {
  final String nome;
  final int inicio, fim; // dias após o plantio
  final double kc;
  const Fase(this.nome, this.inicio, this.fim, this.kc);
}

class Cultivo {
  static const cicloDias = 90;

  // relatório 7.3 (FAO-56 / EMBRAPA)
  static const fases = [
    Fase('Germinação', 0, 10, 0.35),
    Fase('Vegetativo inicial', 10, 25, 0.70),
    Fase('Vegetativo avançado', 25, 40, 1.05),
    Fase('Floração', 40, 60, 1.15),
    Fase('Produção', 60, 90, 0.90),
  ];

  // relatório 7.2: curva logística, altura máx. 60 cm, r = 0,08/dia, inflexão no dia 35
  static const alturaMax = 60.0, taxa = 0.08, inflexao = 35.0;

  static double alturaEsperada(double dia) => alturaMax / (1 + math.exp(-taxa * (dia - inflexao)));

  static int faseIdx(double dia) {
    for (var i = 0; i < fases.length; i++) {
      if (dia < fases[i].fim) return i;
    }
    return fases.length - 1;
  }

  /// Faixa de "conforto hídrico" na umidade do solo (%): miolo do conjunto fuzzy "ideal".
  static const confortoMin = 35.0, confortoMax = 62.0;

  /// Umidade abaixo da qual o fuzzy volta a pedir irrigação relevante.
  static const limiarRega = 35.0;
}
