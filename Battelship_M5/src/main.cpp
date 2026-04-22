#include <NimBLEDevice.h>
#include <M5Core2.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <HTTPClient.h>

#define SERVICE_UUID    "f4893cb2-c54a-4c85-9339-4c03f3f19077"
#define MOVE_CHAR_UUID  "ceb4ef8c-12b5-4932-b2d5-3bf26fe18af5"
#define STATE_CHAR_UUID "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

// ----------------------------------------------------------------
//  WiFi + GCP
// ----------------------------------------------------------------
#define WIFI_SSID     "SpectrumSetup-53"
#define WIFI_PASSWORD "smallshark225"
#define GCP_URL       "https://navalstrike-767201081384.europe-west1.run.app"

#define GRID_SIZE  6
#define CELL_SIZE  32
#define GRID_OX    64
#define GRID_OY    36
#define BANNER_H   26
#define STATUS_Y   222

#define COL_BG       M5.Lcd.color565(  0,  8, 32)
#define COL_WATER    M5.Lcd.color565(  4, 28, 58)
#define COL_GRIDLINE M5.Lcd.color565( 10, 58, 74)
#define COL_SHIP     M5.Lcd.color565(138,176,192)
#define COL_HIT      M5.Lcd.color565(204, 32, 32)
#define COL_MISS     M5.Lcd.color565( 42, 58, 74)
#define COL_WHITE    M5.Lcd.color565(255,255,255)
#define COL_GREEN    M5.Lcd.color565(  0,200, 68)
#define COL_RED_BAN  M5.Lcd.color565(180, 40,  0)
#define COL_SUBTEXT  M5.Lcd.color565( 74,122,138)
#define COL_STATUSBG M5.Lcd.color565(  8, 24, 42)
#define COL_SHIPDEAD M5.Lcd.color565( 80, 20, 20)
#define COL_CURSOR   M5.Lcd.color565(255,220,  0)
#define COL_PREVIEW  M5.Lcd.color565( 80,160, 80)

#define FAN_PIN     26
#define FAN_ON      HIGH
#define FAN_OFF_VAL LOW

int scoreWins   = 0;
int scoreLosses = 0;

enum CellState { EMPTY, SHIP, HIT, MISS };
enum GamePhase { PLACEMENT, WAITING, BATTLE, OVER };

struct {
    CellState myGrid[GRID_SIZE][GRID_SIZE];
    CellState enemyGrid[GRID_SIZE][GRID_SIZE];
    int  myShipsLeft;
    int  enemyShipsLeft;
    int  totalShipCells;
    bool myTurn;
    GamePhase phase;
    bool iWon;
} gs;

BLEServer         *bleServer;
BLEService        *bleService;
BLECharacteristic *movChar;
BLECharacteristic *stateChar;
bool deviceConnected = false;

volatile bool pendingConnect    = false;
volatile bool pendingDisconnect = false;
volatile bool pendingMove       = false;
volatile bool pendingWin        = false;
volatile int  pendingRow        = -1;
volatile int  pendingCol        = -1;

int  placeRow    = 0;
int  placeCol    = 0;
int  shipsPlaced = 0;
#define SHIPS_NEEDED  3
#define SHIP_LEN      2

int  cursorRow = 0;
int  cursorCol = 0;

#define BTN_DEBOUNCE_MS 200
unsigned long lastBtnMs = 0;

// Forward declarations
void initGame();
void initFan();
void initWiFi();
void postMatchResult();
void setFan(bool on);
int  nearestShipDistance(int row, int col);
void drawPlacementScreen();
void drawPlacementGrid();
void drawPlacementCursor(bool visible);
void handlePlacementButtons();
bool canPlaceShip(int row, int col);
void commitShip(int row, int col);
void drawAttackScreen();
void drawDefendScreen();
void drawWaitingScreen();
void drawGameOverScreen();
void drawScoreboard();
void drawGrid(CellState grid[GRID_SIZE][GRID_SIZE], bool showShips);
void drawCell(int row, int col, CellState state, bool showShip);
void drawCursor(int row, int col, bool visible);
void drawBanner(const char* text, uint16_t bgColor, uint16_t textColor);
void drawStatusBar();
void drawColRowLabels();
void handleButtons();
void applyMyShot(int row, int col);
void applyEnemyShot(int row, int col);
void sendMove(int row, int col);
void sendStateUpdate();
void initBLE();

class MoveCharCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pChar) {
        std::string raw = pChar->getValue();
        if (raw.length() == 0) return;
        StaticJsonDocument<64> doc;
        if (deserializeJson(doc, raw.c_str())) return;

        if (doc.containsKey("gameover") && doc["gameover"] == true) {
            gs.phase   = OVER;
            gs.iWon    = true;
            pendingWin = true;
            Serial.println("[GAME] Flutter signals game over — M5 wins!");
            return;
        }

        if (gs.phase != BATTLE || gs.myTurn) return;
        int r = doc["r"] | -1;
        int c = doc["c"] | -1;
        if (r < 0 || r >= GRID_SIZE || c < 0 || c >= GRID_SIZE) return;
        pendingRow  = r;
        pendingCol  = c;
        pendingMove = true;
        Serial.printf("[BLE] Enemy fires at (%d,%d)\n", r, c);
    }
};

class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer *pServer) {
        deviceConnected = true;
        pendingConnect  = true;
        Serial.println("[BLE] Flutter connected");
    }
    void onDisconnect(BLEServer *pServer) {
        deviceConnected   = false;
        pendingDisconnect = true;
        Serial.println("[BLE] Disconnected");
    }
};

// ================================================================
//  Setup
// ================================================================
void setup() {
    // Kill fan immediately before anything else runs
    pinMode(26, OUTPUT);
    digitalWrite(26, LOW);

    M5.begin();
    M5.Lcd.setRotation(1);
    Serial.begin(115200);

    initFan();
    initGame();
    drawPlacementScreen();
}

// ================================================================
//  Loop
// ================================================================
void loop() {
    M5.update();

    if (gs.phase == PLACEMENT) {
        handlePlacementButtons();
        return;
    }

    if (pendingConnect) {
        pendingConnect = false;
        gs.phase  = BATTLE;
        gs.myTurn = true;
        delay(1200);
        sendStateUpdate();
        delay(300);
        sendStateUpdate();
        cursorRow = 0;
        cursorCol = 0;
        drawAttackScreen();
        Serial.println("[GAME] Battle started");
    }

    if (pendingDisconnect) {
        pendingDisconnect = false;
        bleServer->startAdvertising();
        gs.phase = WAITING;
        setFan(false);
        drawWaitingScreen();
    }

    if (pendingWin) {
        pendingWin = false;
        scoreWins++;
        setFan(false);
        postMatchResult();
        drawGameOverScreen();
        return;
    }

    if (pendingMove) {
        pendingMove = false;
        applyEnemyShot(pendingRow, pendingCol);
    }

    if (gs.phase == BATTLE && gs.myTurn) {
        handleButtons();
    }

    delay(20);
}

// ================================================================
//  WiFi init
// ================================================================
void initWiFi() {
    Serial.printf("[WiFi] Connecting to %s\n", WIFI_SSID);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
        delay(500);
        Serial.print(".");
        attempts++;
    }

    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("\n[WiFi] Connected! IP: %s\n", WiFi.localIP().toString().c_str());
    } else {
        Serial.println("\n[WiFi] Failed to connect — skipping GCP post");
    }
}

