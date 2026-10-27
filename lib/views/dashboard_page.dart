import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../controllers/explicacao.dart';
import '../controllers/formatos.dart';
import '../models/leitura.dart';
import '../services/fuzzy.dart';
import 'widgets.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final l = c.atual;
    final cs = Theme.of(context).colorScheme;

    if (l == null) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (c.erro != null)
          Aviso(icone: Icons.error_outline, texto: c.erro!, cor: cs.error, aoFechar: c.limparErro),
        SizedBox(
          height: 400,
          child: c.carregando
              ? const Carregando()
              : const Vazio(
                  icone: Icons.sensors_off,
                  texto: 'Nenhuma leitura em /sensores/atual.\n'
                      'Verifique se o ESP32 (ou o simulador Python) está enviando dados.'),
        ),
      ]);
    }

    final fz = Fuzzy.calcular(l.solo, l.temp, l.altura);
    final hoje = c.resumoHoje;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      // ---------- avisos ----------
      if (c.erro != null)
        Aviso(icone: Icons.error_outline, texto: c.erro!, cor: cs.error, aoFechar: c.limparErro),
      if (!c.dispositivoOnline)
        Aviso(
          icone: Icons.wifi_off,
          cor: cs.error,
          texto: 'ESP32 sem enviar dados ${fmtIdade(c.idadeLeitura ?? Duration.zero)}. '
              'Os valores abaixo podem estar desatualizados.',
        ),
      if (fz.soilIdx == 0)
        const Aviso(
          icone: Icons.warning_amber_rounded,
          cor: Color(0xFFD84315),
          texto: 'Solo em nível crítico: risco de estresse hídrico.',
        ),
      if (l.bloqueado)
        Aviso(icone: Icons.block, cor: const Color(0xFFB71C1C), texto: statusAmigavel(l.status)),

      // ---------- status da irrigação ----------
      _StatusCard(l: l, c: c),

      // ---------- sensores ----------
      const Secao('Sensores'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: SensorCard(
            icone: Icons.water_drop_outlined,
            titulo: 'Umidade do solo',
            valor: fmtNum(l.solo, 0),
            unidade: '%',
            rotulo: Fuzzy.soloNomes[fz.soilIdx],
            cor: coresSolo[fz.soilIdx],
            rodape: BarraSolo(solo: l.solo),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SensorCard(
            icone: Icons.thermostat,
            titulo: 'Temperatura',
            valor: fmtNum(l.temp),
            unidade: '°C',
            rotulo: Fuzzy.tempNomes[fz.tempIdx],
            cor: coresTemp[fz.tempIdx],
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: SensorCard(
            icone: Icons.cloud_outlined,
            titulo: 'Umidade do ar',
            valor: fmtNum(l.ar, 0),
            unidade: '%',
            rotulo: l.ar < 40 ? 'ar seco' : (l.ar > 80 ? 'ar úmido' : 'normal'),
            cor: const Color(0xFF00838F),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SensorCard(
            icone: Icons.grass,
            titulo: 'Altura da planta',
            valor: l.altura == null ? '--' : fmtNum(l.altura!, 0),
            unidade: 'cm',
            rotulo: fz.heightIdx < 0 ? 'sem leitura' : Fuzzy.faseNomes[fz.heightIdx],
            cor: const Color(0xFF558B2F),
          ),
        ),
      ]),

      // ---------- decisão ----------
      Secao('Última decisão da IA',
          acao: Text(fmtHora(l.momento), style: Theme.of(context).textTheme.bodySmall)),
      _DecisaoCard(l: l, kc: fz.kc),

      // ---------- resumo do dia ----------
      const Secao('Hoje'),
      Painel(
        child: Column(children: [
          Row(children: [
            _Numero(titulo: 'Água usada', valor: fmtVolume(hoje.volumeMl), icone: Icons.opacity),
            _Numero(titulo: 'Irrigações', valor: '${hoje.irrigacoes}', icone: Icons.repeat),
            _Numero(titulo: 'Bloqueios', valor: '${hoje.bloqueios}', icone: Icons.shield_outlined),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text('Bomba hoje: ${fmtNum(hoje.segundos)} de '
                  '${AppController.maxDailyPumpS.toStringAsFixed(0)} s',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (hoje.segundos / AppController.maxDailyPumpS).clamp(0, 1).toDouble(),
              minHeight: 8,
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _StatusCard extends StatelessWidget {
  final Leitura l;
  final AppController c;
  const _StatusCard({required this.l, required this.c});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final ultima = c.ultimaIrrigacao;
    final irrigando = l.irrigou;
    final cor = irrigando ? const Color(0xFF0277BD) : const Color(0xFF2E7D32);

    String titulo;
    if (irrigando) {
      titulo = 'Irrigou ${fmtNum(l.irrigadoS)} s agora';
    } else if (ultima != null) {
      titulo = 'Última irrigação às ${fmtHora(ultima.momento)}';
    } else {
      titulo = 'Nenhuma irrigação recente';
    }

    return Painel(
      cor: cor.withAlpha(18),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
          child: Icon(irrigando ? Icons.water_drop : Icons.eco, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(statusAmigavel(l.status), style: tt.bodyMedium),
            if (ultima != null && !irrigando)
              Text('${fmtNum(ultima.irrigadoS)} s · ${fmtVolume(ultima.volumeMl)}', style: tt.bodySmall),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Selo(c.comandos.auto ? 'Automático' : 'Manual',
                  cor: c.comandos.auto ? const Color(0xFF2E7D32) : const Color(0xFF6D4C41),
                  icone: c.comandos.auto ? Icons.autorenew : Icons.pan_tool_alt_outlined),
              Selo(c.comandos.ml ? 'IA ligada' : 'Só fuzzy',
                  cor: const Color(0xFF5E35B1), icone: Icons.psychology_outlined),
              if (c.idadeLeitura != null)
                Selo('Atualizado ${fmtIdade(c.idadeLeitura!)}',
                    cor: c.dispositivoOnline ? const Color(0xFF455A64) : Theme.of(context).colorScheme.error,
                    icone: Icons.schedule),
              if (l.testMode)
                const Selo('Modo teste: bomba travada', cor: Color(0xFFE65100), icone: Icons.construction_outlined),
              if (c.comandoManualPendente)
                const Selo('Comando manual pendente', cor: Color(0xFF0277BD), icone: Icons.hourglass_top),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _DecisaoCard extends StatelessWidget {
  final Leitura l;
  final double kc;
  const _DecisaoCard({required this.l, required this.kc});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final passos = explicarDecisao(l);
    return Painel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Etapa(titulo: 'Fuzzy × Kc', valor: '${fmtNum(l.fuzzyS)} s', sub: 'Kc ${fmtNum(kc, 2)}'),
          const Icon(Icons.chevron_right, size: 18),
          _Etapa(titulo: 'Rede neural', valor: '×${fmtNum(l.mlpMult, 2)}', sub: 'ajuste'),
          const Icon(Icons.chevron_right, size: 18),
          _Etapa(
            titulo: 'Decisão',
            valor: '${fmtNum(l.decisaoS)} s',
            sub: l.irrigou ? 'executada' : (l.decisaoS > 0 ? 'não executada' : 'não irrigar'),
            destaque: true,
          ),
        ]),
        const SizedBox(height: 14),
        Text('Por que o sistema decidiu isso', style: tt.labelLarge),
        const SizedBox(height: 6),
        for (final p in passos)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 5)),
              const SizedBox(width: 8),
              Expanded(child: Text(p, style: tt.bodyMedium)),
            ]),
          ),
      ]),
    );
  }
}

class _Etapa extends StatelessWidget {
  final String titulo, valor, sub;
  final bool destaque;
  const _Etapa({required this.titulo, required this.valor, required this.sub, this.destaque = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: destaque ? cs.primary : cs.primaryContainer.withAlpha(120),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text(titulo,
              style: tt.labelSmall?.copyWith(color: destaque ? cs.onPrimary : cs.onPrimaryContainer),
              textAlign: TextAlign.center),
          const SizedBox(height: 2),
          FittedBox(
            child: Text(valor,
                style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800, color: destaque ? cs.onPrimary : cs.onPrimaryContainer)),
          ),
          Text(sub,
              style: tt.labelSmall?.copyWith(
                  color: (destaque ? cs.onPrimary : cs.onPrimaryContainer).withAlpha(180)),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _Numero extends StatelessWidget {
  final String titulo, valor;
  final IconData icone;
  const _Numero({required this.titulo, required this.valor, required this.icone});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Column(children: [
        Icon(icone, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(valor, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        Text(titulo, style: tt.bodySmall),
      ]),
    );
  }
}
