# Battleship BLE — Flutter Client

Flutter app that connects to the **M5Stack Core2** Battleship firmware over
Bluetooth Low Energy (BLE) and lets you play a full two-player Battleship game.

---

## Architecture

```
Flutter Phone  ←──────────── BLE ────────────→  M5Stack Core2
    │                                                │
    │  writes {"r":row, "c":col}  → movChar         │
    │  reads  {"r":row, "c":col}  ← movChar notify  │
    │  reads  state JSON          ← stateChar notify │
```

### BLE Characteristics

| Characteristic | UUID                                   | Direction           |
|----------------|----------------------------------------|---------------------|
| **movChar**    | `ceb4ef8c-12b5-4932-b2d5-3bf26fe18af5` | Flutter→M5 (write) & M5→Flutter (notify) |
| **stateChar**  | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` | M5→Flutter (notify) |

### Protocol

**M5Stack fires a shot** (movChar notify):
```json
{ "r": 2, "c": 4 }
```

**Flutter fires a shot** (Flutter writes to movChar):
```json
{ "r": 1, "c": 3 }
```

**M5Stack state update** (stateChar notify):
```json
{
  "phase":  1,       // 0=waiting  1=battle  2=game-over
  "myTurn": true,    // true = M5 fires next
  "myLeft": 5,       // M5's remaining ship cells (used for hit detection)
  "enLeft": 6,       // Flutter's cells as M5 sees them (not reliable — ignored)
  "won":    false    // true = M5 won (only meaningful when phase=2)
}
```

### Turn Flow

```
M5 connects  →  stateChar: {phase:1, myTurn:true}
     ↓
M5 fires     →  movChar notify: {r, c}
     ↓
Flutter applies hit/miss to MY FLEET grid
Flutter's turn becomes active
     ↓
Flutter taps attack grid  →  Flutter writes {r, c} to movChar
     ↓
M5 applies hit/miss to its own grid
M5 sends stateChar: {myLeft: updated}
     ↓
Flutter detects hit if m5ShipsLeft decreased
     ↓
Repeat…
```

### Game Over Detection

| Who loses | How detected |
|-----------|--------------|
| **M5 loses** | M5 sends `stateChar {phase:2, won:false}` → Flutter shows **VICTORY** |
| **Flutter loses** | Flutter's `myShipsLeft` reaches 0 → Flutter shows **DEFEATED** |

---

## Setup

### 1. Install Flutter
https://docs.flutter.dev/get-started/install

### 2. Get dependencies
```bash
flutter pub get
```

### 3. Android — make sure `minSdkVersion` = 21
Already set in `android/app/build.gradle`.

### 4. iOS — add Bluetooth permissions
Already in `ios/Runner/Info.plist`. You'll need a physical device (BLE doesn't work in Simulator).

### 5. Flash the M5Stack firmware
Upload the provided `.ino` sketch to your M5Stack Core2.

### 6. Run
```bash
flutter run
```

---

## Game Screens

| Screen | Description |
|--------|-------------|
| **Placement** | Tap the grid to place 3 × 2-cell horizontal ships. Tap "Find M5Stack" when ready. |
| **Scan** | Auto-scans and connects to the first device advertising "Battleship-M5". |
| **Game** | Top grid = your fleet (defense). Bottom grid = attack (tap to fire on your turn). Status bar shows ship health for both sides. |
| **Game Over** | Animated overlay showing VICTORY or DEFEATED with ship stats and a Play Again button. |

---

## Dependencies

```yaml
flutter_blue_plus: ^1.31.15   # BLE communication
provider:          ^6.1.2     # State management
permission_handler:^11.3.0    # Runtime BLE permissions
```
