// =====================================================================
//  TCC - IRRIGACAO INTELIGENTE  |  ESP32 + Fuzzy Mamdani + MLP + Firebase
//
//  Fluxo por ciclo:
//    sensores -> fuzzy (25 regras, solo x temperatura)
//             -> fator Kc pela altura da planta (fase fenologica)
//             -> MLP 25-20-15-10-1 ajusta o tempo (0,5x a 1,5x)
//             -> travas de seguranca -> rele
//             -> envia dados ao Firebase / le comandos do app
// =====================================================================
#include <Arduino.h>
#include <DHT.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <time.h>
#include <math.h>

#include "secrets.h"      // Wi-Fi, Firebase, data de plantio
#include "mlp_weights.h"  // pesos da MLP (gerado por tools/train_mlp.py)

// ------------------------- PINOS -------------------------
#define SOIL_PIN  34   // ADC1 (compativel com Wi-Fi)
#define DHT_PIN   23
#define DHT_TYPE  DHT22
#define TRIG_PIN  5
#define ECHO_PIN  18   // ATENCAO: HC-SR04 manda 5V -> usar divisor de tensao (1k/2k)
#define RELAY_PIN 26

DHT dht(DHT_PIN, DHT_TYPE);

// ------------------------- CONFIGURACAO -------------------------
bool TEST_MODE = true;               // true = calcula tudo, mas NAO liga a bomba

int   RAW_DRY = 3000;                // calibrar: sensor no ar/solo seco
int   RAW_WET = 1300;                // calibrar: sensor na agua/solo saturado
float SENSOR_TO_SOIL_CM = 100.0;     // distancia do HC-SR04 ate o nivel do solo
float PUMP_FLOW_ML_S = 33.3;         // medir a vazao real depois

const float MAX_PLANT_HEIGHT_CM = 70.0;
const float HARD_STOP_MOISTURE  = 75.0;   // % acima disso nunca irriga

const float MAX_PUMP_S       = 15.0;      // maximo por irrigacao (universo da saida fuzzy)
const float MIN_ACTION_S     = 1.0;       // abaixo disso = "nao irrigar"
const float MAX_DAILY_PUMP_S = 60.0;      // teto de bomba ligada em 24 h

const unsigned long READ_INTERVAL_MS = 10000UL;           // 10 s em teste (final: 5 min = 300000)
const unsigned long CLOUD_PUSH_MS    = 30000UL;           // envio ao Firebase (final: 300000)
const unsigned long TREND_STEP_MS    = 5UL * 60UL * 1000UL;
const unsigned long MIN_INTERVAL_MS  = 30UL * 60UL * 1000UL; // entre irrigacoes automaticas
const unsigned long WIFI_RETRY_MS    = 30000UL;

const bool RELAY_ACTIVE_LOW = true;

// ------------------------- ESTADO -------------------------
unsigned long lastReadMs = 0, lastWateringMs = 0, lastCloudMs = 0;
unsigned long lastTrendMs = 0, lastWifiTryMs = 0, dayWindowStart = 0;
float pumpSecToday = 0;

bool autoMode  = true;    // comandado pelo app (/comandos/auto)
bool mlEnabled = true;    // comandado pelo app (/comandos/ml)

// historico de 4 h (48 amostras de 5 min) para as tendencias
const int TREND_N = 48;
float soilHist[TREND_N], tempHist[TREND_N];
int histHead = 0, histCount = 0;

// ------------------------- UTIL -------------------------
float clampF(float x, float a, float b) { return x < a ? a : (x > b ? b : x); }

struct Trap { float a, b, c, d; };

float trapmf(float x, float a, float b, float c, float d) {
  if (x <= a || x >= d) return 0;
  if (x >= b && x <= c) return 1;
  if (x < b) return (x - a) / (b - a);
  return (d - x) / (d - c);
}
float trapmf(float x, const Trap &t) { return trapmf(x, t.a, t.b, t.c, t.d); }

// ------------------------- SENSORES -------------------------
int readSoilRaw() {
  long total = 0;
  for (int i = 0; i < 15; i++) { total += analogRead(SOIL_PIN); delay(10); }
  return (int)(total / 15);
}

