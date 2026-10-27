import 'dart:math' as math;

/// Cópia fiel de fuzzyController() do main.cpp.
/// Usada para (1) rotular as leituras no app (solo "baixo", fase "floração"...)
/// e explicar as decisões em linguagem natural, e (2) gerar dados no modo demonstração.
/// Se mudar os conjuntos no firmware, mude aqui também.
class Trap {
  final double a, b, c, d;
  const Trap(this.a, this.b, this.c, this.d);

  double mu(double x) {
    if (x <= a || x >= d) return 0;
    if (x >= b && x <= c) return 1;
    if (x < b) return (x - a) / (b - a);
    return (d - x) / (d - c);
  }
}

class FuzzyResult {
  final List<double> mu; // [0-4] solo, [5-9] temperatura, [10-14] altura
  final double baseTime; // Mamdani antes do Kc (s)
  final double kc;
  final double time; // baseTime * kc (s)
  final int soilIdx, tempIdx, heightIdx; // heightIdx = -1 sem leitura
  const FuzzyResult(this.mu, this.baseTime, this.kc, this.time, this.soilIdx, this.tempIdx,
      this.heightIdx);

  /// Conjunto de saída da regra dominante (0 = nulo ... 4 = muito longo).
  int get saidaIdx => Fuzzy.rules[soilIdx][tempIdx];
}

class Fuzzy {
  static const maxPumpS = 15.0;

  static const soilSets = [
    Trap(-1, 0, 10, 20), Trap(18, 24, 30, 35), Trap(32, 40, 54, 62),
    Trap(58, 66, 72, 80), Trap(78, 86, 100, 101),
  ];
  static const tempSets = [
    Trap(-1, 0, 8, 14), Trap(12, 15, 17, 20), Trap(18, 21, 25, 28),
    Trap(26, 29, 33, 36), Trap(34, 38, 45, 46),
  ];
  static const heightSets = [
    Trap(-1, 0, 2, 5), Trap(3, 6, 12, 15), Trap(10, 15, 25, 30),
    Trap(25, 32, 43, 50), Trap(40, 50, 70, 71),
  ];
  static const outSets = [
    Trap(-1, 0, 0.3, 1.5), Trap(1, 2.5, 3.5, 5), Trap(4, 6, 8, 10),
    Trap(8, 10, 12, 14), Trap(12, 14, 15, 16),
  ];
  static const kcFase = [0.35, 0.70, 1.05, 1.15, 0.90];
  static const rules = [
    [3, 3, 4, 4, 4], // solo crítico
    [2, 2, 3, 3, 4], // solo baixo
    [0, 0, 0, 1, 1], // solo ideal
    [0, 0, 0, 0, 0], // solo alto
    [0, 0, 0, 0, 0], // solo encharcado
  ];

  static const soloNomes = ['crítico', 'baixo', 'ideal', 'alto', 'encharcado'];
  static const tempNomes = ['muito fria', 'fria', 'moderada', 'quente', 'muito quente'];
  static const faseNomes = [
    'germinação', 'vegetativo inicial', 'vegetativo avançado', 'floração', 'produção'
  ];
  static const saidaNomes = ['nenhuma', 'curta', 'média', 'longa', 'muito longa'];

  // nomes sem acento, iguais aos do firmware (usados no texto "motivo" do modo demo)
  static const soloNomesFw = ['critico', 'baixo', 'ideal', 'alto', 'encharcado'];
  static const tempNomesFw = ['muito fria', 'fria', 'moderada', 'quente', 'muito quente'];
  static const faseNomesFw = [
    'germinacao', 'veg. inicial', 'veg. avancado', 'floracao', 'producao'
  ];

  static int _argmax(List<double> v, int from, int n) {
    var k = 0;
    for (var i = 1; i < n; i++) {
      if (v[from + i] > v[from + k]) k = i;
    }
    return k;
  }

  static FuzzyResult calcular(double soil, double temperature, double? height) {
    final s = soil.clamp(0, 100).toDouble();
    final t = temperature.clamp(0, 45).toDouble();
    final mu = List<double>.filled(15, 0);
    for (var i = 0; i < 5; i++) {
      mu[i] = soilSets[i].mu(s);
      mu[5 + i] = tempSets[i].mu(t);
    }

    final h0 = height;
    final semAltura = h0 == null || h0.isNaN;
    var kc = 1.0;
    if (h0 != null && !h0.isNaN) {
      final h = h0.clamp(0, 70).toDouble();
      var num = 0.0, den = 0.0;
      for (var i = 0; i < 5; i++) {
        mu[10 + i] = heightSets[i].mu(h);
        num += mu[10 + i] * kcFase[i];
        den += mu[10 + i];
      }
      kc = den > 0.0001 ? num / den : 1.0;
    }

    // Mamdani: min nas premissas, max na agregação, centroide na defuzzificação
    const step = 0.1;
    const points = 151;
    final agg = List<double>.filled(points, 0);
    for (var i = 0; i < 5; i++) {
      for (var j = 0; j < 5; j++) {
        final w = math.min(mu[i], mu[5 + j]);
        if (w <= 0) continue;
        final o = outSets[rules[i][j]];
        for (var k = 0; k < points; k++) {
          agg[k] = math.max(agg[k], math.min(w, o.mu(k * step)));
        }
      }
    }
    var num = 0.0, den = 0.0;
    for (var k = 0; k < points; k++) {
      num += k * step * agg[k];
      den += agg[k];
    }
    final base = den > 0.0001 ? num / den : 0.0;
    final time = (base * kc).clamp(0, maxPumpS).toDouble();

    return FuzzyResult(mu, base, kc, time, _argmax(mu, 0, 5), _argmax(mu, 5, 5),
        semAltura ? -1 : _argmax(mu, 10, 5));
  }
}
