enum TipoAlerta { perigo, aviso, info }

/// Evento detectado no histórico (solo crítico, bloqueio, ESP32 offline...).
class Alerta {
  final DateTime momento;
  final TipoAlerta tipo;
  final String titulo;
  final String detalhe;
  const Alerta(this.momento, this.tipo, this.titulo, this.detalhe);
}
