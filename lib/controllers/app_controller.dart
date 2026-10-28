import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alerta.dart';
import '../models/comandos.dart';
import '../models/config_cultivo.dart';
import '../models/leitura.dart';
import '../services/cultivo.dart';
import '../services/data_source.dart';
import '../services/demo_data_source.dart';
import '../services/firebase_data_source.dart';
import 'formatos.dart';

class ResumoPeriodo {
  final int irrigacoes;
  final double segundos;
  final double volumeMl;
  final int bloqueios;
  const ResumoPeriodo(this.irrigacoes, this.segundos, this.volumeMl, this.bloqueios);
}

class ProximaRega {
  final DateTime? quando; // null = sem previsão ou "a qualquer momento"
  final String titulo;
  final String detalhe;
  const ProximaRega(this.quando, this.titulo, this.detalhe);
}

class DiaAgua {
  final DateTime dia;
  final double realMl;
  final double timerMl;
  final bool parcial; // dia corrente, ainda em andamento
  const DiaAgua(this.dia, this.realMl, this.timerMl, this.parcial);
}

class Economia {
  final double realMl; // consumo do sistema nos dias completos
  final double timerMl; // consumo do temporizador fixo nos mesmos dias
  final int dias;
  final List<DiaAgua> semana; // últimos 7 dias (o último pode ser parcial)
  const Economia(this.realMl, this.timerMl, this.dias, this.semana);

  /// Fração economizada (positiva) ou gasta a mais (negativa).
  double? get fracao => timerMl > 0 ? 1 - realMl / timerMl : null;
}

/// Controller (MVC): assina a fonte de dados uma única vez, guarda o último estado
/// e avisa as telas. As telas só leem daqui e chamam os métodos de ação.
class AppController extends ChangeNotifier {
  AppController({required this.prefs}) {
    _usarDemo = prefs.getBool('usarDemo') ?? false;
    _dbUrl = prefs.getString('dbUrl') ?? '';
    _offlineS = prefs.getInt('offlineS') ?? 90;
    _vazao = prefs.getDouble('vazao') ?? 33.3;
    _limiteHist = prefs.getInt('limiteHist') ?? 2200;
    _alertasVistos = prefs.getInt('alertasVistos') ?? 0;
    _conectarFonte();
    // reavalia "online/offline" e "há X s" mesmo sem dados novos
    _relogio = Timer.periodic(const Duration(seconds: 10), (_) => notifyListeners());
  }

  final SharedPreferences prefs;

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
  late int _alertasVistos;
  late Timer _relogio;

  DataSource? _fonte;
  final List<StreamSubscription> _subs = [];

  Leitura? atual;
  List<Leitura> historico = const [];
  List<Leitura> irrigacoes = const [];
  Comandos comandos = const Comandos();
  ConfigCultivo config = const ConfigCultivo();
  bool conectado = false;
  bool carregando = true;
  String cenario = 'normal';
  String? erro;

  List<AlturaDia>? alturas; // null = ainda não carregado
  bool carregandoAlturas = false;

  // ---------------- configurações ----------------
  bool get simulado => _usarDemo;
  String get dbUrl => _dbUrl;
  String get urlEfetiva => FirebaseDataSource.normalizarUrl(_dbUrl);
  int get offlineS => _offlineS;
  double get vazaoMlS => _vazao;
  int get limiteHistorico => _limiteHist;

