import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../controllers/formatos.dart';
import '../services/cultivo.dart';
import '../services/data_source.dart';
import '../services/fuzzy.dart';
import 'widgets.dart';

const _coresFase = [
  Color(0xFFA1887F), // germinação
  Color(0xFF9CCC65), // vegetativo inicial
  Color(0xFF66BB6A), // vegetativo avançado
  Color(0xFFF06292), // floração
  Color(0xFFFFB300), // produção
];

/// Pede a data do plantio e grava em /config (vale para todos os aparelhos).
Future<void> escolherPlantio(BuildContext context, AppController c) async {
  final ultimo = DateTime.now().add(const Duration(days: 1));
  var atual = c.config.plantio ?? c.agora.subtract(const Duration(days: 30));
  if (atual.isAfter(ultimo)) atual = ultimo;
  if (atual.isBefore(DateTime(2024))) atual = DateTime(2024);
  final d = await showDatePicker(
    context: context,
    initialDate: atual,
    firstDate: DateTime(2024),
    lastDate: ultimo,
    helpText: 'Data do plantio',
    cancelText: 'Cancelar',
    confirmText: 'Salvar',
  );
  if (d == null) return;
  await c.setConfig(c.config.copyWith(
      plantioEpoch: DateTime(d.year, d.month, d.day, 8).millisecondsSinceEpoch ~/ 1000));
}

class CultivoPage extends StatelessWidget {
  const CultivoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final tt = Theme.of(context).textTheme;
    final dia = c.diaCiclo;
    final plantio = c.config.plantio;