float rawToMoisture(int raw) {
  if (RAW_DRY == RAW_WET) return 0;
  float pct = 100.0f * ((float)RAW_DRY - raw) / ((float)RAW_DRY - RAW_WET);
  return clampF(pct, 0, 100);
}

bool readClimate(float &t, float &h) {
  t = dht.readTemperature();
  h = dht.readHumidity();
  return !(isnan(t) || isnan(h));
}

float readDistanceCm() {
  digitalWrite(TRIG_PIN, LOW);  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH); delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  unsigned long d = pulseIn(ECHO_PIN, HIGH, 30000UL);
  if (d == 0) return NAN;
  return (d * 0.0343f) / 2.0f;
}

float readPlantHeightCm() {
  float total = 0; int valid = 0;
  for (int i = 0; i < 5; i++) {
    float d = readDistanceCm();
    if (!isnan(d) && d > 2 && d < 200) { total += d; valid++; }
    delay(50);
  }
  if (valid == 0) return NAN;
  return clampF(SENSOR_TO_SOIL_CM - total / valid, 0, MAX_PLANT_HEIGHT_CM);
}

// ------------------------- FUZZY: CONJUNTOS (relatorio, cap. 7.5) -------------------------
// Trapezios {a,b,c,d}. Solo em % (calibrado), temperatura em C, altura em cm.
const Trap SOIL_SETS[5] = {   // critico, baixo, ideal, alto, encharcado
  {-1, 0, 10, 20}, {18, 24, 30, 35}, {32, 40, 54, 62}, {58, 66, 72, 80}, {78, 86, 100, 101}};
const Trap TEMP_SETS[5] = {   // muito fria, fria, moderada, quente, muito quente
  {-1, 0, 8, 14}, {12, 15, 17, 20}, {18, 21, 25, 28}, {26, 29, 33, 36}, {34, 38, 45, 46}};
const Trap HEIGHT_SETS[5] = { // germinacao, veg. inicial, veg. avancado, floracao, producao
  {-1, 0, 2, 5}, {3, 6, 12, 15}, {10, 15, 25, 30}, {25, 32, 43, 50}, {40, 50, 70, 71}};

// Saida: tempo de bomba em segundos (0..15). 0=nulo 1=curto 2=medio 3=longo 4=muito longo
const Trap OUT_SETS[5] = {
  {-1, 0, 0.3, 1.5}, {1, 2.5, 3.5, 5}, {4, 6, 8, 10}, {8, 10, 12, 14}, {12, 14, 15, 16}};

// Kc por fase (FAO-56 / EMBRAPA, conforme relatorio 7.3)
const float KC[5] = {0.35f, 0.70f, 1.05f, 1.15f, 0.90f};

// Tabela de 25 regras: RULES[solo][temperatura] -> conjunto de saida
const uint8_t RULES[5][5] = {
  /* solo critico     */ {3, 3, 4, 4, 4},
  /* solo baixo       */ {2, 2, 3, 3, 4},
  /* solo ideal       */ {0, 0, 0, 1, 1},
  /* solo alto        */ {0, 0, 0, 0, 0},
  /* solo encharcado  */ {0, 0, 0, 0, 0}};

const char *SOIL_NAMES[5]   = {"critico", "baixo", "ideal", "alto", "encharcado"};
const char *TEMP_NAMES[5]   = {"muito fria", "fria", "moderada", "quente", "muito quente"};
const char *HEIGHT_NAMES[5] = {"germinacao", "veg. inicial", "veg. avancado", "floracao", "producao"};

struct FuzzyResult {
  float mu[15];     // [0-4] solo, [5-9] temperatura, [10-14] altura
  float baseTime;   // saida do Mamdani (s), antes do Kc
  float kc;         // fator de cultura pela altura
  float time;       // baseTime * kc (s)
  int soilIdx, tempIdx, heightIdx;
};

int argmaxN(const float *v, int n) {
  int k = 0;
  for (int i = 1; i < n; i++) if (v[i] > v[k]) k = i;
  return k;
}