// ================================================================
//  POST match result to GCP
// ================================================================
void postMatchResult() {
    // Connect WiFi if not already connected
    if (WiFi.status() != WL_CONNECTED) {
        initWiFi();
    }

    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[GCP] No WiFi — skipping post");
        return;
    }

    // Show uploading message on screen
    M5.Lcd.fillScreen(COL_BG);
    drawBanner("  SAVING RESULT...  ", COL_GRIDLINE, COL_WHITE);
    M5.Lcd.setTextColor(COL_SUBTEXT);
    M5.Lcd.setTextSize(1);
    M5.Lcd.setCursor(80, 120);
    M5.Lcd.print("Uploading to cloud...");

    // Build JSON payload
    StaticJsonDocument<128> doc;
    doc["winner"]          = gs.iWon ? "m5" : "flutter";
    doc["flutterShipsLeft"] = gs.enemyShipsLeft;
    doc["m5ShipsLeft"]     = gs.myShipsLeft;
    char payload[128];
    serializeJson(doc, payload);

    HTTPClient http;
    http.begin(GCP_URL);
    http.addHeader("Content-Type", "application/json");

    int code = http.POST(payload);
    Serial.printf("[GCP] POST status: %d\n", code);

    if (code == 200) {
        String response = http.getString();
        Serial.printf("[GCP] Response: %s\n", response.c_str());

        // Parse quote from response
        StaticJsonDocument<256> resp;
        if (!deserializeJson(resp, response)) {
            const char* quote = resp["quote"] | "";
            if (strlen(quote) > 0) {
                // Show quote on screen briefly
                M5.Lcd.fillRect(0, 100, 320, 80, COL_BG);
                M5.Lcd.setTextColor(COL_SHIP);
                M5.Lcd.setTextSize(1);
                M5.Lcd.setCursor(10, 110);
                M5.Lcd.print("\"");
                M5.Lcd.print(quote);
                M5.Lcd.print("\"");
                delay(2500);
            }
        }
    } else {
        Serial.printf("[GCP] POST failed: %d\n", code);
    }

    http.end();
}

// ================================================================
//  Fan
// ================================================================
void initFan() {
    pinMode(FAN_PIN, OUTPUT);
    digitalWrite(FAN_PIN, LOW);
    Serial.println("[FAN] Initialized on GPIO 26");
}

void setFan(bool on) {
    digitalWrite(FAN_PIN, on ? HIGH : LOW);
}

int nearestShipDistance(int row, int col) {
    int minDist = 999;
    for (int r = 0; r < GRID_SIZE; r++)
        for (int c = 0; c < GRID_SIZE; c++)
            if (gs.myGrid[r][c] == SHIP) {
                int dist = abs(r - row) + abs(c - col);
                if (dist < minDist) minDist = dist;
            }
    return minDist;
}

// ================================================================
//  Init game state
// ================================================================
void initGame() {
    memset(&gs, 0, sizeof(gs));
    for (int r = 0; r < GRID_SIZE; r++)
        for (int c = 0; c < GRID_SIZE; c++) {
            gs.myGrid[r][c]    = EMPTY;
            gs.enemyGrid[r][c] = EMPTY;
        }
    gs.totalShipCells = SHIPS_NEEDED * SHIP_LEN;
    gs.myShipsLeft    = gs.totalShipCells;
    gs.enemyShipsLeft = gs.totalShipCells;
    gs.myTurn         = true;
    gs.phase          = PLACEMENT;
    gs.iWon           = false;
    shipsPlaced       = 0;
    placeRow          = 0;
    placeCol          = 0;
}

// ================================================================
//  Placement screen
// ================================================================
void drawPlacementScreen() {
    M5.Lcd.fillScreen(COL_BG);
    drawBanner(" A:ROW  C:COL  B:PLACE ", COL_GRIDLINE, COL_WHITE);
    drawColRowLabels();
    drawPlacementGrid();
    drawPlacementCursor(true);
    M5.Lcd.fillRect(0, STATUS_Y, 320, 18, COL_STATUSBG);
    M5.Lcd.setTextColor(COL_SUBTEXT);
    M5.Lcd.setTextSize(1);
    M5.Lcd.setCursor(6, STATUS_Y + 5);
    char buf[40];
    snprintf(buf, sizeof(buf), "Ships: %d/%d placed", shipsPlaced, SHIPS_NEEDED);
    M5.Lcd.print(buf);
}

void drawPlacementGrid() {
    for (int r = 0; r < GRID_SIZE; r++)
        for (int c = 0; c < GRID_SIZE; c++)
            drawCell(r, c, gs.myGrid[r][c], true);
}

