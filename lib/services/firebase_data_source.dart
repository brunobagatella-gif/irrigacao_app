import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/comandos.dart';
import '../models/config_cultivo.dart';
import '../models/leitura.dart';
import '../models/parse.dart';
import 'data_source.dart';

/// Banco do projeto (o mesmo FIREBASE_HOST do secrets.h).
const urlBancoPadrao = 'https://controle-de-irrigacao-co-e3c37-default-rtdb.firebaseio.com';

/// Acesso ao Firebase Realtime Database pela API REST, igual ao firmware do ESP32.
/// Não precisa de SDK, firebase_options nem google-services.json: basta a URL do banco
/// e regras de leitura/escrita abertas (firebase/database.rules.json).
///
///   /sensores/atual   último estado (PUT do ESP32)
///   /historico/{push} log cronológico (POST do ESP32)
///   /comandos         {auto, ml, manual_s}  escrito pelo app, lido pelo ESP32
///   /config           {plantio, timer_regas, timer_s}
///   /simulacao        {cenario}  só para o simulador Python
///
/// Atualização por consulta periódica: estado atual a cada 3 s, histórico novo a cada 10 s
/// (só as chaves novas, sem baixar tudo de novo).
class FirebaseDataSource implements DataSource {
  FirebaseDataSource({String? databaseUrl, this.limiteHistorico = 2200})
      : base = normalizarUrl(databaseUrl) {
    _iniciar();
  }

  final String base;
  final int limiteHistorico;
  final _cli = http.Client();
  final List<Timer> _timers = [];
  bool _ativo = true;
  bool _falhando = false;

  // últimos valores (novos ouvintes recebem na hora)
  Leitura? _atual;
  List<Leitura> _hist = const [];
  List<Leitura> _irrig = const [];
  Comandos _cmd = const Comandos();
  ConfigCultivo _cfg = const ConfigCultivo();
  String _cenario = 'normal';
  bool _conectado = false;
  String? _ultimaChave;
  String _atualBruto = '';

  final _atualCtrl = StreamController<Leitura?>.broadcast();
  final _histCtrl = StreamController<List<Leitura>>.broadcast();
  final _irrCtrl = StreamController<List<Leitura>>.broadcast();
  final _cmdCtrl = StreamController<Comandos>.broadcast();
  final _cfgCtrl = StreamController<ConfigCultivo>.broadcast();
  final _cenCtrl = StreamController<String>.broadcast();
  final _conCtrl = StreamController<bool>.broadcast();