FuzzyResult fuzzyController(float soil, float temperature, float height) {
  FuzzyResult r;
  float s = clampF(soil, 0, 100), t = clampF(temperature, 0, 45);

  for (int i = 0; i < 5; i++) {
    r.mu[i]     = trapmf(s, SOIL_SETS[i]);
    r.mu[5 + i] = trapmf(t, TEMP_SETS[i]);
  }

  // altura: se o HC-SR04 falhar, Kc neutro (1,0) e graus de pertinencia zerados
  if (isnan(height)) {
    for (int i = 0; i < 5; i++) r.mu[10 + i] = 0;
    r.kc = 1.0f;
  } else {
    float h = clampF(height, 0, 70), num = 0, den = 0;
    for (int i = 0; i < 5; i++) {
      r.mu[10 + i] = trapmf(h, HEIGHT_SETS[i]);
      num += r.mu[10 + i] * KC[i];
      den += r.mu[10 + i];
    }
    r.kc = den > 0.0001f ? num / den : 1.0f;
  }

  // Mamdani: min nas premissas, max na agregacao, centroide na defuzzificacao
  const float step = 0.1f;
  const int points = 151;      // 0 .. 15 s
  float agg[points];
  for (int i = 0; i < points; i++) agg[i] = 0;

  for (int i = 0; i < 5; i++) {
    for (int j = 0; j < 5; j++) {
      float w = min(r.mu[i], r.mu[5 + j]);
      if (w <= 0) continue;
      const Trap &o = OUT_SETS[RULES[i][j]];
      for (int k = 0; k < points; k++)
        agg[k] = max(agg[k], min(w, trapmf(k * step, o)));
    }
  }

  float num = 0, den = 0;
  for (int k = 0; k < points; k++) { num += k * step * agg[k]; den += agg[k]; }
  r.baseTime = den > 0.0001f ? num / den : 0;
  r.time = clampF(r.baseTime * r.kc, 0, MAX_PUMP_S);

  r.soilIdx = argmaxN(&r.mu[0], 5);
  r.tempIdx = argmaxN(&r.mu[5], 5);
  r.heightIdx = isnan(height) ? -1 : argmaxN(&r.mu[10], 5);
  return r;
}

// ------------------------- TEMPO / TENDENCIAS -------------------------
bool timeValid() { return time(nullptr) > 1700000000L; }

float hourOfDay() {
  struct tm tmInfo;
  if (timeValid() && getLocalTime(&tmInfo, 0)) return tmInfo.tm_hour + tmInfo.tm_min / 60.0f;
  return 12.0f;
}

float dayOfCycle() {
  if (!timeValid() || PLANTING_EPOCH <= 0) return 0;
  return clampF((time(nullptr) - PLANTING_EPOCH) / 86400.0f, 0, 90);
}

void pushTrend(float soil, float temp) {
  soilHist[histHead] = soil;
  tempHist[histHead] = temp;
  histHead = (histHead + 1) % TREND_N;
  if (histCount < TREND_N) histCount++;
}

// variacao em relacao a amostra mais antiga disponivel (ate 4 h)
void trends(float soil, float temp, float &dSoil, float &dTemp) {
  if (histCount == 0) { dSoil = 0; dTemp = 0; return; }
  int oldest = (histCount < TREND_N) ? 0 : histHead;
  dSoil = soil - soilHist[oldest];
  dTemp = temp - tempHist[oldest];
}

// ------------------------- MLP 25-20-15-10-1 -------------------------
const int N_IN = 25;

void buildFeatures(const FuzzyResult &fz, float soil, float temp, float air, float height,
                   float *f) {
  for (int i = 0; i < 15; i++) f[i] = fz.mu[i];                      // 15 graus de pertinencia
  f[15] = clampF(soil / 100.0f, 0, 1);
  f[16] = clampF(temp / 45.0f, 0, 1);
  f[17] = isnan(height) ? 0 : clampF(height / 70.0f, 0, 1);
  f[18] = clampF(air / 100.0f, 0, 1);
  f[19] = autoMode ? 1.0f : 0.0f;                                    // flag auto/manual
  f[20] = hourOfDay() / 24.0f;                                       // contexto temporal
  f[21] = dayOfCycle() / 90.0f;
  float dS, dT; trends(soil, temp, dS, dT);
  f[22] = (clampF(dS / 20.0f, -1, 1) + 1.0f) / 2.0f;                 // tendencia solo (4 h)
  f[23] = (clampF(dT / 10.0f, -1, 1) + 1.0f) / 2.0f;                 // tendencia temp (4 h)
  f[24] = clampF(fz.time / MAX_PUMP_S, 0, 1);                        // saida do fuzzy base
}