void drawPlacementCursor(bool visible) {
    for (int dc = 0; dc < SHIP_LEN; dc++) {
        int c = placeCol + dc;
        if (c >= GRID_SIZE) continue;
        int x = GRID_OX + c * CELL_SIZE;
        int y = GRID_OY + placeRow * CELL_SIZE;
        if (visible && gs.myGrid[placeRow][c] == EMPTY) {
            M5.Lcd.fillRect(x + 1, y + 1, CELL_SIZE - 2, CELL_SIZE - 2, COL_PREVIEW);
            M5.Lcd.drawRect(x, y, CELL_SIZE, CELL_SIZE, COL_CURSOR);
        } else if (!visible && gs.myGrid[placeRow][c] == EMPTY) {
            M5.Lcd.fillRect(x + 1, y + 1, CELL_SIZE - 2, CELL_SIZE - 2, COL_WATER);
            M5.Lcd.drawRect(x, y, CELL_SIZE, CELL_SIZE, COL_GRIDLINE);
        }
    }
}

bool canPlaceShip(int row, int col) {
    if (col + SHIP_LEN > GRID_SIZE) return false;
    for (int dc = 0; dc < SHIP_LEN; dc++)
        if (gs.myGrid[row][col + dc] != EMPTY) return false;
    return true;
}

void commitShip(int row, int col) {
    for (int dc = 0; dc < SHIP_LEN; dc++)
        gs.myGrid[row][col + dc] = SHIP;
    shipsPlaced++;
}

// ================================================================
//  Placement button handler
// ================================================================
void handlePlacementButtons() {
    unsigned long now = millis();
    if (now - lastBtnMs < BTN_DEBOUNCE_MS) return;
    bool pressed = false;

    if (M5.BtnA.wasPressed()) {
        drawPlacementCursor(false);
        placeRow = (placeRow + 1) % GRID_SIZE;
        drawPlacementCursor(true);
        pressed = true;
    }
    else if (M5.BtnC.wasPressed()) {
        drawPlacementCursor(false);
        placeCol = (placeCol + 1) % (GRID_SIZE - SHIP_LEN + 1);
        drawPlacementCursor(true);
        pressed = true;
    }
    else if (M5.BtnB.wasPressed()) {
        if (canPlaceShip(placeRow, placeCol)) {
            commitShip(placeRow, placeCol);
            drawPlacementGrid();
            drawPlacementCursor(true);
            M5.Lcd.fillRect(0, STATUS_Y, 320, 18, COL_STATUSBG);
            M5.Lcd.setTextColor(COL_SUBTEXT);
            M5.Lcd.setTextSize(1);
            M5.Lcd.setCursor(6, STATUS_Y + 5);
            char buf[40];
            snprintf(buf, sizeof(buf), "Ships: %d/%d placed", shipsPlaced, SHIPS_NEEDED);
            M5.Lcd.print(buf);
            if (shipsPlaced >= SHIPS_NEEDED) {
                delay(500);
                gs.phase = WAITING;
                drawWaitingScreen();
                initBLE();
            }
        } else {
            drawPlacementCursor(false);
            for (int dc = 0; dc < SHIP_LEN; dc++) {
                int c = placeCol + dc;
                if (c >= GRID_SIZE) continue;
                int x = GRID_OX + c * CELL_SIZE;
                int y = GRID_OY + placeRow * CELL_SIZE;
                M5.Lcd.drawRect(x, y, CELL_SIZE, CELL_SIZE, COL_HIT);
            }
            delay(200);
            drawPlacementGrid();
            drawPlacementCursor(true);
        }
        pressed = true;
    }
    if (pressed) lastBtnMs = now;
}

// ================================================================
//  BLE init
// ================================================================
void initBLE() {
    BLEDevice::init("Battleship");
    BLEDevice::setMTU(256);
    bleServer = BLEDevice::createServer();
    bleServer->setCallbacks(new ServerCallbacks());
    bleService = bleServer->createService(SERVICE_UUID);

    movChar = bleService->createCharacteristic(
        MOVE_CHAR_UUID,
        NIMBLE_PROPERTY::READ  |
        NIMBLE_PROPERTY::WRITE |
        NIMBLE_PROPERTY::NOTIFY
    );
    movChar->setCallbacks(new MoveCharCallbacks());
    movChar->setValue("");

    stateChar = bleService->createCharacteristic(
        STATE_CHAR_UUID,
        NIMBLE_PROPERTY::READ  |
        NIMBLE_PROPERTY::NOTIFY
    );

    bleService->start();
    BLEAdvertising *adv = BLEDevice::getAdvertising();
    adv->addServiceUUID(SERVICE_UUID);
    adv->setScanResponse(false);
    adv->setMinPreferred(0x00);
    BLEDevice::startAdvertising();
    Serial.println("[BLE] Advertising as 'Battleship'");
}

