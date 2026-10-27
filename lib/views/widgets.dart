import 'package:flutter/material.dart';

import '../controllers/formatos.dart';

/// Card padrão do app (borda fina, sem sombra).
class Painel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? cor;
  final VoidCallback? onTap;
  const Painel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.cor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final claro = Theme.of(context).brightness == Brightness.light;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: cor ?? (claro ? Colors.white : cs.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Título de seção usado nas telas.
class Secao extends StatelessWidget {
  final String texto;
  final Widget? acao;
  const Secao(this.texto, {super.key, this.acao});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(
            child: Text(texto,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: .2)),
          ),
          if (acao != null) acao!,
        ]),
      );
}

/// Faixa de aviso (offline, solo crítico, bloqueio, erro...).
class Aviso extends StatelessWidget {
  final IconData icone;
  final String texto;
  final Color cor;
  final VoidCallback? aoFechar;
  const Aviso({super.key, required this.icone, required this.texto, required this.cor, this.aoFechar});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cor.withAlpha(28),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cor.withAlpha(90)),
        ),
        child: Row(children: [
          Icon(icone, color: cor, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.w600))),
          if (aoFechar != null)
            InkWell(onTap: aoFechar, child: Icon(Icons.close, size: 18, color: cor)),
        ]),
      );
}

/// Selo pequeno colorido.
class Selo extends StatelessWidget {
  final String texto;
  final Color cor;
  final IconData? icone;
  const Selo(this.texto, {super.key, required this.cor, this.icone});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: cor.withAlpha(30), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icone != null) ...[Icon(icone, size: 13, color: cor), const SizedBox(width: 4)],
          Text(texto, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Card de sensor do dashboard.
class SensorCard extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String valor;
  final String unidade;
  final String? rotulo;
  final Color cor;
  final Widget? rodape;
  const SensorCard({
    super.key,
    required this.icone,
    required this.titulo,
    required this.valor,
    required this.unidade,
    required this.cor,
    this.rotulo,
    this.rodape,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Painel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: cor.withAlpha(30), borderRadius: BorderRadius.circular(10)),
              child: Icon(icone, color: cor, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(titulo, style: tt.labelLarge, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(valor, style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 3),
            Text(unidade, style: tt.titleSmall?.copyWith(color: tt.bodySmall?.color)),
          ]),
          if (rotulo != null) ...[
            const SizedBox(height: 4),
            Selo(capitalizar(rotulo!), cor: cor),
          ],
          if (rodape != null) ...[const SizedBox(height: 10), rodape!],
        ]),
    );
  }
}

/// Barra horizontal com as faixas fuzzy de umidade do solo e o marcador da leitura atual.
class BarraSolo extends StatelessWidget {
  final double solo;
  const BarraSolo({super.key, required this.solo});

  // limites aproximados (cruzamentos dos trapézios)
  static const _faixas = [20, 15, 27, 18, 20]; // 0-20, 20-35, 35-62, 62-80, 80-100

  @override
  Widget build(BuildContext context) {
    final x = (solo.clamp(0, 100) / 100) * 2 - 1;
    return SizedBox(
      height: 16,
      child: Stack(alignment: Alignment.center, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(children: [
            for (var i = 0; i < 5; i++)
              Expanded(flex: _faixas[i], child: Container(height: 6, color: coresSolo[i].withAlpha(150))),
          ]),
        ),
        Align(
          alignment: Alignment(x.toDouble(), 0),
          child: Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ]),
    );
  }
}

class Carregando extends StatelessWidget {
  final String texto;
  const Carregando({super.key, this.texto = 'Aguardando dados do ESP32...'});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(texto, textAlign: TextAlign.center),
          ]),
        ),
      );
}

class Vazio extends StatelessWidget {
  final IconData icone;
  final String texto;
  const Vazio({super.key, required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icone, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center),
          ]),
        ),
      );
}
