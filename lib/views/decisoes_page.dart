import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../controllers/explicacao.dart';
import '../controllers/formatos.dart';
import '../models/leitura.dart';
import 'widgets.dart';

enum _Filtro { todas, automaticas, manuais }

/// Irrigações executadas no ciclo, com justificativa em linguagem natural (relatório, 7.6).
class DecisoesPage extends StatefulWidget {
  const DecisoesPage({super.key});

  @override
  State<DecisoesPage> createState() => _DecisoesPageState();
}

class _DecisoesPageState extends State<DecisoesPage> {
  _Filtro _filtro = _Filtro.todas;

  bool _passa(Leitura l) => switch (_filtro) {
        _Filtro.todas => true,
        _Filtro.automaticas => !l.manual,
        _Filtro.manuais => l.manual,
      };

  /// Todas as irrigações executadas: as do ciclo inteiro e as que chegaram no histórico recente.
  List<Leitura> _irrigacoes(AppController c) {
    final porChave = <String, Leitura>{};
    for (final l in [...c.irrigacoes, ...c.historico]) {
      if (!l.irrigou || l.emTeste || l.testMode) continue;
      porChave[l.id ?? '${l.momento.millisecondsSinceEpoch}'] = l;
    }
    final lista = porChave.values.toList()..sort((a, b) => b.momento.compareTo(a.momento));
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final itens = _irrigacoes(c).where(_passa).take(300).toList();

    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          for (final (f, nome) in const [
            (_Filtro.todas, 'Todas as irrigações'),
            (_Filtro.automaticas, 'Automáticas'),
            (_Filtro.manuais, 'Manuais'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(nome),
                selected: _filtro == f,
                onSelected: (_) => setState(() => _filtro = f),
              ),
            ),
        ]),
      ),
      Expanded(
        child: itens.isEmpty
            ? const Vazio(icone: Icons.water_drop_outlined, texto: 'Nenhuma irrigação neste filtro.')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: itens.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _ItemDecisao(l: itens[i]),
              ),
      ),
    ]);
  }
}

class _ItemDecisao extends StatelessWidget {
  final Leitura l;
  const _ItemDecisao({required this.l});

  (IconData, Color) get _icone => l.manual
      ? (Icons.pan_tool_alt_outlined, const Color(0xFF6D4C41))
      : (Icons.water_drop, const Color(0xFF0277BD));

  String get _titulo => l.manual ? 'Irrigação manual executada' : 'Irrigação automática executada';

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final (ic, cor) = _icone;
    return Painel(
      padding: const EdgeInsets.all(12),
      onTap: () => _detalhes(context),
      child: Row(children: [
        CircleAvatar(radius: 18, backgroundColor: cor.withAlpha(30), child: Icon(ic, color: cor, size: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_titulo, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Solo ${fmtNum(l.solo, 0)} % · ${fmtNum(l.temp)} °C · fuzzy ${fmtNum(l.fuzzyS)} s · '
                'MLP ×${fmtNum(l.mlpMult, 2)}',
                style: tt.bodySmall),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(l.irrigou ? '${fmtNum(l.irrigadoS)} s' : (l.decisaoS > 0 ? '${fmtNum(l.decisaoS)} s' : '—'),
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cor)),
          Text(fmtDataHora(l.momento), style: tt.labelSmall),
        ]),
      ]),
    );
  }

  void _detalhes(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        maxChildSize: .92,
        builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Text(_titulo, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(fmtDataHora(l.momento), style: tt.bodySmall),
          const SizedBox(height: 16),
          Text('Raciocínio', style: tt.labelLarge),
          const SizedBox(height: 6),
          for (final (i, p) in explicarDecisao(l).indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 10, child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                const SizedBox(width: 10),
                Expanded(child: Text(p)),
              ]),
            ),
          const SizedBox(height: 12),
          Text('Dados do ciclo', style: tt.labelLarge),
          const SizedBox(height: 6),
          _linha('Umidade do solo', '${fmtNum(l.solo)} % (ADC ${l.raw})'),
          _linha('Temperatura', '${fmtNum(l.temp)} °C'),
          _linha('Umidade do ar', '${fmtNum(l.ar)} %'),
          _linha('Altura', l.altura == null ? 'sem leitura' : '${fmtNum(l.altura!)} cm'),
          _linha('Saída fuzzy (com Kc)', '${fmtNum(l.fuzzyS, 2)} s'),
          _linha('Multiplicador MLP', '×${fmtNum(l.mlpMult, 2)}'),
          _linha('Decisão', '${fmtNum(l.decisaoS, 2)} s'),
          _linha('Irrigado', '${fmtNum(l.irrigadoS, 2)} s · ${fmtVolume(l.volumeMl)}'),
          _linha('Modo', l.manual ? 'manual' : 'automático'),
          const SizedBox(height: 12),
          Text('Texto do firmware', style: tt.labelLarge),
          const SizedBox(height: 4),
          SelectableText('${l.motivo}\n${l.status}', style: tt.bodySmall?.copyWith(fontFamily: 'monospace')),
        ]),
      ),
    );
  }

  Widget _linha(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a)),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}
