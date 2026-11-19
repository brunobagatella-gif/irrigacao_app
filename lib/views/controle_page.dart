import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import 'widgets.dart';

class ControlePage extends StatelessWidget {
  const ControlePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      // ---------- modo ----------
      const Secao('Modo de operação'),
      Painel(
        padding: EdgeInsets.zero,
        child: Column(children: [
          SwitchListTile(
            secondary: const Icon(Icons.autorenew),
            title: const Text('Irrigação automática'),
            subtitle: Text(c.comandos.auto
                ? 'Ligada: o sistema decide sozinho quando e quanto irrigar'
                : 'Desligada: o sistema não irriga sozinho'),
            value: c.comandos.auto,
            onChanged: c.setAuto,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.psychology_outlined),
            title: const Text('Ajuste pela rede neural'),
            subtitle: Text(c.comandos.ml
                ? 'Ligado: a rede ajusta o tempo do fuzzy (×0,5 a ×1,5)'
                : 'Desligado: o sistema usa só a lógica fuzzy'),
            value: c.comandos.ml,
            onChanged: c.setMl,
          ),
        ]),
      ),

      // ---------- travas ----------
      const Secao('Travas de segurança (firmware)'),
      Painel(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          _Trava(Icons.water, 'Solo ≥ ${AppController.hardStopSolo.toStringAsFixed(0)} %', 'nunca irriga'),
          _Trava(Icons.timer_outlined, 'Máx. ${AppController.maxPumpS.toStringAsFixed(0)} s', 'por irrigação'),
          _Trava(Icons.today_outlined, 'Máx. ${AppController.maxDailyPumpS.toStringAsFixed(0)} s', 'de bomba em 24 h'),
          _Trava(Icons.hourglass_bottom, '${AppController.minIntervalMin} min', 'entre irrigações automáticas'),
        ]),
      ),
    ]);
  }
}

class _Trava extends StatelessWidget {
  final IconData icone;
  final String titulo, sub;
  const _Trava(this.icone, this.titulo, this.sub);

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(icone, size: 20),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Text(sub),
      );
}
