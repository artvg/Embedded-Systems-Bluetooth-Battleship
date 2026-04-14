#include <NimBLEDevice.h>
#include <M5Core2.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <Adafruit_seesaw.h> 

//  UUIDs — must match Flutter exactly
#define SERVICE_UUID    "f4893cb2-c54a-4c85-9339-4c03f3f19077"
#define MOVE_CHAR_UUID  "ceb4ef8c-12b5-4932-b2d5-3bf26fe18af5"
#define STATE_CHAR_UUID "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

//  Grid layout
#define GRID_SIZE  6
#define CELL_SIZE  32
#define GRID_OX    64
#define GRID_OY    36
#define BANNER_H   26
#define STATUS_Y   222

//  Colors
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

//  Cell states
enum CellState { EMPTY, SHIP, HIT, MISS };

//  Game phases
enum GamePhase { WAITING, BATTLE, OVER };

//  Game state
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

//  BLE handles
BLEServer         *bleServer;
BLEService        *bleService;
BLECharacteristic *movChar;
BLECharacteristic *stateChar;
bool deviceConnected = false;

//  Pending enemy move 
volatile bool pendingMove = false;
volatile int  pendingRow  = -1;
volatile int  pendingCol  = -1;

//  Pre placed ships 
const int MY_SHIPS[3][2] = { {1,1}, {3,3}, {5,0} };

//  GamePad QT - Adafruit seesaw I2C address
#define GAMEPAD_ADDR  0x50

Adafruit_seesaw gamepad;
bool gamepadReady = false;

// Seesaw button bitmasks for GamePad QT
#define BTN_A       (1UL << 6)
#define BTN_B       (1UL << 7)
#define BTN_START   (1UL << 16)
#define BTN_SELECT  (1UL << 14)
#define DPAD_UP     (1UL << 2)
#define DPAD_DOWN   (1UL << 4)
#define DPAD_LEFT   (1UL << 3)
#define DPAD_RIGHT  (1UL << 5)
#define ALL_BUTTONS (BTN_A | BTN_B | BTN_START | BTN_SELECT | \
                     DPAD_UP | DPAD_DOWN | DPAD_LEFT | DPAD_RIGHT)

//  Cursor state - which cell is currently highlighted on attack grid
int  cursorRow    = 0;
int  cursorCol    = 0;
bool cursorActive = true;   

// Debounce - minimum ms between d pad movements
#define DPAD_REPEAT_MS  160
unsigned long lastDpadMs = 0;

//  Forward declarations
void initGame();
void initGamepad();
void drawAttackScreen();
void drawDefendScreen();
void drawWaitingScreen();
void drawGameOverScreen();
void drawGrid(CellState grid[GRID_SIZE][GRID_SIZE], bool showShips);
void drawCell(int row, int col, CellState state, bool showShip);
void drawCursor(int row, int col, bool visible);
void drawBanner(const char* text, uint16_t bgColor, uint16_t textColor);
void drawStatusBar();
void drawColRowLabels();
void handleGamepad();
void applyMyShot(int row, int col);
void applyEnemyShot(int row, int col);
void sendMove(int row, int col);
void sendStateUpdate();

//  BLE - Flutter writes a move here
class MoveCharCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pChar) {
        if (gs.phase != BATTLE || gs.myTurn) return;

        std::string raw = pChar->getValue();
        if (raw.length() == 0) return;

        StaticJsonDocument<64> doc;
        if (deserializeJson(doc, raw.c_str())) return;

        int r = doc["r"] | -1;
        int c = doc["c"] | -1;
        if (r < 0 || r >= GRID_SIZE || c < 0 || c >= GRID_SIZE) return;

        pendingRow  = r;
        pendingCol  = c;
        pendingMove = true;

        Serial.printf("[BLE] Enemy fires at (%d,%d)\n", r, c);
    }
};

//  BLE - connection events
class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer *pServer) {
        deviceConnected = true;
        Serial.println("[BLE] Flutter connected");
        gs.phase = BATTLE;
        sendStateUpdate();
        drawAttackScreen();
    }
    void onDisconnect(BLEServer *pServer) {
        deviceConnected = false;
        Serial.println("[BLE] Disconnected - restarting advertising");
        pServer->startAdvertising();
        gs.phase = WAITING;
        drawWaitingScreen();
    }
};