float mlpForward(const float *in) {
  float a1[20], a2[15], a3[10];
  for (int i = 0; i < 20; i++) {
    float s = MLP_B1[i];
    for (int j = 0; j < N_IN; j++) s += MLP_W1[i][j] * in[j];
    a1[i] = s > 0 ? s : 0;
  }
  for (int i = 0; i < 15; i++) {
    float s = MLP_B2[i];
    for (int j = 0; j < 20; j++) s += MLP_W2[i][j] * a1[j];
    a2[i] = s > 0 ? s : 0;
  }
  for (int i = 0; i < 10; i++) {
    float s = MLP_B3[i];
    for (int j = 0; j < 15; j++) s += MLP_W3[i][j] * a2[j];
    a3[i] = s > 0 ? s : 0;
  }
  float s = MLP_B4[0];
  for (int j = 0; j < 10; j++) s += MLP_W4[0][j] * a3[j];
  return 1.0f / (1.0f + expf(-s));   // saida em 0..1
}

// ------------------------- RELE / BOMBA -------------------------
void relay(bool on) {
  digitalWrite(RELAY_PIN, RELAY_ACTIVE_LOW ? (on ? LOW : HIGH) : (on ? HIGH : LOW));
}

// Retorna os segundos realmente irrigados (0 se bloqueado). 'note' recebe o motivo.
float irrigate(float seconds, float moisture, bool manual, const char **note) {
  if (moisture >= HARD_STOP_MOISTURE) { *note = "BLOQUEADO: solo muito umido"; return 0; }
  if (seconds < MIN_ACTION_S)         { *note = "sem irrigacao"; return 0; }
  seconds = clampF(seconds, 0, MAX_PUMP_S);

  if (millis() - dayWindowStart >= 86400000UL) { dayWindowStart = millis(); pumpSecToday = 0; }
  if (pumpSecToday + seconds > MAX_DAILY_PUMP_S) { *note = "BLOQUEADO: limite diario de bomba"; return 0; }

  if (!manual && lastWateringMs != 0 && millis() - lastWateringMs < MIN_INTERVAL_MS) {
    *note = "BLOQUEADO: intervalo minimo entre irrigacoes";
    return 0;
  }

  if (TEST_MODE) { *note = "TEST_MODE: bomba NAO acionada"; return 0; }

  relay(true);
  unsigned long start = millis(), dur = (unsigned long)(seconds * 1000.0f);
  while (millis() - start < dur) delay(20);
  relay(false);

  lastWateringMs = millis();
  pumpSecToday += seconds;
  *note = manual ? "irrigacao MANUAL executada" : "irrigacao AUTOMATICA executada";
  return seconds;
}

// ------------------------- WI-FI / FIREBASE (REST) -------------------------
bool cloudUp() { return WiFi.status() == WL_CONNECTED && strlen(FIREBASE_HOST) > 0; }

void maintainWifi() {
  if (WiFi.status() == WL_CONNECTED) return;
  if (millis() - lastWifiTryMs < WIFI_RETRY_MS) return;
  lastWifiTryMs = millis();
  Serial.println("Wi-Fi caiu, tentando reconectar...");
  WiFi.disconnect();
  WiFi.begin(WIFI_SSID, WIFI_PASS);
}

String fbUrl(const char *path) {
  String u = String("https://") + FIREBASE_HOST + path + ".json";
  if (strlen(FIREBASE_AUTH) > 0) u += String("?auth=") + FIREBASE_AUTH;
  return u;
}

// method: "PUT", "POST", "PATCH", "GET"
bool fbRequest(const char *method, const char *path, const String &body, String *resp) {
  if (!cloudUp()) return false;
  WiFiClientSecure client;
  client.setInsecure();   // simplificacao de prototipo; em producao usar setCACert()
  HTTPClient http;
  http.setTimeout(5000);
  if (!http.begin(client, fbUrl(path))) return false;
  http.addHeader("Content-Type", "application/json");
  int code = http.sendRequest(method, body);
  if (code > 0 && resp) *resp = http.getString();
  http.end();
  if (code < 200 || code >= 300) {
    Serial.printf("Firebase %s %s -> HTTP %d\n", method, path, code);
    return false;
  }
  return true;
}