  static String normalizarUrl(String? url) {
    var u = (url == null || url.trim().isEmpty) ? urlBancoPadrao : url.trim();
    if (!u.startsWith('http')) u = 'https://$u'; // aceita o formato do FIREBASE_HOST
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  // ---------------- HTTP ----------------

  Uri _uri(String caminho, [Map<String, String>? q]) =>
      Uri.parse('$base/$caminho.json').replace(queryParameters: q);

  Future<Object?> _get(String caminho, [Map<String, String>? q]) async {
    final r = await _cli.get(_uri(caminho, q)).timeout(const Duration(seconds: 12));
    _status(r);
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  Future<void> _patch(String caminho, Map<String, Object?> dados) async {
    final r = await _cli
        .patch(_uri(caminho), headers: {'Content-Type': 'application/json'}, body: jsonEncode(dados))
        .timeout(const Duration(seconds: 12));
    _status(r);
  }

  void _status(http.Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw Exception('permission denied (HTTP ${r.statusCode})');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('HTTP ${r.statusCode}: ${r.body}');
    }
  }

  void _ok() {
    _falhando = false;
    if (!_conectado) {
      _conectado = true;
      _conCtrl.add(true);
    }
  }

  void _falha(Object e) {
    if (_conectado) {
      _conectado = false;
      _conCtrl.add(false);
    }
    if (!_falhando) {
      _falhando = true; // avisa uma vez, não a cada tentativa
      _atualCtrl.addError(e);
    }
  }

  static List<Leitura> _lista(Object? v) {
    if (v is! Map) return <Leitura>[];
    final lista = <Leitura>[
      for (final item in v.entries)
        if (item.value is Map) Leitura.fromMap(item.value as Map, id: item.key.toString()),
    ];
    lista.sort((a, b) => (a.id ?? '').compareTo(b.id ?? ''));
    return lista;
  }

  // ---------------- consultas periódicas ----------------

  void _cada(Duration d, Future<void> Function() f) {
    var ocupado = false;
    Future<void> rodar() async {
      if (ocupado || !_ativo) return;
      ocupado = true;
      try {
        await f();
        _ok();
      } catch (e) {
        _falha(e);
      } finally {
        ocupado = false;
      }
    }

    rodar();
    _timers.add(Timer.periodic(d, (_) => rodar()));
  }

  void _iniciar() {
    _cada(const Duration(seconds: 3), _lerAtual);
    _cada(const Duration(seconds: 3), _lerComandos);
    _cada(const Duration(seconds: 10), _lerHistorico);
    _cada(const Duration(seconds: 20), _lerConfig);
    _carregarIrrigacoes();
  }

  Future<void> _lerAtual() async {
    final v = await _get('sensores/atual');
    final bruto = jsonEncode(v);
    if (bruto == _atualBruto) return;
    _atualBruto = bruto;
    _atual = v is Map ? Leitura.fromMap(v) : null;
    _atualCtrl.add(_atual);
  }

  Future<void> _lerComandos() async {
    final c = Comandos.fromMap(await _get('comandos'));
    if (c.auto == _cmd.auto && c.ml == _cmd.ml && c.manualS == _cmd.manualS) return;
    _cmd = c;
    _cmdCtrl.add(c);
  }

  Future<void> _lerConfig() async {
    final c = ConfigCultivo.fromMap(await _get('config'));
    if (c.plantioEpoch != _cfg.plantioEpoch || c.timerRegas != _cfg.timerRegas || c.timerS != _cfg.timerS) {
      _cfg = c;
      _cfgCtrl.add(c);
    }
    final cen = (await _get('simulacao/cenario'))?.toString() ?? 'normal';
    if (cen != _cenario) {
      _cenario = cen;
      _cenCtrl.add(cen);
    }
  }

  Future<void> _lerHistorico() async {
    final ultima = _ultimaChave;
    final novos = ultima == null
        ? _lista(await _get('historico', {'orderBy': '"\$key"', 'limitToLast': '$limiteHistorico'}))
        : _lista(await _get('historico', {'orderBy': '"\$key"', 'startAt': '"$ultima"'}))
            .where((l) => l.id != ultima)
            .toList();
    if (ultima != null && novos.isEmpty) return;
    var h = [..._hist, ...novos];
    if (h.length > limiteHistorico) h = h.sublist(h.length - limiteHistorico);
    _hist = List.unmodifiable(h);
    if (h.isNotEmpty) _ultimaChave = h.last.id;
    _histCtrl.add(_hist);

    // irrigações novas entram também na lista do ciclo
    if (_semIndice) {
      _irrig = List.unmodifiable(_hist.where((l) => l.irrigou));
      _irrCtrl.add(_irrig);
    } else if (ultima != null) {
      final irr = novos.where((l) => l.irrigou).toList();
      if (irr.isNotEmpty) {
        _irrig = List.unmodifiable([..._irrig, ...irr]);
        _irrCtrl.add(_irrig);
      }
    }
  }

  /// Todas as irrigações do ciclo, uma vez só (usa o índice "irrigado_s" das regras).
  bool _semIndice = false;

  Future<void> _carregarIrrigacoes() async {
    try {
      final lista = _lista(await _get('historico', {'orderBy': '"irrigado_s"', 'startAt': '0.01'}));
      final ids = {for (final l in lista) l.id};
      final juntos = [...lista, ..._irrig.where((l) => !ids.contains(l.id))]
        ..sort((a, b) => (a.id ?? '').compareTo(b.id ?? ''));
      _irrig = List.unmodifiable(juntos);
    } catch (_) {
      // sem o índice no banco: usa só as irrigações do histórico carregado
      _semIndice = true;
      _irrig = List.unmodifiable(_hist.where((l) => l.irrigou));
    }
    _irrCtrl.add(_irrig);
  }

  @override
  Future<List<AlturaDia>> alturaDiaria(DateTime inicio, DateTime fim) async {
    // 1) medições com régua em /config/medicoes_altura: {"AAAAMMDD": cm}
    try {
      final m = await _get('config/medicoes_altura');
      if (m is Map && m.isNotEmpty) {
        final out = <AlturaDia>[];
        m.forEach((k, v) {
          final s = k.toString();
          final cm = v is num ? v.toDouble() : double.tryParse(v.toString());
          if (s.length != 8 || cm == null) return;
          final d = DateTime(int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)),
              int.parse(s.substring(6, 8)), 12);
          out.add(AlturaDia(d, cm, manual: true));
        });
        if (out.isNotEmpty) return out..sort((a, b) => a.dia.compareTo(b.dia));
      }
    } catch (_) {}
    // 2) sem medições manuais: leitura diária do HC-SR04 no histórico
    final dias = <DateTime>[];
    for (var d = DateTime(inicio.year, inicio.month, inicio.day, 12);
        !d.isAfter(fim);
        d = DateTime(d.year, d.month, d.day + 1, 12)) {
      dias.add(d);
    }
    // uma consulta pequena por dia: primeiro registro a partir do meio-dia
    final res = await Future.wait(dias.map((d) async {
      try {
        final l = _lista(await _get('historico', {
          'orderBy': '"\$key"',
          'startAt': '"${prefixoChavePush(d)}"',
          'limitToFirst': '1',
        }));
        if (l.isEmpty) return null;
        final r = l.first;
        final alt = r.altura;
        if (alt == null || r.momento.difference(d).inHours > 12) return null;
        return AlturaDia(d, alt);
      } catch (_) {
        return null;
      }
    }));
    return [for (final r in res) if (r != null) r];
  }

  // ---------------- DataSource ----------------

  @override
  bool get simulado => false;

  @override
  Stream<Leitura?> atual() async* {
    if (_atual != null) yield _atual;
    yield* _atualCtrl.stream;
  }

  @override
  Stream<List<Leitura>> historico({int limite = 600}) async* {
    if (_hist.isNotEmpty) yield _hist;
    yield* _histCtrl.stream;
  }

  @override
  Stream<List<Leitura>> irrigacoes() async* {
    yield _irrig;
    yield* _irrCtrl.stream;
  }

  @override
  Stream<Comandos> comandos() async* {
    yield _cmd;
    yield* _cmdCtrl.stream;
  }

  @override
  Stream<ConfigCultivo> config() async* {
    yield _cfg;
    yield* _cfgCtrl.stream;
  }

  @override
  Stream<bool> conectado() async* {
    yield _conectado;
    yield* _conCtrl.stream;
  }

  @override
  Stream<String> cenario() async* {
    yield _cenario;
    yield* _cenCtrl.stream;
  }

  @override
  Future<void> setAuto(bool v) async {
    await _patch('comandos', {'auto': v});
    _cmd = _cmd.copyWith(auto: v);
    _cmdCtrl.add(_cmd);
  }

  @override
  Future<void> setMl(bool v) async {
    await _patch('comandos', {'ml': v});
    _cmd = _cmd.copyWith(ml: v);
    _cmdCtrl.add(_cmd);
  }

  @override
  Future<void> irrigarManual(double segundos) async {
    final s = double.parse(segundos.toStringAsFixed(1));
    await _patch('comandos', {'manual_s': s});
    _cmd = _cmd.copyWith(manualS: s);
    _cmdCtrl.add(_cmd);
  }

  @override
  Future<void> setCenario(String cenario) async {
    await _patch('simulacao', {
      'cenario': cenario,
      'alterado_em': {'.sv': 'timestamp'},
    });
    _cenario = cenario;
    _cenCtrl.add(cenario);
  }

  @override
  Future<void> setConfig(ConfigCultivo c) async {
    await _patch('config', c.toMap());
    _cfg = c;
    _cfgCtrl.add(c);
  }

  @override
  void dispose() {
    _ativo = false;
    for (final t in _timers) {
      t.cancel();
    }
    _cli.close();
    _atualCtrl.close();
    _histCtrl.close();
    _irrCtrl.close();
    _cmdCtrl.close();
    _cfgCtrl.close();
    _cenCtrl.close();
    _conCtrl.close();
  }
}