    if (dia == null || plantio == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.local_florist, size: 56, color: Color(0xFF66BB6A)),
            const SizedBox(height: 12),
            Text('Quando o feijoeiro foi plantado?', style: tt.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            const Text('Com a data do plantio o app acompanha o ciclo, as fases e o crescimento esperado.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => escolherPlantio(context, c),
              icon: const Icon(Icons.event),
              label: const Text('Definir data do plantio'),
            ),
          ]),
        ),
      );
    }

    if (c.alturas == null && !c.carregandoAlturas) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.carregarAlturas());
    }

    final fi = Cultivo.faseIdx(dia);
    final fase = Cultivo.fases[fi];
    final diaInt = dia.floor();
    final faltam = math.max(0, fase.fim - diaInt);
    final manuais = [for (final a in c.alturas ?? const <AlturaDia>[]) if (a.manual) a];
    final alt = manuais.isNotEmpty ? manuais.last.altura : c.atual?.altura;
    final esperado = Cultivo.alturaEsperada(dia);
    final fzAlt = alt == null ? null : Fuzzy.calcular(50, 25, alt).heightIdx;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Painel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Feijoeiro · plantado em ${fmtData(plantio)}', style: tt.bodySmall),
                Text(diaInt >= Cultivo.cicloDias ? 'Ciclo concluído (dia $diaInt)' : 'Dia $diaInt de ${Cultivo.cicloDias}',
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ]),
            ),
            Selo(fase.nome, cor: _coresFase[fi]),
            IconButton(
              tooltip: 'Alterar data do plantio',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_calendar_outlined, size: 20),
              onPressed: () => escolherPlantio(context, c),
            ),
          ]),
          const SizedBox(height: 12),
          _LinhaDoTempo(dia: dia),
          const SizedBox(height: 14),
          Row(children: [
            _Mini('Kc da fase', fmtNum(fase.kc, 2)),
            _Mini('Altura', alt == null ? '--' : '${fmtNum(alt, 0)} cm'),
            _Mini(fi == Cultivo.fases.length - 1 ? 'até a colheita' : 'até ${Cultivo.fases[fi + 1].nome.toLowerCase()}',
                '$faltam dias'),
          ]),
        ]),
      ),
      if (fzAlt != null && fzAlt >= 0 && fzAlt != fi)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Aviso(
            icone: Icons.info_outline,
            cor: const Color(0xFF5E35B1),
            texto: 'Pela altura medida, a planta parece estar em "${Fuzzy.faseNomes[fzAlt]}", '
                'e pelo calendário em "${fase.nome.toLowerCase()}". O Kc usado pelo firmware vem da altura.',
          ),
        ),
      Secao('Crescimento real × esperado',
          acao: IconButton(
            tooltip: 'Recarregar',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => c.carregarAlturas(forcar: true),
          )),
      Painel(
        padding: const EdgeInsets.fromLTRB(4, 16, 16, 4),
        child: SizedBox(height: 200, child: _GraficoCrescimento(dia: dia)),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Wrap(spacing: 14, children: const [
          _Leg('Medido', Color(0xFF2E7D32)),
          _Leg('Curva do relatório', Color(0xFF9CCC65)),
          _Leg('Hoje', Color(0xFFF06292)),
        ]),
      ),
      if (alt != null) ...[
        const SizedBox(height: 10),
        Painel(
          cor: const Color(0xFFF1F8EC),
          child: Text(_comparacao(alt, esperado, fase.kc), style: const TextStyle(fontSize: 13)),
        ),
      ],
      const Secao('Fases do feijoeiro'),
      Painel(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (var i = 0; i < Cultivo.fases.length; i++)
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 7, backgroundColor: _coresFase[i]),
              title: Text(Cultivo.fases[i].nome,
                  style: TextStyle(fontWeight: i == fi ? FontWeight.w800 : FontWeight.w500)),
              subtitle: Text('dias ${Cultivo.fases[i].inicio}–${Cultivo.fases[i].fim}'),
              trailing: Text('Kc ${fmtNum(Cultivo.fases[i].kc, 2)}'),
              selected: i == fi,
            ),
        ]),
      ),
    ]);
  }

  static String _comparacao(double alt, double esperado, double kc) {
    if (esperado < 1) return 'Planta ainda em germinação: a altura esperada é quase zero.';
    final dif = (alt / esperado - 1) * 100;
    final txt = dif.abs() < 10
        ? 'dentro do normal'
        : (dif > 0 ? 'acima do esperado' : 'abaixo do esperado: vale observar estresse hídrico ou térmico');
    return 'Altura ${fmtNum(alt, 0)} cm contra ${fmtNum(esperado, 0)} cm esperados '
        '(${dif >= 0 ? '+' : ''}${dif.round()} %): $txt. Nesta fase o Kc é ${fmtNum(kc, 2)}.';
  }
}

class _LinhaDoTempo extends StatelessWidget {
  final double dia;
  const _LinhaDoTempo({required this.dia});

  static const _curtos = ['Germ.', 'Veg. ini.', 'Veg. av.', 'Floração', 'Produção'];

