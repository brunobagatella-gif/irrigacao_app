import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/comandos.dart';
import '../models/leitura.dart';
import '../services/data_source.dart';
import '../services/demo_data_source.dart';
import '../services/firebase_data_source.dart';

class ResumoPeriodo {
  final int irrigacoes;
  final double segundos;
  final double volumeMl;
  final int bloqueios;
  const ResumoPeriodo(this.irrigacoes, this.segundos, this.volumeMl, this.bloqueios);
}

/// Controller (MVC): assina a fonte de dados uma única vez, guarda o último estado
/// e avisa as telas. As telas só leem daqui e chamam os métodos de ação.
class AppController extends ChangeNotifier {
  AppController({required this.prefs, required this.firebaseDisponivel}) {
    _usarDemo = !firebaseDisponivel || (prefs.getBool('usarDemo') ?? false);
    _dbUrl = prefs.getString('dbUrl') ?? '';
    _offlineS = prefs.getInt('offlineS') ?? 90;
    _vazao = prefs.getDouble('vazao') ?? 33.3;
    _limiteHist = prefs.getInt('limiteHist') ?? 600;
    _conectarFonte();
    // reavalia "online/offline" e "há X s" mesmo sem dados novos
    _relogio = Timer.periodic(const Duration(seconds: 10), (_) => notifyListeners());
  }

  final SharedPreferences prefs;
  final bool firebaseDisponivel;

  // limites do firmware (main.cpp) mostrados na tela de controle
  static const hardStopSolo = 75.0;
  static const maxPumpS = 15.0;
  static const maxDailyPumpS = 60.0;
  static const minIntervalMin = 30;

  late bool _usarDemo;
  late String _dbUrl;
  late int _offlineS;
  late double _vazao;
  late int _limiteHist;
  late Timer _relogio;

  DataSource? _fonte;
  final List<StreamSubscription> _subs = [];

  Leitura? atual;
  List<Leitura> historico = const [];
  Comandos comandos = const Comandos();
  bool conectado = false;
  bool carregando = true;
  String cenario = 'normal';
  String? erro;

  // ---------------- configurações ----------------
  bool get simulado => _usarDemo;
  String get dbUrl => _dbUrl;
  int get offlineS => _offlineS;
  double get vazaoMlS => _vazao;
  int get limiteHistorico => _limiteHist;

  Future<void> setUsarDemo(bool v) async {
    if (!firebaseDisponivel) v = true;
    _usarDemo = v;
    await prefs.setBool('usarDemo', v);
    _conectarFonte();
  }

  Future<void> setDbUrl(String v) async {
    _dbUrl = v.trim();
    await prefs.setString('dbUrl', _dbUrl);
    if (!_usarDemo) _conectarFonte();
  }

  Future<void> setOfflineS(int v) async {
    _offlineS = v;
    await prefs.setInt('offlineS', v);
    notifyListeners();
  }

  Future<void> setVazao(double v) async {
    _vazao = v;
    await prefs.setDouble('vazao', v);
    notifyListeners();
  }

  Future<void> setLimiteHistorico(int v) async {
    _limiteHist = v;
    await prefs.setInt('limiteHist', v);
    _conectarFonte();
  }

  void _conectarFonte() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _fonte?.dispose();
    atual = null;
    historico = const [];
    comandos = const Comandos();
    conectado = false;
    carregando = true;
    erro = null;

