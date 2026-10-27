import '../models/leitura.dart';
import '../services/fuzzy.dart';
import 'formatos.dart';

/// Monta a justificativa da decisão em linguagem natural (relatório, seção 7.6:
/// "o usuário compreenda não apenas a decisão executada, mas o raciocínio").
List<String> explicarDecisao(Leitura l) {
  final fz = Fuzzy.calcular(l.solo, l.temp, l.altura);
  final passos = <String>[];

  passos.add('O solo está ${Fuzzy.soloNomes[fz.soilIdx]} (${fmtNum(l.solo, 0)} %) e a '
      'temperatura ${Fuzzy.tempNomes[fz.tempIdx]} (${fmtNum(l.temp)} °C).');

  final saida = Fuzzy.saidaNomes[fz.saidaIdx];
  passos.add(fz.saidaIdx == 0
      ? 'Pelas regras fuzzy, nessa combinação a planta não precisa de água agora.'
      : 'Pelas regras fuzzy, essa combinação pede uma irrigação $saida.');

  final alt = l.altura;
  if (alt == null || fz.heightIdx < 0) {
    passos.add('Sem leitura de altura: o fator da cultura ficou neutro (Kc 1,00).');
  } else {
    passos.add('Com ${fmtNum(alt, 0)} cm, a planta está na fase de '
        '${Fuzzy.faseNomes[fz.heightIdx]}; o fator da cultura Kc ${fmtNum(fz.kc, 2)} '
        'ajusta o tempo para ${fmtNum(l.fuzzyS)} s.');
  }

  if (l.fuzzyS >= 1) {
    final dif = ((l.mlpMult - 1) * 100).round();
    if (dif.abs() >= 2) {
      passos.add('A rede neural ${dif > 0 ? 'aumentou' : 'reduziu'} o tempo em ${dif.abs()} % '
          '(×${fmtNum(l.mlpMult, 2)}), considerando a tendência do solo e do clima nas últimas horas.');
    } else {
      passos.add('A rede neural manteve o tempo do fuzzy (×${fmtNum(l.mlpMult, 2)}).');
    }
  }

  if (l.irrigou) {
    passos.add('Resultado: irrigou ${fmtNum(l.irrigadoS)} s (≈ ${fmtVolume(l.volumeMl)}).');
  } else if (l.bloqueado) {
    passos.add('Resultado: ${statusAmigavel(l.status).toLowerCase()}, uma trava de segurança '
        'impediu a irrigação de ${fmtNum(l.decisaoS)} s.');
  } else if (l.emTeste) {
    passos.add('Resultado: decidiu ${fmtNum(l.decisaoS)} s, mas a bomba está travada (TEST_MODE).');
  } else {
    passos.add('Resultado: ${statusAmigavel(l.status).toLowerCase()}.');
  }
  return passos;
}