  @override
  Widget build(BuildContext context) {
    final pos = (dia / Cultivo.cicloDias).clamp(0, 1).toDouble();
    return Column(children: [
      SizedBox(
        height: 20,
        child: Stack(alignment: Alignment.center, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(children: [
              for (var i = 0; i < Cultivo.fases.length; i++)
                Expanded(
                  flex: Cultivo.fases[i].fim - Cultivo.fases[i].inicio,
                  child: Container(height: 12, color: _coresFase[i].withAlpha(215)),
                ),
            ]),
          ),
          Align(
            alignment: Alignment(pos * 2 - 1, 0),
            child: Container(
              width: 5,
              height: 20,
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [
        for (var i = 0; i < Cultivo.fases.length; i++)
          Expanded(
            flex: Cultivo.fases[i].fim - Cultivo.fases[i].inicio,
            child: Text(_curtos[i],
                textAlign: TextAlign.center,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: const TextStyle(fontSize: 9.5, color: Colors.black54)),
          ),
      ]),
    ]);
  }
}

class _GraficoCrescimento extends StatelessWidget {
  final double dia;
  const _GraficoCrescimento({required this.dia});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final cs = Theme.of(context).colorScheme;
    final plantio = c.config.plantio!;
    final estilo = TextStyle(fontSize: 10, color: cs.onSurface.withAlpha(150));

    final esperado = [for (var d = 0; d <= Cultivo.cicloDias; d += 2) FlSpot(d.toDouble(), Cultivo.alturaEsperada(d.toDouble()))];
    final lista = c.alturas ?? const <AlturaDia>[];
    final reais = [
      for (final a in lista) FlSpot(a.dia.difference(plantio).inHours / 24, a.altura),
    ]..sort((a, b) => a.x.compareTo(b.x));
    final xsReais = {for (final r in reais) r.x};
    // Entre duas medições com régua, a linha segue o formato da curva de crescimento do feijoeiro,
    // dia a dia, passando exatamente pelos valores medidos (os pontos marcam as medições).
    final manual = lista.isNotEmpty && lista.every((a) => a.manual);
    final medidos = <FlSpot>[];
    if (manual && reais.length >= 2) {
      for (var i = 0; i < reais.length - 1; i++) {
        final a = reais[i], b = reais[i + 1];
        final ea = Cultivo.alturaEsperada(a.x), eb = Cultivo.alturaEsperada(b.x);
        for (var d = a.x; d < b.x - 0.01; d += 1) {
          final f = (eb - ea).abs() < 1e-6
              ? (d - a.x) / (b.x - a.x)
              : (Cultivo.alturaEsperada(d) - ea) / (eb - ea);
          medidos.add(FlSpot(d, a.y + (b.y - a.y) * f));
        }
      }
      medidos.add(reais.last);
    } else {
      medidos.addAll(reais);
    }
    final maxY = math.max(65.0, medidos.isEmpty ? 0.0 : medidos.map((e) => e.y).reduce(math.max) + 5);

    if (c.carregandoAlturas && medidos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return LineChart(LineChartData(
      minX: 0,
      maxX: Cultivo.cicloDias.toDouble(),
      minY: 0,
      maxY: maxY,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: 20,
        getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant, strokeWidth: 0.6),
      ),
      extraLinesData: ExtraLinesData(verticalLines: [
        VerticalLine(x: dia.clamp(0, Cultivo.cicloDias).toDouble(), color: const Color(0xFFF06292), strokeWidth: 1.4, dashArray: [4, 4]),
      ]),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 20,
            getTitlesWidget: (v, meta) => Text('${v.toInt()}', style: estilo),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: 15,
            getTitlesWidget: (v, meta) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('dia ${v.toInt()}', style: estilo),
            ),
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots
              .map((s) => s.barIndex == 1 && !xsReais.contains(s.x)
                  ? null
                  : LineTooltipItem('dia ${s.x.toStringAsFixed(0)}\n${fmtNum(s.y, 1)} cm',
                      const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))
              .toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: esperado,
          isCurved: true,
          color: const Color(0xFF9CCC65),
          barWidth: 2,
          dashArray: [6, 4],
          dotData: FlDotData(show: false),
        ),
        if (medidos.isNotEmpty)
          LineChartBarData(
            spots: medidos,
            isCurved: true,
            preventCurveOverShooting: true,
            color: const Color(0xFF2E7D32),
            barWidth: 2.6,
            belowBarData: BarAreaData(show: true, color: const Color(0x1A2E7D32)),
            dotData: FlDotData(
              checkToShowDot: (spot, bar) => xsReais.contains(spot.x),
              getDotPainter: (spot, p, bar, i) =>
                  FlDotCirclePainter(radius: 2.6, color: const Color(0xFF2E7D32), strokeWidth: 0),
            ),
          ),
      ],
    ));
  }
}

class _Mini extends StatelessWidget {
  final String titulo, valor;
  const _Mini(this.titulo, this.valor);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Column(children: [
        Text(valor, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        Text(titulo, style: tt.bodySmall, textAlign: TextAlign.center),
      ]),
    );
  }
}

class _Leg extends StatelessWidget {
  final String nome;
  final Color cor;
  const _Leg(this.nome, this.cor);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(nome, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