// parsing simples por substring (o relatorio descreve a mesma abordagem)
bool jsonFind(const String &s, const char *key, int &pos) {
  String k = String("\"") + key + "\":";
  int p = s.indexOf(k);
  if (p < 0) return false;
  pos = p + k.length();
  while (pos < (int)s.length() && s[pos] == ' ') pos++;
  return true;
}
bool jsonBool(const String &s, const char *key, bool def) {
  int p; if (!jsonFind(s, key, p)) return def;
  return s.startsWith("true", p) ? true : (s.startsWith("false", p) ? false : def);
}
float jsonNum(const String &s, const char *key, float def) {
  int p; if (!jsonFind(s, key, p)) return def;
  return s.substring(p).toFloat();
}

// le /comandos: {"auto":true,"ml":true,"manual_s":0}
float pullCommands() {
  String resp;
  if (!fbRequest("GET", "/comandos", "", &resp)) return 0;
  autoMode  = jsonBool(resp, "auto", autoMode);
  mlEnabled = jsonBool(resp, "ml", mlEnabled);
  return jsonNum(resp, "manual_s", 0);
}

void clearManualCommand() { fbRequest("PATCH", "/comandos", "{\"manual_s\":0}", nullptr); }

void pushCloud(int raw, float soil, float temp, float air, float height, float fuzzyS,
               float mult, float finalS, float irrigatedS, const char *reason, const char *note) {
  char hbuf[16];
  if (isnan(height)) strcpy(hbuf, "null"); else snprintf(hbuf, sizeof(hbuf), "%.1f", height);
  char body[640];
  snprintf(body, sizeof(body),
    "{\"ts\":%ld,\"uptime_ms\":%lu,\"raw\":%d,\"solo\":%.1f,\"temp\":%.1f,\"ar\":%.1f,"
    "\"altura\":%s,\"fuzzy_s\":%.2f,\"mlp_mult\":%.2f,\"decisao_s\":%.2f,\"irrigado_s\":%.2f,"
    "\"volume_ml\":%.1f,\"test_mode\":%s,\"auto\":%s,\"motivo\":\"%s\",\"status\":\"%s\"}",
    (long)(timeValid() ? time(nullptr) : 0), millis(), raw, soil, temp, air, hbuf, fuzzyS, mult,
    finalS, irrigatedS, irrigatedS * PUMP_FLOW_ML_S, TEST_MODE ? "true" : "false",
    autoMode ? "true" : "false", reason, note);
  String b(body);
  fbRequest("PUT", "/sensores/atual", b, nullptr);   // ultimo estado (dashboard)
  fbRequest("POST", "/historico", b, nullptr);       // log cronologico (graficos / treino)
}

// ------------------------- SETUP / LOOP -------------------------
void setup() {
  Serial.begin(115200);
  pinMode(SOIL_PIN, INPUT);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(RELAY_PIN, OUTPUT);
  relay(false);
  analogReadResolution(12);
  dht.begin();
  dayWindowStart = millis();

  Serial.println();
  Serial.println("====================================");
  Serial.println(" TCC - IRRIGACAO INTELIGENTE");
  Serial.println(" ESP32 + FUZZY MAMDANI + MLP");
  Serial.println("====================================");
  Serial.print("TEST_MODE: ");
  Serial.println(TEST_MODE ? "ATIVO - BOMBA BLOQUEADA" : "DESATIVADO - BOMBA HABILITADA");
  Serial.print("MLP: ");
  Serial.println(MLP_TRAINED ? "pesos treinados carregados" : "SEM pesos (fuzzy puro)");

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 10000) { delay(250); Serial.print("."); }
  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("Wi-Fi OK, IP: "); Serial.println(WiFi.localIP());
    configTime(UTC_OFFSET_S, 0, "pool.ntp.org", "time.google.com");
  } else {
    Serial.println("Sem Wi-Fi: operando offline (fuzzy continua funcionando).");
  }

  Serial.println("CSV,millis,rawSolo,umidadeSolo,temp,umidadeAr,altura,fuzzy_s,mlp_mult,decisao_s");
}

