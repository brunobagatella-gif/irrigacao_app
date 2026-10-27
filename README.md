# Minha Horta: app de irrigação inteligente (Flutter)

App do TCC (Facens) que mostra, explica e controla o sistema ESP32 + Fuzzy Mamdani + MLP via Firebase Realtime Database.

## Telas

| Aba | O que mostra |
|---|---|
| **Início** | Status da irrigação, 4 sensores com o conjunto fuzzy atual (solo "baixo", fase "floração"...), barra de faixas de umidade, a última decisão (Fuzzy×Kc → MLP → Decisão) explicada em linguagem natural, e o resumo do dia (água, irrigações, bomba usada/60 s). |
| **Histórico** | Gráficos de 6/12/24 h: solo (com faixa ideal, pontos de irrigação e projeção de 6 h pela tendência das últimas 4 h), temperatura, umidade do ar e altura. |
| **Decisões** | Log da IA filtrável (relevantes, irrigações, bloqueios, todas). Tocando num item, abre o raciocínio passo a passo e os dados do ciclo. |
| **Controle** | Liga/desliga o automático e a rede neural, irrigação manual (1–15 s) com confirmação, travas de segurança do firmware e painel de cenários climáticos. |
| **Configurações** | Fonte de dados (Firebase ou demonstração), URL do banco, limite de "offline", vazão da bomba, quantidade de histórico. |

A fonte de dados (Firebase ou demonstração) aparece só nas Configurações. Quando o firmware está em `TEST_MODE`, o Início mostra o selo "Modo teste".

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

> Sem o Firebase configurado, o app abre no modo demonstração (cultivo virtual). Para ver os dados do ESP32, siga "Conectar ao Firebase" abaixo e envie o `lib/firebase_options.dart` gerado para o GitHub. O site será recompilado.

## Conectar ao Firebase

### Passo a passo (no computador com Flutter)

1. Instale o Flutter (3.19 ou mais novo) e confira com `flutter doctor`.
2. Na pasta do projeto, gere as pastas de plataforma (os arquivos existentes não são sobrescritos):
   ```
   flutter create --org br.facens --project-name irrigacao_app --platforms android,ios,web .
   flutter pub get
   ```
3. Só com isso o app já abre no **modo demonstração**: `flutter run`
4. Para conectar ao Firebase:
   ```
   dart pub global activate flutterfire_cli
   flutterfire configure        # escolha o projeto; gera lib/firebase_options.dart
   ```
   - No console do Firebase, crie o **Realtime Database** e cole as regras de `firebase/database.rules.json` (abertas, **só para teste**).
   - Em `secrets.h` do firmware, coloque `FIREBASE_HOST` com o mesmo host do banco.
   - Nas Configurações do app, escolha **Firebase**. Se o `firebase_options.dart` vier sem `databaseURL`, cole o host no campo "URL do Realtime Database".
5. Testes do fuzzy (confere o port em Dart contra o Python): `flutter test`

### Android
- Release precisa da permissão de internet. Em `android/app/src/main/AndroidManifest.xml`, antes de `<application>`:
  `<uses-permission android:name="android.permission.INTERNET"/>`
- Se o build reclamar de `minSdkVersion`, use 23 em `android/app/build.gradle`.
- Se o `flutterfire configure` atualizar os pacotes Firebase para uma versão maior, rode `flutter pub upgrade --major-versions`.

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
