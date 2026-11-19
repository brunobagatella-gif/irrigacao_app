import '../models/comandos.dart';
import '../models/config_cultivo.dart';
import '../models/leitura.dart';

/// Altura medida num dia do ciclo (para o gráfico real × esperado).
class AlturaDia {
  final DateTime dia;
  final double altura;
  final bool manual; // medição com régua (/config/medicoes_altura)
  const AlturaDia(this.dia, this.altura, {this.manual = false});
}

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
  Stream<ConfigCultivo> config();

  /// Todos os registros do histórico em que a bomba realmente ligou (ciclo inteiro).
  Stream<List<Leitura>> irrigacoes();

  /// Uma leitura de altura por dia, de [inicio] até [fim].
  Future<List<AlturaDia>> alturaDiaria(DateTime inicio, DateTime fim);

  Future<void> setAuto(bool v);
  Future<void> setMl(bool v);
  Future<void> irrigarManual(double segundos);
  Future<void> setCenario(String cenario);
  Future<void> setConfig(ConfigCultivo c);

  void dispose();
}