void loop() {
  maintainWifi();

  if (lastReadMs != 0 && millis() - lastReadMs < READ_INTERVAL_MS) { delay(100); return; }
  lastReadMs = millis();

  // ---- leitura ----
  int raw = readSoilRaw();
  float soil = rawToMoisture(raw);
  float temperature, airHumidity;
  if (!readClimate(temperature, airHumidity)) {
    Serial.println("ERRO: falha na leitura do DHT22 (ciclo ignorado, sem irrigar).");
    return;
  }
  float height = readPlantHeightCm();

  if (lastTrendMs == 0 || millis() - lastTrendMs >= TREND_STEP_MS) {
    lastTrendMs = millis();
    pushTrend(soil, temperature);
  }

  // ---- comandos vindos do app ----
  float manualS = cloudUp() ? pullCommands() : 0;

  // ---- decisao: fuzzy -> Kc -> MLP ----
  FuzzyResult fz = fuzzyController(soil, temperature, height);
  float feat[N_IN];
  buildFeatures(fz, soil, temperature, airHumidity, height, feat);

  float mult = 1.0f;
  if (MLP_TRAINED && mlEnabled) mult = 0.5f + mlpForward(feat);   // 0,5x .. 1,5x
  float finalS = (fz.time < MIN_ACTION_S) ? 0 : clampF(fz.time * mult, 0, MAX_PUMP_S);
  // a MLP nunca cria irrigacao quando o fuzzy decidiu "nao irrigar"

  char reason[160];
  snprintf(reason, sizeof(reason), "solo %s, temp %s, fase %s, Kc %.2f, fuzzy %.1fs, MLP x%.2f",
           SOIL_NAMES[fz.soilIdx], TEMP_NAMES[fz.tempIdx],
           fz.heightIdx >= 0 ? HEIGHT_NAMES[fz.heightIdx] : "sem leitura", fz.kc, fz.time, mult);

  // ---- log serial ----
  Serial.println();
  Serial.println("------------------------------------");
  Serial.printf("Solo RAW: %d | Umidade solo: %.1f %%\n", raw, soil);
  Serial.printf("Temp: %.1f C | Umidade ar: %.1f %%\n", temperature, airHumidity);
  if (isnan(height)) Serial.println("Altura planta: SEM LEITURA");
  else Serial.printf("Altura planta: %.1f cm\n", height);
  Serial.printf("Fuzzy: %.2f s (base %.2f x Kc %.2f) | MLP x%.2f | Decisao: %.2f s\n",
                fz.time, fz.baseTime, fz.kc, mult, finalS);
  Serial.println(reason);
  Serial.printf("CSV,%lu,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f\n", millis(), raw, soil, temperature,
                airHumidity, isnan(height) ? -1.0f : height, fz.time, mult, finalS);
  Serial.print("FEAT");
  for (int i = 0; i < N_IN; i++) Serial.printf(",%.4f", feat[i]);
  Serial.println();

  // ---- atuacao ----
  const char *note = "";
  float irrigated = 0;
  if (manualS > 0) {
    irrigated = irrigate(manualS, soil, true, &note);
    clearManualCommand();
  } else if (autoMode) {
    irrigated = irrigate(finalS, soil, false, &note);
  } else {
    note = "modo manual: automatico desligado";
  }
  Serial.println(note);
  if (irrigated > 0) Serial.printf("Volume estimado: %.1f mL\n", irrigated * PUMP_FLOW_ML_S);

  // ---- nuvem ----
  // envia na hora quando houve irrigacao ou comando manual, para o app sempre registrar o evento
  bool evento = (manualS > 0) || (irrigated > 0);
  if (cloudUp() && (evento || lastCloudMs == 0 || millis() - lastCloudMs >= CLOUD_PUSH_MS)) {
    lastCloudMs = millis();
    pushCloud(raw, soil, temperature, airHumidity, height, fz.time, mult, finalS, irrigated, reason, note);
  }
}
