import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../controllers/formatos.dart';
import 'widgets.dart';

class ControlePage extends StatefulWidget {
  const ControlePage({super.key});

  @override
  State<ControlePage> createState() => _ControlePageState();
}

class _ControlePageState extends State<ControlePage> {
  double _segundos = 5;

  static const _cenarios = [
    ('normal', 'Normal', Icons.wb_sunny_outlined),
    ('calor', 'Onda de calor', Icons.local_fire_department_outlined),
    ('chuva', 'Chuva', Icons.grain),
    ('inverno', 'Inverno', Icons.ac_unit),
    ('estresse', 'Estresse hídrico', Icons.water_drop_outlined),
  ];

  Future<void> _confirmarManual(AppController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.water_drop),
        title: const Text('Irrigar agora?'),
        content: Text('A bomba vai ligar por ${fmtNum(_segundos)} s '
            '(≈ ${fmtVolume(_segundos * c.vazaoMlS)}).\n\n'
            'O ESP32 executa no próximo ciclo de leitura e ainda aplica as travas de segurança.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Irrigar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await c.irrigarManual(_segundos);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Comando enviado. Aguardando o ESP32 executar...'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final solo = c.atual?.solo;
    final vaiBloquear = solo != null && solo >= AppController.hardStopSolo;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      // ---------- modo ----------
      const Secao('Modo de operação'),
      Painel(
        padding: EdgeInsets.zero,
        child: Column(children: [
          SwitchListTile(
            secondary: const Icon(Icons.autorenew),
            title: const Text('Irrigação automática'),
            subtitle: const Text('O sistema decide sozinho quando e quanto irrigar'),
            value: c.comandos.auto,
            onChanged: c.setAuto,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.psychology_outlined),
            title: const Text('Ajuste pela rede neural'),
            subtitle: const Text('Desligado, o sistema usa só a lógica fuzzy'),
            value: c.comandos.ml,
            onChanged: c.setMl,
          ),
        ]),
      ),
      if (c.mlpPareceSemPesos)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Aviso(
            icone: Icons.info_outline,
            cor: const Color(0xFF5E35B1),
            texto: 'O multiplicador da rede está sempre em ×1,00: parece que o firmware ainda está '
                'sem pesos treinados (mlp_weights.h).',
          ),
        ),

      // ---------- manual ----------
      const Secao('Irrigação manual'),
      Painel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${fmtNum(_segundos)} s', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('≈ ${fmtVolume(_segundos * c.vazaoMlS)}', style: tt.titleSmall),
          ]),
          Slider(
            value: _segundos,
            min: 1,
            max: AppController.maxPumpS,
            divisions: 28,
            label: '${fmtNum(_segundos)} s',
            onChanged: (v) => setState(() => _segundos = v),
          ),
          if (vaiBloquear)
            Aviso(
              icone: Icons.block,
              cor: cs.error,
              texto: 'Solo acima de ${AppController.hardStopSolo.toStringAsFixed(0)} %: o firmware vai bloquear.',
            ),
          if (c.comandoManualPendente)
            Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Aguardando o ESP32 (${fmtNum(c.comandos.manualS)} s pedidos)...',
                    style: tt.bodyMedium),
              ),
            ])
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: c.atual == null ? null : () => _confirmarManual(c),
                icon: const Icon(Icons.water_drop),
                label: const Text('Irrigar agora'),
              ),
            ),
          if (c.atual != null) ...[
            const SizedBox(height: 8),
            Text('Último resultado: ${statusAmigavel(c.atual!.status)}', style: tt.bodySmall),
          ],
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
          _Trava(
            Icons.construction_outlined,
            'TEST_MODE',
            c.atual == null ? '—' : (c.atual!.testMode ? 'ativo (bomba travada)' : 'desligado'),
          ),
        ]),
      ),

      // ---------- cenários ----------
      const Secao('Cenários climáticos'),
      Painel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            c.simulado
                ? 'Muda o clima do cultivo virtual na hora. Veja a resposta do sistema no Início e no Histórico.'
                : 'Grava /simulacao/cenario no Firebase para o simulador Python. Não afeta o ESP32 real.',
            style: tt.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (id, nome, ic) in _cenarios)
              ChoiceChip(
                avatar: Icon(ic, size: 18),
                label: Text(nome),
                selected: c.cenario == id,
                onSelected: (_) => c.setCenario(id),
              ),
          ]),
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
