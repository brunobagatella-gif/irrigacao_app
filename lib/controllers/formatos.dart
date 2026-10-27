import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String fmtNum(double v, [int casas = 1]) => v.toStringAsFixed(casas).replaceAll('.', ',');

String fmtHora(DateTime t) => DateFormat('HH:mm').format(t);
String fmtDataHora(DateTime t) => DateFormat('dd/MM HH:mm').format(t);

String fmtIdade(Duration d) {
  if (d.inSeconds < 5) return 'agora';
  if (d.inSeconds < 60) return 'há ${d.inSeconds} s';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  return 'há ${d.inDays} dia${d.inDays > 1 ? 's' : ''}';
}

String fmtVolume(double ml) =>
    ml >= 1000 ? '${fmtNum(ml / 1000, 2)} L' : '${ml.toStringAsFixed(0)} mL';

/// Traduz o campo "status" (note) do firmware para o usuário.
String statusAmigavel(String s) {
  if (s.isEmpty) return '—';
  if (s.startsWith('BLOQUEADO')) {
    final motivo = s.split(':').skip(1).join(':').trim();
    const mapa = {
      'solo muito umido': 'solo muito úmido',
      'limite diario de bomba': 'limite diário de bomba atingido',
      'intervalo minimo entre irrigacoes': 'intervalo mínimo entre irrigações',
    };
    return 'Bloqueado: ${mapa[motivo] ?? motivo}';
  }
  if (s == 'sem irrigacao') return 'Sem necessidade de irrigar';
  if (s.contains('MANUAL executada')) return 'Irrigação manual executada';
  if (s.contains('AUTOMATICA executada')) return 'Irrigação automática executada';
  if (s.startsWith('TEST_MODE')) return 'Modo teste: bomba não acionada';
  if (s.startsWith('modo manual')) return 'Automático desligado';
  return s;
}

/// Cores por conjunto de umidade do solo (crítico → encharcado).
const coresSolo = [
  Color(0xFFD84315), // crítico
  Color(0xFFF9A825), // baixo
  Color(0xFF2E7D32), // ideal
  Color(0xFF0277BD), // alto
  Color(0xFF4527A0), // encharcado
];

const coresTemp = [
  Color(0xFF1565C0),
  Color(0xFF0097A7),
  Color(0xFF2E7D32),
  Color(0xFFEF6C00),
  Color(0xFFC62828),
];

String capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
