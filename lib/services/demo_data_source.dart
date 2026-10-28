import 'dart:async';
import 'dart:math' as math;

import '../models/comandos.dart';
import '../models/config_cultivo.dart';
import '../models/leitura.dart';
import 'cultivo.dart';
import 'data_source.dart';
import 'fuzzy.dart';

/// Cultivo virtual local para apresentar o app sem ESP32 nem Firebase.
/// Cada tique (3 s reais) avança 5 min simulados e aplica a MESMA lógica do
/// firmware: fuzzy -> Kc -> ajuste MLP -> travas de segurança.
/// Os cenários (calor, chuva...) mudam o clima virtual na hora.
class DemoDataSource implements DataSource {
  DemoDataSource({this.vazaoMlS = 33.3}) {
    _t = DateTime.now().subtract(const Duration(days: 7));
    _inicioDia = _t;
    // plantio virtual 30 dias antes do início do histórico
    _cfg = ConfigCultivo(
        plantioEpoch: _t.subtract(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000);
    for (var i = 0; i < 7 * 288; i++) {
      _passo(emitir: false); // 7 dias de histórico prévio
    }
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _passo());
  }

  final double vazaoMlS;
  final _rng = math.Random(7);
  late Timer _timer;

  late DateTime _t;
  late DateTime _inicioDia;
  DateTime? _ultimaIrrigacao;
  double _bombaHoje = 0;
  double _solo = 44;
  double _dia = 30; // dia do ciclo do feijoeiro
  String _cenario = 'normal';
  Comandos _cmd = const Comandos();
  final List<double> _soloHist = [];
  final List<double> _tempHist = [];
  final List<Leitura> _hist = [];
  final List<Leitura> _irrig = [];
  Leitura? _atual;
  late ConfigCultivo _cfg;

  final _atualCtrl = StreamController<Leitura?>.broadcast();
  final _histCtrl = StreamController<List<Leitura>>.broadcast();
  final _cmdCtrl = StreamController<Comandos>.broadcast();
  final _cenCtrl = StreamController<String>.broadcast();
  final _cfgCtrl = StreamController<ConfigCultivo>.broadcast();
  final _irrCtrl = StreamController<List<Leitura>>.broadcast();