// ================================================================
//  Screens
// ================================================================
void drawWaitingScreen() {
    M5.Lcd.fillScreen(COL_BG);
    drawBanner("    B A T T L E S H I P    ", COL_GRIDLINE, COL_WHITE);
    M5.Lcd.setTextColor(COL_SUBTEXT);
    M5.Lcd.setTextSize(1);
    M5.Lcd.setCursor(72, 90);
    M5.Lcd.print("Waiting for opponent");
    M5.Lcd.setCursor(104, 108);
    M5.Lcd.print("via Bluetooth...");
    M5.Lcd.setTextColor(COL_SHIP);
    M5.Lcd.setCursor(134, 140);
    M5.Lcd.print("* * *");
    drawScoreboard();
}

void drawScoreboard() {
    M5.Lcd.fillRect(0, STATUS_Y, 320, 18, COL_STATUSBG);
    M5.Lcd.setTextColor(COL_GREEN);
    M5.Lcd.setTextSize(1);
    char buf[40];
    snprintf(buf, sizeof(buf), "YOU: %d  |  ENEMY: %d", scoreWins, scoreLosses);
    int textW = strlen(buf) * 6;
    M5.Lcd.setCursor((320 - textW) / 2, STATUS_Y + 5);
    M5.Lcd.print(buf);
}

void drawAttackScreen() {
    M5.Lcd.fillScreen(COL_BG);
    drawBanner(" A:ROW  C:COL  B:FIRE ", COL_GREEN, COL_BG);
    drawColRowLabels();
    drawGrid(gs.enemyGrid, false);
    drawCursor(cursorRow, cursorCol, true);
    drawStatusBar();
}

void drawDefendScreen() {
    M5.Lcd.fillScreen(COL_BG);
    drawBanner(" INCOMING  ENEMY FIRING ", COL_RED_BAN, COL_WHITE);
    drawColRowLabels();
    drawGrid(gs.myGrid, true);
    drawStatusBar();
}

void drawGrid(CellState grid[GRID_SIZE][GRID_SIZE], bool showShips) {
    for (int r = 0; r < GRID_SIZE; r++)
        for (int c = 0; c < GRID_SIZE; c++)
            drawCell(r, c, grid[r][c], showShips);
}

void drawCell(int row, int col, CellState state, bool showShip) {
    int x = GRID_OX + col * CELL_SIZE;
    int y = GRID_OY + row * CELL_SIZE;
    int inner = CELL_SIZE - 2;
    uint16_t fill;
    if      (state == SHIP && showShip) fill = COL_SHIP;
    else if (state == HIT)              fill = COL_HIT;
    else if (state == MISS)             fill = COL_MISS;
    else                                fill = COL_WATER;
    M5.Lcd.fillRect(x + 1, y + 1, inner, inner, fill);
    M5.Lcd.drawRect(x, y, CELL_SIZE, CELL_SIZE, COL_GRIDLINE);
    if (state == MISS)
        M5.Lcd.fillCircle(x + CELL_SIZE/2, y + CELL_SIZE/2, 4, COL_SUBTEXT);
    if (state == HIT) {
        M5.Lcd.drawLine(x+7, y+7, x+CELL_SIZE-7, y+CELL_SIZE-7, COL_WHITE);
        M5.Lcd.drawLine(x+CELL_SIZE-7, y+7, x+7, y+CELL_SIZE-7, COL_WHITE);
    }
}

