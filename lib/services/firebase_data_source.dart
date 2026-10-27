import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/comandos.dart';
import '../models/leitura.dart';
import 'data_source.dart';

/// Estrutura usada (a mesma do main.cpp):
///   /sensores/atual   último estado (PUT a cada envio)
///   /historico/{push} log cronológico (POST a cada envio)
///   /comandos         {auto, ml, manual_s}  escrito pelo app, lido pelo ESP32
///   /simulacao        {cenario}             lido pelo simulador Python (opcional)
class FirebaseDataSource implements DataSource {
  final FirebaseDatabase db;

  FirebaseDataSource({String? databaseUrl}) : db = _abrir(databaseUrl);

  static FirebaseDatabase _abrir(String? url) {
    if (url == null || url.trim().isEmpty) return FirebaseDatabase.instance;
    var u = url.trim();
    if (!u.startsWith('http')) u = 'https://$u'; // aceita o mesmo formato do FIREBASE_HOST
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: u);
  }

  @override
  bool get simulado => false;

  @override
  Stream<Leitura?> atual() => db.ref('sensores/atual').onValue.map((e) {
        final v = e.snapshot.value;
        return v is Map ? Leitura.fromMap(v) : null;
      });

  @override
  Stream<List<Leitura>> historico({int limite = 600}) =>
      db.ref('historico').orderByKey().limitToLast(limite).onValue.map((e) {
        final v = e.snapshot.value;
        if (v is! Map) return <Leitura>[];
        final lista = <Leitura>[
          for (final item in v.entries)
            if (item.value is Map)
              Leitura.fromMap(item.value as Map, id: item.key.toString()),
        ];
        lista.sort((a, b) => a.momento.compareTo(b.momento));
        return lista;
      });

  @override
  Stream<Comandos> comandos() =>
      db.ref('comandos').onValue.map((e) => Comandos.fromMap(e.snapshot.value));

  @override
  Stream<bool> conectado() =>
      db.ref('.info/connected').onValue.map((e) => e.snapshot.value == true);

  @override
  Stream<String> cenario() => db
      .ref('simulacao/cenario')
      .onValue
      .map((e) => e.snapshot.value?.toString() ?? 'normal');

  @override
  Future<void> setAuto(bool v) => db.ref('comandos').update({'auto': v});

  @override
  Future<void> setMl(bool v) => db.ref('comandos').update({'ml': v});

  @override
  Future<void> irrigarManual(double segundos) =>
      db.ref('comandos').update({'manual_s': double.parse(segundos.toStringAsFixed(1))});

  @override
  Future<void> setCenario(String cenario) => db
      .ref('simulacao')
      .update({'cenario': cenario, 'alterado_em': ServerValue.timestamp});

  @override
  void dispose() {}
}
