import 'package:flutter_test/flutter_test.dart';
import 'package:irrigacao_app/models/parse.dart';
import 'package:irrigacao_app/services/fuzzy.dart';

// Valores de referência calculados com fuzzy() do tools/train_mlp.py,
// que replica o fuzzyController() do firmware. Rode: flutter test
void main() {
  test('fuzzy em Dart bate com o do firmware/Python', () {
    expect(Fuzzy.calcular(30, 25, 20).time, closeTo(11.55, 0.01));
    expect(Fuzzy.calcular(15, 30, 40).time, closeTo(15.0, 0.01));
    expect(Fuzzy.calcular(50, 20, null).time, closeTo(0.548, 0.01));
    expect(Fuzzy.calcular(45, 30, 8).time, closeTo(2.10, 0.01));
  });

  test('rótulos dominantes', () {
    final r = Fuzzy.calcular(30, 25, 20);
    expect(Fuzzy.soloNomes[r.soilIdx], 'baixo');
    expect(Fuzzy.tempNomes[r.tempIdx], 'moderada');
    expect(Fuzzy.faseNomes[r.heightIdx], 'vegetativo avançado');
  });

  test('instante da chave push do Firebase', () {
    final t = tempoDaChavePush('-NxYz0123456789abcd');
    expect(t, isNotNull);
    expect(t!.year, greaterThan(2020));
  });
}
