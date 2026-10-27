import '../models/comandos.dart';
import '../models/leitura.dart';

/// Camada de modelo: de onde vêm os dados.
/// FirebaseDataSource = ESP32 real (ou simulador Python) via Realtime Database.
/// DemoDataSource = cultivo virtual local, para apresentar sem hardware.
abstract class DataSource {
  bool get simulado;

  Stream<Leitura?> atual();
  Stream<List<Leitura>> historico({int limite = 600});
  Stream<Comandos> comandos();
  Stream<bool> conectado();
  Stream<String> cenario();

  Future<void> setAuto(bool v);
  Future<void> setMl(bool v);
  Future<void> irrigarManual(double segundos);
  Future<void> setCenario(String cenario);

  void dispose();
}