//  Setup
void setup() {
    M5.begin();
    M5.Lcd.setRotation(1);
    Serial.begin(115200);

    initGamepad();   
    initGame();

    // Show your fleet for 2 seconds on boot so you can confirm ship placement
    M5.Lcd.fillScreen(COL_BG);
    drawBanner("  YOUR SHIPS  (memorize!)", COL_GRIDLINE, COL_WHITE);
    drawColRowLabels();
    drawGrid(gs.myGrid, true);  
    drawStatusBar();
    delay(2500);

    drawWaitingScreen();

    BLEDevice::init("Battleship");
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

void loop() {
    M5.update();

    if (pendingMove) {
        pendingMove = false;
        applyEnemyShot(pendingRow, pendingCol);
    }

    if (gs.phase == BATTLE && gs.myTurn) {
        handleGamepad();
    }

    delay(20);
}

//  Init game state
void initGame() {
    memset(&gs, 0, sizeof(gs));

    for (int r = 0; r < GRID_SIZE; r++)
        for (int c = 0; c < GRID_SIZE; c++) {
            gs.myGrid[r][c]    = EMPTY;
            gs.enemyGrid[r][c] = EMPTY;
        }

    for (int i = 0; i < 3; i++) {
        int r = MY_SHIPS[i][0];
        int c = MY_SHIPS[i][1];
        gs.myGrid[r][c]     = SHIP;
        gs.myGrid[r][c + 1] = SHIP;
    }

    gs.totalShipCells = 6;
    gs.myShipsLeft    = 6;
    gs.enemyShipsLeft = 6;
    gs.myTurn         = true;
    gs.phase          = WAITING;
    gs.iWon           = false;
}

//  Waiting screen
void drawWaitingScreen() {
    M5.Lcd.fillScreen(COL_BG);
    drawBanner("    B A T T L E S H I P    ", COL_GRIDLINE, COL_WHITE);

    M5.Lcd.setTextColor(COL_SUBTEXT);
    M5.Lcd.setTextSize(1);
    M5.Lcd.setCursor(72, 100);
    M5.Lcd.print("Waiting for opponent");
    M5.Lcd.setCursor(104, 118);
    M5.Lcd.print("via Bluetooth...");

    M5.Lcd.setTextColor(COL_SHIP);
    M5.Lcd.setCursor(134, 155);
    M5.Lcd.print("* * *");
}

//  Attack screen - my turn, fog of war grid
void drawAttackScreen() {
    M5.Lcd.fillScreen(COL_BG);
    drawBanner(" D-PAD: AIM   A: FIRE ", COL_GREEN, COL_BG);
    drawColRowLabels();
    drawGrid(gs.enemyGrid, false);
    drawCursor(cursorRow, cursorCol, true); 
    drawStatusBar();
}

//  Defend screen - enemys turn, show my fleet
void drawDefendScreen() {
    M5.Lcd.fillScreen(COL_BG);
    drawBanner(" INCOMING  ENEMY FIRING ", COL_RED_BAN, COL_WHITE);
    drawColRowLabels();
    drawGrid(gs.myGrid, true);
    drawStatusBar();
}

//  Draw full grid
void drawGrid(CellState grid[GRID_SIZE][GRID_SIZE], bool showShips) {
    for (int r = 0; r < GRID_SIZE; r++)
        for (int c = 0; c < GRID_SIZE; c++)
            drawCell(r, c, grid[r][c], showShips);
}

//  Draw one cell
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

    if (state == MISS) {
        M5.Lcd.fillCircle(x + CELL_SIZE/2, y + CELL_SIZE/2, 4, COL_SUBTEXT);
    }

    if (state == HIT) {
        M5.Lcd.drawLine(x+7, y+7, x+CELL_SIZE-7, y+CELL_SIZE-7, COL_WHITE);
        M5.Lcd.drawLine(x+CELL_SIZE-7, y+7, x+7, y+CELL_SIZE-7, COL_WHITE);
    }
}

//  Draw / erase cursor highlight on a cell
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

//  Column (A–F) and row (1–6) labels
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

//  Bottom status bar - ship health as small blocks
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

//  Init GamePad QT
void initGamepad() {
    Wire.begin();
    if (!gamepad.begin(GAMEPAD_ADDR)) {
        Serial.println("[GAMEPAD] Not found at 0x50 - check wiring");
        gamepadReady = false;
        return;
    }
    // Set all button pins as inputs with pull-ups
    gamepad.pinModeBulk(ALL_BUTTONS, INPUT_PULLUP);
    gamepadReady = true;
    Serial.println("[GAMEPAD] GamePad QT ready");
}