  Future<void> setUsarDemo(bool v) async {
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
    irrigacoes = const [];
    comandos = const Comandos();
    config = const ConfigCultivo();
    alturas = null;
    conectado = false;
    carregando = true;
    erro = null;

    try {
      _fonte = _usarDemo
          ? DemoDataSource(vazaoMlS: _vazao)
          : FirebaseDataSource(databaseUrl: _dbUrl, limiteHistorico: _limiteHist);
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
    _subs.add(f.irrigacoes().listen((v) {
      irrigacoes = v;
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(f.comandos().listen((v) {
      comandos = v;
      notifyListeners();
    }, onError: _onErro));
    _subs.add(f.config().listen((v) {
      final mudouPlantio = v.plantioEpoch != config.plantioEpoch;
      config = v;
      if (mudouPlantio) alturas = null;
      notifyListeners();
    }, onError: (_) {}));
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

  /// Instante de referência: a leitura mais recente (no modo demo o relógio é simulado).
  DateTime get agora => atual?.momento ?? (historico.isNotEmpty ? historico.last.momento : DateTime.now());

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
    return resumo(historico.where((l) => _mesmoDia(l.momento, ref)));
  }

  static bool _mesmoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  static DateTime _dia(DateTime t) => DateTime(t.year, t.month, t.day);

  Leitura? get ultimaIrrigacao {
    for (var i = historico.length - 1; i >= 0; i--) {
      if (historico[i].irrigou) return historico[i];
    }
    return irrigacoes.isNotEmpty ? irrigacoes.last : null;
  }

  /// Se a IA está ligada mas o multiplicador é sempre 1,00, os pesos não foram carregados
  /// (mlp_weights.h ainda é o placeholder, MLP_TRAINED = false).
  bool get mlpPareceSemPesos {
    if (!comandos.ml) return false;
    final ativos = historico.where((l) => l.fuzzyS >= 1).toList();
    if (ativos.length < 5) return false;
    return ativos.reversed.take(30).every((l) => (l.mlpMult - 1).abs() < 0.005);
  }

  // ---------- conforto hídrico ----------

  /// Fração das leituras com o solo na faixa de conforto (35–62 %). null = sem dados.
  double? conforto(Duration? janelaDur) {
    final itens = janelaDur == null ? historico : janela(janelaDur);
    if (itens.length < 3) return null;
    final ok = itens.where((l) => l.solo >= Cultivo.confortoMin && l.solo <= Cultivo.confortoMax).length;
    return ok / itens.length;
  }

  /// Dias cobertos pelo histórico carregado.
  double get diasCarregados =>
      historico.length < 2 ? 0 : historico.last.momento.difference(historico.first.momento).inMinutes / 1440;

  // ---------- tendência e próxima rega ----------

  /// Inclinação da umidade do solo nas últimas 4 h, em pontos percentuais por hora.
  double? get tendenciaSolo {
    final ult = janela(const Duration(hours: 4));
    if (ult.length < 6) return null;
    final fim = ult.last.momento;
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (final l in ult) {
      final x = l.momento.difference(fim).inSeconds / 3600.0;
      sx += x;
      sy += l.solo;
      sxx += x * x;
      sxy += x * l.solo;
    }
    final n = ult.length.toDouble();
    final den = n * sxx - sx * sx;
    if (den.abs() < 1e-9) return null;
    return (n * sxy - sx * sy) / den;
  }

  ProximaRega get proximaRega {
    final a = atual;
    if (a == null) return const ProximaRega(null, '--', 'sem leitura');
    if (!comandos.auto) return const ProximaRega(null, 'Manual', 'automático desligado');
    final tend = tendenciaSolo;
    if (a.solo <= Cultivo.limiarRega) {
      return const ProximaRega(null, 'Em breve', 'solo abaixo de 35 %: no próximo ciclo liberado');
    }
    if (tend == null) return const ProximaRega(null, '--', 'aguardando 4 h de histórico');
    if (tend > -0.15) {
      return ProximaRega(null, 'Sem previsão', 'solo estável (${fmtNum(tend)} %/h)');
    }
    final horas = (a.solo - Cultivo.limiarRega) / -tend;
    if (horas > 48) return const ProximaRega(null, '> 2 dias', 'o solo está secando devagar');
    final quando = a.momento.add(Duration(minutes: (horas * 60).round()));
    final dia = _mesmoDia(quando, a.momento) ? '' : ' (amanhã)';
    return ProximaRega(quando, '~${fmtHora(quando)}$dia',
        'quando o solo chegar a 35 % (agora ${fmtNum(a.solo, 0)} %, caindo ${fmtNum(-tend)} %/h)');
  }

  // ---------- ciclo do feijoeiro ----------

  /// Dia do ciclo (dias desde o plantio); null se a data do plantio não foi definida.
  double? get diaCiclo {
    final p = config.plantio;
    if (p == null) return null;
    final d = agora.difference(p).inMinutes / 1440;
    return d < 0 ? 0.0 : d;
  }

  Future<void> carregarAlturas({bool forcar = false}) async {
    final p = config.plantio;
    final f = _fonte;
    if (p == null || f == null || carregandoAlturas) return;
    if (alturas != null && !forcar) return;
    carregandoAlturas = true;
    notifyListeners();
    try {
      alturas = await f.alturaDiaria(p, agora);
    } catch (e) {
      alturas = const [];
    }
    carregandoAlturas = false;
    notifyListeners();
  }

  // ---------- economia de água ----------

  Economia get economia {
    final timerDiaMl = config.timerSegundosDia * _vazao;
    final ref = _dia(agora);
    final porDia = <DateTime, double>{};
    for (final l in irrigacoes) {
      final d = _dia(l.momento);
      porDia[d] = (porDia[d] ?? 0.0) + (l.volumeMl > 0 ? l.volumeMl : l.irrigadoS * _vazao);
    }
    // período avaliado: do primeiro dia com dados (ou do plantio) até ontem
    var inicio = porDia.isEmpty ? ref : porDia.keys.reduce((a, b) => a.isBefore(b) ? a : b);
    final p = config.plantio;
    if (p != null && _dia(p).isAfter(inicio)) inicio = _dia(p);
    var real = 0.0;
    var dias = 0;
    for (var d = inicio; d.isBefore(ref); d = DateTime(d.year, d.month, d.day + 1)) {
      real += porDia[d] ?? 0;
      dias++;
    }
    final semana = <DiaAgua>[
      for (var i = 6; i >= 0; i--)
        DiaAgua(DateTime(ref.year, ref.month, ref.day - i), porDia[DateTime(ref.year, ref.month, ref.day - i)] ?? 0.0,
            timerDiaMl, i == 0),
    ];
    return Economia(real, dias * timerDiaMl, dias, semana);
  }

  // ---------- alertas ----------

  List<Alerta>? _alertasCache;
  Object? _alertasRef;

  List<Alerta> get alertas {
    if (identical(_alertasRef, historico) && _alertasCache != null) return _alertasCache!;
    final out = <Alerta>[];
    Leitura? ant;
    for (final l in historico) {
      if (ant != null) {
        final gap = l.momento.difference(ant.momento);
        if (!simulado && gap.inSeconds > _offlineS * 2) {
          out.add(Alerta(ant.momento, TipoAlerta.aviso, 'ESP32 ficou sem enviar dados',
              'Por ${gap.inMinutes} min, até ${fmtHora(l.momento)}'));
        }
        if (l.solo < 20 && ant.solo >= 20) {
          out.add(Alerta(l.momento, TipoAlerta.perigo, 'Solo em nível crítico',
              'Umidade caiu para ${fmtNum(l.solo, 0)} %'));
        }
        if (l.temp >= 34 && ant.temp < 34) {
          out.add(Alerta(l.momento, TipoAlerta.aviso, 'Calor intenso',
              '${fmtNum(l.temp)} °C: as regas tendem a ser mais longas'));
        }
        if (l.solo >= AppController.hardStopSolo && ant.solo < AppController.hardStopSolo) {
          out.add(Alerta(l.momento, TipoAlerta.aviso, 'Solo muito úmido',
              '${fmtNum(l.solo, 0)} %: o sistema bloqueia novas irrigações'));
        }
      }
      if (l.bloqueado && l.status.contains('limite diario') &&
          (ant == null || !ant.status.contains('limite diario'))) {
        out.add(Alerta(l.momento, TipoAlerta.perigo, 'Limite diário de bomba atingido',
            '${maxDailyPumpS.toStringAsFixed(0)} s de bomba em 24 h'));
      }
      if (l.manual && l.irrigou) {
        out.add(Alerta(l.momento, TipoAlerta.info, 'Irrigação manual executada',
            '${fmtNum(l.irrigadoS)} s · ${fmtVolume(l.volumeMl)}'));
      }
      ant = l;
    }
    if (!simulado && atual != null && !dispositivoOnline) {
      out.add(Alerta(atual!.momento, TipoAlerta.perigo, 'ESP32 offline agora',
          'Última leitura ${fmtIdade(idadeLeitura ?? Duration.zero)}'));
    }
    out.sort((a, b) => b.momento.compareTo(a.momento));
    _alertasRef = historico;
    _alertasCache = out.take(60).toList();
    return _alertasCache!;
  }

  int get alertasNaoLidos =>
      alertas.where((a) => a.momento.millisecondsSinceEpoch > _alertasVistos).length;

  Future<void> marcarAlertasLidos() async {
    _alertasVistos = agora.millisecondsSinceEpoch;
    await prefs.setInt('alertasVistos', _alertasVistos);
    notifyListeners();
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

  Future<void> setConfig(ConfigCultivo c) => _acao(() {
        if (c.plantioEpoch != config.plantioEpoch) alturas = null;
        config = c;
        return _fonte!.setConfig(c);
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
