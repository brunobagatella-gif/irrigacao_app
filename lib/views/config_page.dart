import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../controllers/formatos.dart';
import 'widgets.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  late final TextEditingController _url;
  late final TextEditingController _vazao;

  @override
  void initState() {
    super.initState();
    final c = context.read<AppController>();
    _url = TextEditingController(text: c.dbUrl);
    _vazao = TextEditingController(text: fmtNum(c.vazaoMlS));
  }

  @override
  void dispose() {
    _url.dispose();
    _vazao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        const Secao('Fonte de dados'),
        Painel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            RadioListTile<bool>(
              value: false,
              groupValue: c.simulado,
              onChanged: c.firebaseDisponivel ? (_) => c.setUsarDemo(false) : null,
              title: const Text('Firebase (ESP32 ou simulador Python)'),
              subtitle: Text(c.firebaseDisponivel
                  ? (c.conectado && !c.simulado ? 'Conectado ao Realtime Database' : 'Dados reais em tempo real')
                  : 'Indisponível: rode "flutterfire configure"'),
            ),
            const Divider(height: 1),
            RadioListTile<bool>(
              value: true,
              groupValue: c.simulado,
              onChanged: (_) => c.setUsarDemo(true),
              title: const Text('Demonstração local'),
              subtitle: const Text('Cultivo virtual, sem hardware nem internet'),
            ),
          ]),
        ),
        const Secao('Firebase'),
        Painel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'URL do Realtime Database (opcional)',
                hintText: 'meu-projeto-default-rtdb.firebaseio.com',
                helperText: 'O mesmo FIREBASE_HOST do secrets.h. Vazio = usa o do firebase_options.dart',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              onSubmitted: c.setDbUrl,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => c.setDbUrl(_url.text), child: const Text('Aplicar')),
            ),
          ]),
        ),
        const Secao('Parâmetros'),
        Painel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Considerar ESP32 offline após ${c.offlineS} s sem dados', style: tt.bodyMedium),
            Slider(
              value: c.offlineS.toDouble(),
              min: 30,
              max: 900,
              divisions: 29,
              label: '${c.offlineS} s',
              onChanged: (v) => c.setOfflineS(v.round()),
            ),
            Text('Use ~3× o CLOUD_PUSH_MS do firmware (30 s em teste → 90 s; 5 min no final → 900 s).',
                style: tt.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _vazao,
              decoration: const InputDecoration(
                labelText: 'Vazão da bomba (mL/s)',
                helperText: 'Usado nas estimativas de volume da irrigação manual (PUMP_FLOW_ML_S)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (t) {
                final v = double.tryParse(t.replaceAll(',', '.'));
                if (v != null && v > 0) c.setVazao(v);
              },
            ),
            const SizedBox(height: 16),
            Text('Registros de histórico carregados: ${c.limiteHistorico}', style: tt.bodyMedium),
            Slider(
              value: c.limiteHistorico.toDouble(),
              min: 200,
              max: 3000,
              divisions: 14,
              label: '${c.limiteHistorico}',
              onChanged: (v) => c.setLimiteHistorico(v.round()),
            ),
            Text('24 h = 288 registros a cada 5 min, ou 2880 a cada 30 s.', style: tt.bodySmall),
          ]),
        ),
        const Secao('Sobre'),
        Painel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Irrigação Inteligente · v1.0', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('TCC de Engenharia da Computação · Facens\n'
                'ESP32 + Fuzzy Mamdani + MLP 25-20-15-10-1 + Firebase',
                style: tt.bodySmall),
          ]),
        ),
      ]),
    );
  }
}
