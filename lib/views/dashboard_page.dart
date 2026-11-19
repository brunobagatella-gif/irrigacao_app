import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../controllers/explicacao.dart';
import '../controllers/formatos.dart';
import '../models/leitura.dart';
import '../services/fuzzy.dart';
import 'planta.dart';
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
    final prox = c.proximaRega;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
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

      // ---------- saúde da planta ----------
      _SaudeCard(l: l, c: c, soilIdx: fz.soilIdx),
      const SizedBox(height: 12),

      // ---------- conforto + próxima rega ----------
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: 6,
            child: Painel(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                AnelConforto(fracao: c.conforto(const Duration(hours: 24)), tamanho: 72),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Conforto hídrico',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const Text('últimas 24 h', style: TextStyle(fontSize: 11.5)),
                        _confortoPeriodo(c),
                      ]),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
            child: Painel(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Próxima rega', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(prox.titulo,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF0277BD))),
                ),
                const SizedBox(height: 2),
                Text(prox.detalhe, style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
              ]),
            ),
          ),
        ]),
      ),

      // ---------- sensores ----------
      const Secao('Sensores'),
      Row(children: [
        _Tile(
            icone: Icons.water_drop,
            valor: fmtNum(l.solo, 0),
            unidade: '%',
            rotulo: Fuzzy.soloNomes[fz.soilIdx],
            cor: coresSolo[fz.soilIdx],
            dica: 'Umidade do solo'),
        const SizedBox(width: 7),
        _Tile(
            icone: Icons.thermostat,
            valor: fmtNum(l.temp),
            unidade: '°C',
            rotulo: Fuzzy.tempNomes[fz.tempIdx],
            cor: coresTemp[fz.tempIdx],
            dica: 'Temperatura'),
        const SizedBox(width: 7),
        _Tile(
            icone: Icons.cloud,
            valor: fmtNum(l.ar, 0),
            unidade: '%',
            rotulo: l.ar < 40 ? 'ar seco' : (l.ar > 80 ? 'ar úmido' : 'normal'),
            cor: const Color(0xFF00838F),
            dica: 'Umidade do ar'),
        const SizedBox(width: 7),
        _Tile(
            icone: Icons.grass,
            valor: l.altura == null ? '--' : fmtNum(l.altura!, 0),
            unidade: 'cm',
            rotulo: fz.heightIdx < 0 ? 'sem leitura' : Fuzzy.faseNomes[fz.heightIdx].split(' ').first,
            cor: const Color(0xFF558B2F),
            dica: 'Altura da planta'),
      ]),
      const SizedBox(height: 10),
      Painel(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Faixas de umidade do solo', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          BarraSolo(solo: l.solo),
          const SizedBox(height: 4),
          const Row(children: [
            Expanded(flex: 20, child: Text('crítico', style: TextStyle(fontSize: 9.5))),
            Expanded(flex: 15, child: Text('baixo', style: TextStyle(fontSize: 9.5))),
            Expanded(flex: 27, child: Text('ideal', style: TextStyle(fontSize: 9.5))),
            Expanded(flex: 18, child: Text('alto', style: TextStyle(fontSize: 9.5))),
            Expanded(flex: 20, child: Text('encharcado', style: TextStyle(fontSize: 9.5))),
          ]),
        ]),
      ),

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

  Widget _confortoPeriodo(AppController c) {
    final f = c.conforto(null);
    final dias = c.diasCarregados;
    if (f == null || dias < 1.5) return const SizedBox.shrink();
    return Text('${dias.round()} dias: ${(f * 100).round()}%',
        style: const TextStyle(fontSize: 11.5, color: Colors.black54));
  }
}

class _SaudeCard extends StatelessWidget {
  final Leitura l;
  final AppController c;
  final int soilIdx;
  const _SaudeCard({required this.l, required this.c, required this.soilIdx});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final estado = soilIdx <= 1
        ? EstadoPlanta.murcha
        : (soilIdx == 4 ? EstadoPlanta.encharcada : EstadoPlanta.saudavel);
    final (titulo, cor) = switch (soilIdx) {
      0 => ('Com muita sede', const Color(0xFFD84315)),
      1 => ('Com sede', const Color(0xFFB07A00)),
      2 => ('Confortável', const Color(0xFF1B5E20)),
      3 => ('Bem hidratada', const Color(0xFF0277BD)),
      _ => ('Encharcada', const Color(0xFF4527A0)),
    };
    final tend = c.tendenciaSolo;
    String desc = switch (soilIdx) {
      0 => 'O solo está muito seco. O sistema prioriza uma irrigação longa.',
      1 => 'O solo está abaixo do ideal; a próxima rega vai repor a umidade.',
      2 => 'O solo está na faixa ideal para o feijoeiro.',
      3 => 'O solo está acima do ideal; o sistema evita irrigar agora.',
      _ => 'Excesso de água: risco para as raízes. As regas estão bloqueadas.',
    };
    if (tend != null && tend < -0.8) {
      desc += ' Está secando rápido (${fmtNum(-tend)} %/h).';
    } else if (tend != null && tend > 0.8) {
      desc += ' A umidade está subindo.';
    }
    final ultima = c.ultimaIrrigacao;

    return Painel(
      cor: const Color(0xFFEDF6E7),
      padding: const EdgeInsets.fromLTRB(8, 10, 14, 12),
      child: Row(children: [
        PlantaIlustracao(estado: estado, regando: l.irrigou, largura: 100),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Saúde da planta', style: tt.bodySmall),
            Text(titulo, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cor)),
            const SizedBox(height: 2),
            Text(desc, style: tt.bodySmall?.copyWith(fontSize: 12.5, color: Colors.black87)),
            const SizedBox(height: 6),
            if (l.irrigou)
              Text('Irrigou ${fmtNum(l.irrigadoS)} s agora',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0277BD), fontSize: 12.5))
            else if (ultima != null)
              Text('Última rega: ${fmtHora(ultima.momento)} · ${fmtNum(ultima.irrigadoS)} s',
                  style: tt.bodySmall),
            const SizedBox(height: 6),
            Wrap(spacing: 5, runSpacing: 5, children: [
              Selo(c.comandos.auto ? 'Automático' : 'Manual',
                  cor: c.comandos.auto ? const Color(0xFF2E7D32) : const Color(0xFF6D4C41),
                  icone: c.comandos.auto ? Icons.autorenew : Icons.pan_tool_alt_outlined),
              Selo(c.comandos.ml ? 'IA ligada' : 'Só fuzzy',
                  cor: const Color(0xFF5E35B1), icone: Icons.psychology_outlined),
              if (c.idadeLeitura != null)
                Selo(fmtIdade(c.idadeLeitura!),
                    cor: c.dispositivoOnline ? const Color(0xFF455A64) : Theme.of(context).colorScheme.error,
                    icone: Icons.schedule),
              if (c.comandoManualPendente)
                const Selo('Rega manual pendente', cor: Color(0xFF0277BD), icone: Icons.hourglass_top),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icone;
  final String valor, unidade, rotulo, dica;
  final Color cor;
  const _Tile({
    required this.icone,
    required this.valor,
    required this.unidade,
    required this.rotulo,
    required this.cor,
    required this.dica,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Tooltip(
          message: dica,
          child: Painel(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: cor.withAlpha(30), borderRadius: BorderRadius.circular(10)),
                child: Icon(icone, color: cor, size: 17),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(valor, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(unidade, style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
                ]),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(rotulo, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: cor)),
              ),
            ]),
          ),
        ),
      );
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