//  Handle GamePad QT input during attack phase
void handleGamepad() {
    if (!gamepadReady) return;

    unsigned long now = millis();
    if (now - lastDpadMs < DPAD_REPEAT_MS) return; 

    // Read all buttons - LOW means pressed
    uint32_t buttons = gamepad.digitalReadBulk(ALL_BUTTONS);

    int newRow = cursorRow;
    int newCol = cursorCol;
    bool moved = false;

    if (!(buttons & DPAD_UP))    { newRow--; moved = true; }
    if (!(buttons & DPAD_DOWN))  { newRow++; moved = true; }
    if (!(buttons & DPAD_LEFT))  { newCol--; moved = true; }
    if (!(buttons & DPAD_RIGHT)) { newCol++; moved = true; }

    // Clamp within grid
    newRow = constrain(newRow, 0, GRID_SIZE - 1);
    newCol = constrain(newCol, 0, GRID_SIZE - 1);

    if (moved && (newRow != cursorRow || newCol != cursorCol)) {
        drawCursor(cursorRow, cursorCol, false);
        drawCell(cursorRow, cursorCol, gs.enemyGrid[cursorRow][cursorCol], false);

        cursorRow = newRow;
        cursorCol = newCol;
        drawCursor(cursorRow, cursorCol, true);
        lastDpadMs = now;
    }

    // A button fire at cursor cell
    if (!(buttons & BTN_A)) {
        CellState target = gs.enemyGrid[cursorRow][cursorCol];
        if (target == HIT || target == MISS) {
            // Already shot — flash cursor red briefly as feedback
            drawCursor(cursorRow, cursorCol, false);
            M5.Lcd.drawRect(GRID_OX + cursorCol * CELL_SIZE,
                            GRID_OY + cursorRow * CELL_SIZE,
                            CELL_SIZE, CELL_SIZE, COL_HIT);
            delay(200);
            drawCursor(cursorRow, cursorCol, true);
        } else {
            applyMyShot(cursorRow, cursorCol);
        }
        lastDpadMs = now + 300;   // extra cooldown after fire
    }

    // B button - move cursor back to (0,0) as a "cancel/reset" feel
    if (!(buttons & BTN_B)) {
        drawCursor(cursorRow, cursorCol, false);
        drawCell(cursorRow, cursorCol, gs.enemyGrid[cursorRow][cursorCol], false);
        cursorRow = 0;
        cursorCol = 0;
        drawCursor(cursorRow, cursorCol, true);
        lastDpadMs = now;
    }
}

//  I fired - send to Flutter, swap to defend screen
void applyMyShot(int row, int col) {
    Serial.printf("[GAME] I fire at (%d,%d)\n", row, col);

    gs.enemyGrid[row][col] = MISS;  // Flutter confirms
    gs.myTurn = false;
    sendMove(row, col);
    drawDefendScreen();             // swap screen while waiting
}

//  Enemy fired - apply hit/miss, check game over, swap screen
void applyEnemyShot(int row, int col) {
    Serial.printf("[GAME] Enemy fires at (%d,%d)\n", row, col);

    if (gs.myGrid[row][col] == SHIP) {
        gs.myGrid[row][col] = HIT;
        gs.myShipsLeft--;
        Serial.printf("[GAME] HIT on my fleet! Left: %d\n", gs.myShipsLeft);
    } else {
        gs.myGrid[row][col] = MISS;
    }

    // Instant feedback - redraw just the hit cell
    drawCell(row, col, gs.myGrid[row][col], true);
    drawStatusBar();

    if (gs.myShipsLeft <= 0) {
        gs.phase = OVER;
        gs.iWon  = false;
        sendStateUpdate();
        delay(800);
        drawGameOverScreen();
        return;
    }

    gs.myTurn = true;
    sendStateUpdate();
    delay(500);
    cursorRow = 0; cursorCol = 0;   
    drawAttackScreen();
}

//  Send move
void sendMove(int row, int col) {
    if (!deviceConnected) return;
    StaticJsonDocument<32> doc;
    doc["r"] = row;
    doc["c"] = col;
    char buf[32];
    serializeJson(doc, buf);
    movChar->setValue(buf);
    movChar->notify();
    Serial.printf("[BLE] Sent move: %s\n", buf);
}

//  Send state - Flutter uses this to sync and swap its screen
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
    Serial.printf("[BLE] Sent state: %s\n", buf);
}

//  Game over screen
void drawGameOverScreen() {
    M5.Lcd.fillScreen(COL_BG);

    if (gs.iWon) {
        drawBanner("         GAME OVER         ", COL_GREEN, COL_BG);
        M5.Lcd.setTextSize(3);
        M5.Lcd.setTextColor(COL_GREEN);
        M5.Lcd.setCursor(74, 90);
        M5.Lcd.print("WINNER");
    } else {
        drawBanner("         GAME OVER         ", COL_RED_BAN, COL_WHITE);
        M5.Lcd.setTextSize(3);
        M5.Lcd.setTextColor(COL_HIT);
        M5.Lcd.setCursor(54, 90);
        M5.Lcd.print("DEFEATED");
    }

    M5.Lcd.setTextSize(1);
    M5.Lcd.setTextColor(COL_SUBTEXT);
    M5.Lcd.setCursor(88, 165);
    M5.Lcd.print("Press reset to replay");

    while (true) { delay(1000); }
}