  double _gauss() {
    final u1 = math.max(_rng.nextDouble(), 1e-9), u2 = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  void _passo({bool emitir = true}) {
    _t = _t.add(const Duration(minutes: 5));
    _dia += 5 / 1440;
    final h = _t.hour + _t.minute / 60;
    final onda = math.sin(2 * math.pi * (h - 9) / 24); // pico por volta das 15 h

    double tBase = 23, tAmp = 6, arBase = 62, et = 1;
    switch (_cenario) {
      case 'calor':
        tBase = 34; tAmp = 5; arBase = 35; et = 1.4;
      case 'inverno':
        tBase = 13; tAmp = 5; arBase = 72; et = 0.6;
      case 'chuva':
        tBase = 20; tAmp = 2.5; arBase = 88; et = 0.4;
      case 'estresse':
        et = 2.4;
    }
    final temp = tBase + tAmp * onda + _gauss() * 0.6;
    final ar = (arBase - 15 * onda + _gauss() * 2).clamp(15, 99).toDouble();
    final altura = 0.97 * Cultivo.alturaEsperada(_dia) + _gauss() * 0.3;

    // balanço hídrico simplificado (% por 5 min)
    final kc = Fuzzy.calcular(_solo, temp, altura).kc;
    final perda = 0.5 * (0.025 + 0.006 * math.max(0, temp - 10)) * (1 - ar / 200) * kc * et;
    _solo -= perda;
    if (_cenario == 'chuva' && _rng.nextDouble() < 0.015) _solo += 2 + _rng.nextDouble() * 4;
    if (_solo > 60) _solo -= (_solo - 60) * 0.02; // drenagem acima da capacidade de campo
    _solo = _solo.clamp(3, 100).toDouble();

    final solo = (_solo + _gauss() * 0.8).clamp(0, 100).toDouble();
    final fz = Fuzzy.calcular(solo, temp, altura);

    _soloHist.add(solo);
    _tempHist.add(temp);
    if (_soloHist.length > 48) _soloHist.removeAt(0);
    if (_tempHist.length > 48) _tempHist.removeAt(0);
    final dS = solo - _soloHist.first, dT = temp - _tempHist.first;

    // mesmo rótulo heurístico do train_mlp.py --synthetic
    var mult = 1.0;
    if (_cmd.ml) {
      mult = (1 - 0.5 * (dS / 20).clamp(-1, 1) + 0.15 * (dT / 10).clamp(-1, 1) +
              0.15 * (50 - ar) / 50)
          .clamp(0.5, 1.5)
          .toDouble();
    }
    final finalS = fz.time < 1 ? 0.0 : (fz.time * mult).clamp(0, 15).toDouble();

    double irrigado = 0;
    String nota;
    if (_cmd.manualS > 0) {
      (irrigado, nota) = _irrigar(_cmd.manualS, solo, true);
      _cmd = _cmd.copyWith(manualS: 0);
      if (emitir) _cmdCtrl.add(_cmd);
    } else if (_cmd.auto) {
      (irrigado, nota) = _irrigar(finalS, solo, false);
    } else {
      nota = 'modo manual: automatico desligado';
    }

    final motivo = 'solo ${Fuzzy.soloNomesFw[fz.soilIdx]}, temp ${Fuzzy.tempNomesFw[fz.tempIdx]}, '
        'fase ${Fuzzy.faseNomesFw[fz.heightIdx]}, Kc ${fz.kc.toStringAsFixed(2)}, '
        'fuzzy ${fz.time.toStringAsFixed(1)}s, MLP x${mult.toStringAsFixed(2)}';

    final l = Leitura(
      id: 'demo${_hist.length}',
      ts: _t.millisecondsSinceEpoch ~/ 1000,
      uptimeMs: 0,
      raw: (3000 - solo / 100 * 1700).round(),
      solo: solo,
      temp: temp,
      ar: ar,
      altura: altura,
      fuzzyS: fz.time,
      mlpMult: mult,
      decisaoS: finalS,
      irrigadoS: irrigado,
      volumeMl: irrigado * vazaoMlS,
      testMode: false,
      auto: _cmd.auto,
      motivo: motivo,
      status: nota,
      recebidoEm: _t,
    );
    _atual = l;
    _hist.add(l);
    if (_hist.length > 2100) _hist.removeAt(0);
    if (l.irrigou) _irrig.add(l);
    if (emitir) {
      _atualCtrl.add(l);
      _histCtrl.add(List.unmodifiable(_hist));
      if (l.irrigou) _irrCtrl.add(List.unmodifiable(_irrig));
    }
  }

  // Mesmas travas de irrigate() no main.cpp
  (double, String) _irrigar(double s, double solo, bool manual) {
    if (solo >= 75) return (0, 'BLOQUEADO: solo muito umido');
    if (s < 1) return (0, 'sem irrigacao');
    s = s.clamp(0, 15).toDouble();
    if (_t.difference(_inicioDia).inHours >= 24) {
      _inicioDia = _t;
      _bombaHoje = 0;
    }
    if (_bombaHoje + s > 60) return (0, 'BLOQUEADO: limite diario de bomba');
    if (!manual &&
        _ultimaIrrigacao != null &&
        _t.difference(_ultimaIrrigacao!).inMinutes < 30) {
      return (0, 'BLOQUEADO: intervalo minimo entre irrigacoes');
    }
    _ultimaIrrigacao = _t;
    _bombaHoje += s;
    _solo = math.min(100.0, _solo + s * 0.9);
    return (s, manual ? 'irrigacao MANUAL executada' : 'irrigacao AUTOMATICA executada');
  }

  List<Leitura> _ultimos(int n) =>
      List.unmodifiable(_hist.length <= n ? _hist : _hist.sublist(_hist.length - n));

  @override
  bool get simulado => true;

  @override
  Stream<Leitura?> atual() async* {
    yield _atual;
    yield* _atualCtrl.stream;
  }

  @override
  Stream<List<Leitura>> historico({int limite = 600}) async* {
    yield _ultimos(limite);
    yield* _histCtrl.stream.map((h) => h.length <= limite ? h : h.sublist(h.length - limite));
  }

  @override
  Stream<Comandos> comandos() async* {
    yield _cmd;
    yield* _cmdCtrl.stream;
  }

  @override
  Stream<bool> conectado() => Stream.value(true);

  @override
  Stream<String> cenario() async* {
    yield _cenario;
    yield* _cenCtrl.stream;
  }

  @override
  Stream<ConfigCultivo> config() async* {
    yield _cfg;
    yield* _cfgCtrl.stream;
  }

  @override
  Stream<List<Leitura>> irrigacoes() async* {
    yield List.unmodifiable(_irrig);
    yield* _irrCtrl.stream;
  }

  @override
  Future<List<AlturaDia>> alturaDiaria(DateTime inicio, DateTime fim) async {
    final plantio = _cfg.plantio ?? inicio;
    final r = math.Random(11);
    final out = <AlturaDia>[];
    for (var d = DateTime(inicio.year, inicio.month, inicio.day, 12);
        !d.isAfter(fim);
        d = d.add(const Duration(days: 1))) {
      final dia = d.difference(plantio).inHours / 24;
      if (dia < 0) continue;
      final alt = 0.97 * Cultivo.alturaEsperada(dia) + (r.nextDouble() - 0.5) * 1.2;
      out.add(AlturaDia(d, math.max(0.0, alt)));
    }
    return out;
  }

  @override
  Future<void> setConfig(ConfigCultivo c) async {
    _cfg = c;
    _cfgCtrl.add(c);
  }

  @override
  Future<void> setAuto(bool v) async {
    _cmd = _cmd.copyWith(auto: v);
    _cmdCtrl.add(_cmd);
  }

  @override
  Future<void> setMl(bool v) async {
    _cmd = _cmd.copyWith(ml: v);
    _cmdCtrl.add(_cmd);
  }

  @override
  Future<void> irrigarManual(double segundos) async {
    _cmd = _cmd.copyWith(manualS: segundos);
    _cmdCtrl.add(_cmd); // executado no próximo tique, como o ESP32 faz no próximo ciclo
  }

  @override
  Future<void> setCenario(String cenario) async {
    _cenario = cenario;
    _cenCtrl.add(cenario);
  }

  @override
  void dispose() {
    _timer.cancel();
    _atualCtrl.close();
    _histCtrl.close();
    _cmdCtrl.close();
    _cenCtrl.close();
    _cfgCtrl.close();
    _irrCtrl.close();
  }
}