    try {
      _fonte = _usarDemo ? DemoDataSource(vazaoMlS: _vazao) : FirebaseDataSource(databaseUrl: _dbUrl);
    } catch (e) {
      erro = 'Não foi possível abrir o Firebase ($e). Usando demonstração.';
      _usarDemo = true;
      _fonte = DemoDataSource(vazaoMlS: _vazao);
    }
    final f = _fonte!;
    _subs.add(f.atual().listen((v) {
      atual = v;
      carregando = false;
      notifyListeners();
    }, onError: _onErro));
    _subs.add(f.historico(limite: _limiteHist).listen((v) {
      historico = v;
      carregando = false;
      notifyListeners();
    }, onError: _onErro));
    _subs.add(f.comandos().listen((v) {
      comandos = v;
      notifyListeners();
    }, onError: _onErro));
    _subs.add(f.conectado().listen((v) {
      conectado = v;
      notifyListeners();
    }, onError: _onErro));
    _subs.add(f.cenario().listen((v) {
      cenario = v;
      notifyListeners();
    }, onError: (_) {}));
    notifyListeners();
  }

  void _onErro(Object e) {
    final txt = e.toString();
    erro = txt.contains('permission')
        ? 'Sem permissão no Firebase. Confira as regras do Realtime Database.'
        : 'Erro de comunicação: $txt';
    carregando = false;
    notifyListeners();
  }

  void limparErro() {
    erro = null;
    notifyListeners();
  }

  // ---------------- estado derivado ----------------

  /// Quanto tempo desde a última leitura do ESP32 (null no modo demonstração).
  Duration? get idadeLeitura {
    final a = atual;
    if (a == null || simulado) return null;
    final d = DateTime.now().difference(a.momento);
    return d.isNegative ? Duration.zero : d;
  }

  bool get dispositivoOnline {
    if (atual == null) return false;
    if (simulado) return true;
    return (idadeLeitura?.inSeconds ?? 1 << 30) < _offlineS;
  }

  bool get comandoManualPendente => comandos.manualS > 0;

  /// Registros dentro da janela, contada a partir da leitura mais recente.
  List<Leitura> janela(Duration d) {
    if (historico.isEmpty) return const [];
    final fim = historico.last.momento;
    final ini = fim.subtract(d);
    return historico.where((l) => !l.momento.isBefore(ini)).toList();
  }

  ResumoPeriodo resumo(Iterable<Leitura> itens) {
    var n = 0, b = 0;
    var s = 0.0, v = 0.0;
    for (final l in itens) {
      if (l.irrigou) {
        n++;
        s += l.irrigadoS;
        v += l.volumeMl;
      }
      if (l.bloqueado) b++;
    }
    return ResumoPeriodo(n, s, v, b);
  }

  /// Resumo do dia corrente (data da leitura mais recente).
  ResumoPeriodo get resumoHoje {
    if (historico.isEmpty) return const ResumoPeriodo(0, 0, 0, 0);
    final ref = historico.last.momento;
    return resumo(historico.where((l) =>
        l.momento.year == ref.year && l.momento.month == ref.month && l.momento.day == ref.day));
  }

  Leitura? get ultimaIrrigacao {
    for (var i = historico.length - 1; i >= 0; i--) {
      if (historico[i].irrigou) return historico[i];
    }
    return null;
  }

  /// Se a IA está ligada mas o multiplicador é sempre 1,00, os pesos não foram carregados
  /// (mlp_weights.h ainda é o placeholder, MLP_TRAINED = false).
  bool get mlpPareceSemPesos {
    if (!comandos.ml) return false;
    final ativos = historico.where((l) => l.fuzzyS >= 1).toList();
    if (ativos.length < 5) return false;
    return ativos.reversed.take(30).every((l) => (l.mlpMult - 1).abs() < 0.005);
  }

  // ---------------- ações ----------------
  Future<void> setAuto(bool v) => _acao(() {
        comandos = comandos.copyWith(auto: v);
        return _fonte!.setAuto(v);
      });

  Future<void> setMl(bool v) => _acao(() {
        comandos = comandos.copyWith(ml: v);
        return _fonte!.setMl(v);
      });

  Future<void> irrigarManual(double s) => _acao(() {
        comandos = comandos.copyWith(manualS: s);
        return _fonte!.irrigarManual(s);
      });

  Future<void> setCenario(String c) => _acao(() {
        cenario = c;
        return _fonte!.setCenario(c);
      });

  Future<void> _acao(Future<void> Function() f) async {
    try {
      final fut = f(); // atualização otimista
      notifyListeners();
      await fut;
    } catch (e) {
      _onErro(e);
    }
  }

  @override
  void dispose() {
    _relogio.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _fonte?.dispose();
    super.dispose();
  }
}
