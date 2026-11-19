# Minha Horta: app de irrigação inteligente (Flutter)

App do TCC (Facens) que mostra, explica e controla o sistema ESP32 + Fuzzy Mamdani + MLP via Firebase Realtime Database.

## Telas

| Aba | O que mostra |
|---|---|
| **Início** | Saúde da planta (ilustração do feijoeiro que muda com o solo), conforto hídrico das últimas 24 h (meta de 90 % do relatório), próxima rega estimada, sensores, a última decisão da IA explicada e o resumo do dia. |
| **Histórico** | Economia de água contra um temporizador fixo (ciclo e últimos 7 dias) e gráficos de 6/12/24 h de solo (com projeção), temperatura, umidade do ar e altura. |
| **Cultivo** | Dia do ciclo, fase do feijoeiro e Kc, linha do tempo das fases e o gráfico de crescimento real (HC-SR04) contra a curva logística do relatório. |
| **Decisões** | Log da IA filtrável, com o raciocínio passo a passo de cada decisão. |
| **Controle** | Automático, rede neural, irrigação manual, travas de segurança e cenários climáticos. |
| **Sininho** | Alertas detectados no histórico: solo crítico, limite diário, calor, ESP32 offline, regas manuais. |
| **Configurações** | Fonte de dados, data do plantio, temporizador de referência da economia, URL do banco e parâmetros. |

A data do plantio e o temporizador de referência ficam em `/config` no Firebase, então valem para o celular e o site ao mesmo tempo.

### Como as métricas são calculadas
- **Conforto hídrico:** porcentagem das leituras com o solo entre 35 % e 62 % (miolo do conjunto fuzzy "ideal").
- **Próxima rega:** regressão linear da umidade nas últimas 4 h; mostra quando o solo deve chegar a 35 %.
- **Economia:** soma do volume irrigado por dia (`/historico` com `irrigado_s > 0`) contra `regas × segundos × vazão` do temporizador fixo, só em dias completos. Pode dar negativo: aí o sistema gastou mais que o temporizador.
- **Crescimento:** uma leitura de altura por dia (meio-dia), buscada por chave do Firebase sem baixar o histórico inteiro.

## Arquitetura (MVC simplificado, como no relatório 7.6)

```
lib/
  models/       Leitura (JSON do pushCloud), Comandos (/comandos), parse
  services/     DataSource → FirebaseDataSource | DemoDataSource; fuzzy.dart (cópia do firmware)
  controllers/  AppController (estado + ações), explicacao.dart, formatos.dart
  views/        home_shell, dashboard, historico, decisoes, controle, config, widgets
```

Caminhos no Firebase, os mesmos do `main.cpp`:

| Caminho | Quem escreve | Conteúdo |
|---|---|---|
| `/sensores/atual` | ESP32 (PUT) | último estado |
| `/historico/{push}` | ESP32 (POST) | log cronológico |
| `/comandos` | app | `{auto, ml, manual_s}`. O ESP32 lê a cada ciclo e zera `manual_s` |
| `/simulacao/cenario` | app | só para o simulador Python |

O **modo demonstração** roda um cultivo virtual no próprio celular com a mesma lógica do firmware (fuzzy, Kc, ajuste da MLP, travas). Cada 3 s equivalem a 5 min. Serve para apresentar à banca sem hardware.

## Como acessar o app

### Opção 1: site pelo GitHub (não precisa instalar nada)
O arquivo `.github/workflows/site-e-apk.yml` faz o GitHub compilar o site e o APK sozinho.

1. Crie uma conta em github.com e um repositório **público** chamado `irrigacao_app`.
2. Envie esta pasta: na página do repositório, use *Add file > Upload files* e arraste **todo o conteúdo** da pasta (inclusive a pasta `.github`). Se o navegador não mostrar a `.github`, use o GitHub Desktop ou `git push`.
3. No repositório: *Settings > Pages > Source* = **GitHub Actions**.
4. Aba *Actions*: o fluxo "Site e APK" roda sozinho (5 a 10 min). Se não rodar, abra-o e clique em *Run workflow*.
5. O site fica em `https://SEU-USUARIO.github.io/irrigacao_app/`.
6. No celular, abra o link e escolha **Adicionar à tela inicial**: o app ganha ícone e abre em tela cheia.

### Opção 2: APK no Android
Na mesma execução do Actions, desça até *Artifacts* e baixe `minha-horta-apk`. Descompacte, mande o `app-release.apk` para o celular e instale (autorize "fontes desconhecidas").

### Opção 3: no computador, com Flutter instalado
```
flutter create --org br.facens --project-name irrigacao_app --platforms android,web .
flutter pub get
flutter run -d chrome          # testa no navegador
flutter build web              # gera o site em build/web
```
Para hospedar no Firebase Hosting, use o `firebase.json` já incluído: `npm i -g firebase-tools`, `firebase login`, `firebase init hosting` (mantenha os arquivos existentes) e `firebase deploy`.

> O app já abre conectado ao banco do projeto. Para apresentar sem o ESP32, escolha **Demonstração local** nas Configurações.

## Conectar ao Firebase

O app conversa com o Realtime Database pela **API REST**, do mesmo jeito que o ESP32 no `main.cpp`. Não precisa de SDK, `flutterfire`, `firebase_options.dart` nem `google-services.json`: só a URL do banco.

- Banco padrão (já no código, em `lib/services/firebase_data_source.dart`): `controle-de-irrigacao-co-e3c37-default-rtdb.firebaseio.com`
- Para trocar sem recompilar: Configurações > Firebase > URL do Realtime Database.
- No console do Firebase: Realtime Database > **Regras** > cole `firebase/database.rules.json` e publique. Elas abrem leitura e escrita (**só para o TCC**) e criam o índice `irrigado_s`, usado na economia de água.
- No firmware (`secrets.h`): `#define FIREBASE_HOST "controle-de-irrigacao-co-e3c37-default-rtdb.firebaseio.com"`

Atualização: estado atual e comandos a cada 3 s, histórico novo a cada 10 s (só os registros novos), configurações a cada 20 s. Como o ESP32 envia a cada 30 s (`CLOUD_PUSH_MS`), o atraso percebido é dominado pelo firmware.

## Ajuste no firmware (`firmware/main.cpp`)

Uma mudança só, no fim do `loop()`: o envio ao Firebase acontece **na hora** quando houve irrigação ou comando manual. Antes, com `CLOUD_PUSH_MS = 30 s`, uma irrigação que caísse fora da janela de envio não aparecia no histórico nem no app.

```cpp
bool evento = (manualS > 0) || (irrigated > 0);
if (cloudUp() && (evento || lastCloudMs == 0 || millis() - lastCloudMs >= CLOUD_PUSH_MS)) {
```

## Limitações conhecidas
- Regras do banco abertas: para a versão final, use Firebase Auth e regras por usuário.
- Notificações push (FCM) ficaram para depois: exigem Cloud Functions. Hoje os alertas aparecem dentro do app (offline, solo crítico, bloqueio).
- Se mudar conjuntos ou regras fuzzy no firmware, atualize `lib/services/fuzzy.dart` (os textos explicativos dependem dele).

_Última atualização do app: 19/11/2026._