void drawCursor(int row, int col, bool visible) {
    int x = GRID_OX + col * CELL_SIZE;
    int y = GRID_OY + row * CELL_SIZE;
    uint16_t color = visible ? COL_CURSOR : COL_GRIDLINE;
    M5.Lcd.drawRect(x,     y,     CELL_SIZE,     CELL_SIZE,     color);
    M5.Lcd.drawRect(x + 1, y + 1, CELL_SIZE - 2, CELL_SIZE - 2, color);
}

void drawBanner(const char* text, uint16_t bgColor, uint16_t textColor) {
    M5.Lcd.fillRect(0, 0, 320, BANNER_H, bgColor);
    M5.Lcd.setTextColor(textColor);
    M5.Lcd.setTextSize(1);
    M5.Lcd.setCursor(8, 9);
    M5.Lcd.print(text);
}

void drawColRowLabels() {
    const char* cols = "ABCDEF";
    M5.Lcd.setTextColor(COL_SUBTEXT);
    M5.Lcd.setTextSize(1);
    for (int i = 0; i < GRID_SIZE; i++) {
        M5.Lcd.setCursor(GRID_OX + i * CELL_SIZE + 12, GRID_OY - 10);
        M5.Lcd.print(cols[i]);
        M5.Lcd.setCursor(GRID_OX - 14, GRID_OY + i * CELL_SIZE + 11);
        M5.Lcd.print(i + 1);
    }
}

void drawStatusBar() {
    M5.Lcd.fillRect(0, STATUS_Y, 320, 18, COL_STATUSBG);
    M5.Lcd.setTextColor(COL_SUBTEXT);
    M5.Lcd.setTextSize(1);
    M5.Lcd.setCursor(6, STATUS_Y + 5);
    M5.Lcd.print("Mine:");
    for (int i = 0; i < gs.totalShipCells; i++) {
        uint16_t col = (i < gs.myShipsLeft) ? COL_SHIP : COL_SHIPDEAD;
        M5.Lcd.fillRect(44 + i * 10, STATUS_Y + 4, 8, 9, col);
    }
    M5.Lcd.setCursor(120, STATUS_Y + 5);
    M5.Lcd.print("Enemy:");
    for (int i = 0; i < gs.totalShipCells; i++) {
        uint16_t col = (i < gs.enemyShipsLeft) ? COL_SHIP : COL_SHIPDEAD;
        M5.Lcd.fillRect(164 + i * 10, STATUS_Y + 4, 8, 9, col);
    }
}

// ================================================================
//  Game over screen
// ================================================================
void drawGameOverScreen() {
    M5.Lcd.fillScreen(COL_BG);

    if (gs.iWon) {
        drawBanner("         GAME OVER         ", COL_GREEN, COL_BG);
        M5.Lcd.setTextSize(3);
        M5.Lcd.setTextColor(COL_GREEN);
        M5.Lcd.setCursor(74, 70);
        M5.Lcd.print("WINNER");
    } else {
        drawBanner("         GAME OVER         ", COL_RED_BAN, COL_WHITE);
        M5.Lcd.setTextSize(3);
        M5.Lcd.setTextColor(COL_HIT);
        M5.Lcd.setCursor(54, 70);
        M5.Lcd.print("DEFEATED");
    }

    // YOU | ENEMY score
    M5.Lcd.setTextSize(2);
    M5.Lcd.setTextColor(COL_WHITE);
    M5.Lcd.setCursor(60, 120);
    M5.Lcd.print("YOU   |   ENEMY");

    M5.Lcd.setTextSize(3);
    M5.Lcd.setTextColor(COL_GREEN);
    char scoreBuf[20];
    snprintf(scoreBuf, sizeof(scoreBuf), " %d    |    %d", scoreWins, scoreLosses);
    M5.Lcd.setCursor(44, 148);
    M5.Lcd.print(scoreBuf);

    M5.Lcd.setTextSize(1);
    M5.Lcd.setTextColor(COL_SUBTEXT);
    M5.Lcd.setCursor(72, 200);
    M5.Lcd.print("Press reset to play again");

    while (true) { delay(1000); }
}

// ================================================================
//  Battle button handler
// ================================================================
void handleButtons() {
    unsigned long now = millis();
    if (now - lastBtnMs < BTN_DEBOUNCE_MS) return;
    bool pressed = false;

    if (M5.BtnA.wasPressed()) {
        drawCursor(cursorRow, cursorCol, false);
        drawCell(cursorRow, cursorCol, gs.enemyGrid[cursorRow][cursorCol], false);
        cursorRow = (cursorRow + 1) % GRID_SIZE;
        drawCursor(cursorRow, cursorCol, true);
        pressed = true;
    }
    else if (M5.BtnC.wasPressed()) {
        drawCursor(cursorRow, cursorCol, false);
        drawCell(cursorRow, cursorCol, gs.enemyGrid[cursorRow][cursorCol], false);
        cursorCol = (cursorCol + 1) % GRID_SIZE;
        drawCursor(cursorRow, cursorCol, true);
        pressed = true;
    }
    else if (M5.BtnB.wasPressed()) {
        CellState target = gs.enemyGrid[cursorRow][cursorCol];
        if (target == HIT || target == MISS) {
            drawCursor(cursorRow, cursorCol, false);
            M5.Lcd.drawRect(GRID_OX + cursorCol * CELL_SIZE,
                            GRID_OY + cursorRow * CELL_SIZE,
                            CELL_SIZE, CELL_SIZE, COL_HIT);
            delay(200);
            drawCursor(cursorRow, cursorCol, true);
        } else {
            applyMyShot(cursorRow, cursorCol);
        }
        pressed = true;
    }
    if (pressed) lastBtnMs = now;
}

// ================================================================
//  Game logic
// ================================================================
void applyMyShot(int row, int col) {
    Serial.printf("[GAME] I fire at (%d,%d)\n", row, col);
    gs.enemyGrid[row][col] = MISS;
    gs.myTurn = false;
    sendMove(row, col);
    delay(200);
    sendStateUpdate();
    delay(200);
    drawDefendScreen();
}

void applyEnemyShot(int row, int col) {
    Serial.printf("[GAME] Enemy fires at (%d,%d)\n", row, col);

    bool wasHit = (gs.myGrid[row][col] == SHIP);
    if (wasHit) {
        gs.myGrid[row][col] = HIT;
        gs.myShipsLeft--;
        setFan(false);
        Serial.printf("[GAME] HIT on my fleet! Left: %d\n", gs.myShipsLeft);
    } else {
        gs.myGrid[row][col] = MISS;
        // Spin fan if miss was within 3 cells of an M5 ship
        int dist = nearestShipDistance(row, col);
        Serial.printf("[FAN] Miss dist=%d\n", dist);
        if (dist <= 3) {
            setFan(true);
            delay(1500);
            setFan(false);
        }
    }

    drawCell(row, col, gs.myGrid[row][col], true);
    drawStatusBar();

    if (gs.myShipsLeft <= 0) {
        gs.phase = OVER;
        gs.iWon  = false;
        scoreLosses++;
        setFan(false);
        sendStateUpdate();
        delay(300);
        postMatchResult();
        drawGameOverScreen();
        return;
    }

    gs.myTurn = true;
    delay(100);
    sendStateUpdate();
    delay(400);
    cursorRow = 0;
    cursorCol = 0;
    drawAttackScreen();
}

void sendMove(int row, int col) {
    if (!deviceConnected) return;
    StaticJsonDocument<32> doc;
    doc["r"] = row;
    doc["c"] = col;
    char buf[32];
    serializeJson(doc, buf);
    movChar->setValue(buf);
    movChar->notify();
    Serial.printf("[BLE] Move sent: %s\n", buf);
}

void sendStateUpdate() {
    if (!deviceConnected) return;
    StaticJsonDocument<128> doc;
    doc["phase"]  = (int)gs.phase;
    doc["myTurn"] = gs.myTurn;
    doc["myLeft"] = gs.myShipsLeft;
    doc["enLeft"] = gs.enemyShipsLeft;
    doc["won"]    = gs.iWon;
    char buf[128];
    serializeJson(doc, buf);
    stateChar->setValue(buf);
    stateChar->notify();
    Serial.printf("[BLE] State sent: %s\n", buf);
}
