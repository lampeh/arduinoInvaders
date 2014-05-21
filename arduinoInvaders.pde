
// pin  0:                            - (serial RX)
// pin  1:                            - (serial TX)
// pin  2: left top button interrupt
// pin  3: right top button interrupt - (PWM interference while tone() - http://arduino.cc/en/Reference/Tone)
// pin  4: speaker
// pin  5: LCD backlight+             - (PWM increased - http://arduino.cc/en/Reference/AnalogWrite)
// pin  6: LCD RS                     - (PWM increased - http://arduino.cc/en/Reference/AnalogWrite)
// pin  7: left bottom button
// pin  8: right bottom button
// pin  9: left LED                   - (PWM)
// pin 10: right LED                  - (PWM)
// pin 11: LCD E                      - (PWM interference while tone() - http://arduino.cc/en/Reference/Tone)
// pin 12:  
// pin 13: status LED                 - (always reads LOW w/ internal pullup - http://arduino.cc/en/Tutorial/DigitalPins)

// pin A0: LCD D4
// pin A1: LCD D5
// pin A2: LCD D6
// pin A3: LCD D7
// pin A4:
// pin A5: random seed

// TODO: optimize for-loops, reduce redundancy and code duplication
// TODO: buttons pressed in demo mode should start a new game
// TODO: the mixed use of rows and columns is confusing. LCD cols == game rows, 1 LCD row == 2 game columns


// max. return value of millis()
const unsigned long MAXULONG = ~0UL;


// include the library code:
#include <LiquidCrystal.h>
#include "pitches.h"


// serial I/O rate (for debug output)
const unsigned long serialRate = 115200;


const unsigned long timeBase = 250;

const char titleRow1[] = "     FNORD\0"; // "      "
const char titleRow2[] =     "INVADERS    \0"; // "    "
const unsigned long titleScrollInterval = timeBase / 2;

// notes in the melody:
const int titleMelodyNotes = 8;
const int titleMelody[8] = {
    NOTE_C4, NOTE_G3, NOTE_G3, NOTE_A3, NOTE_G3, 0, NOTE_B3, NOTE_C4
};

// note durations: 4 = quarter note, 8 = eighth note, etc.:
const int titleNoteDurations[] = {
    4, 16, 16, 8, 8, 8, 8, 8 
};

const char gameOverRow1[] = "GAME\0";
const char gameOverRow2[] = "O V E R\0";
//const unsigned long gameOverScrollInterval = timeBase / 2;

const int gameOverMelodyNotes = 8;
const int gameOverMelody[8] = {
    NOTE_A3, NOTE_A3, NOTE_G3, NOTE_B3, NOTE_C4, 0, NOTE_G3, NOTE_A3
};

// note durations: 4 = quarter note, 8 = eighth note, etc.:
const int gameOverNoteDurations[] = {
    4, 16, 16, 8, 8, 8, 8, 8
};

// how long to wait for button after title display (in ms)
const unsigned long titleTimeout = 8000;

// interval between turns (in ms)
const unsigned long playInterval = timeBase * 1;

// interval between invader respawn (in ms)
// TODO: decrease with time
const unsigned long defaultInvaderIntervalMin = timeBase * 1;
const unsigned long defaultInvaderIntervalMax = timeBase * 6;
const unsigned long demoInvaderIntervalMin = timeBase * 1;
const unsigned long demoInvaderIntervalMax = timeBase * 3;
// max. number of invaders to spawn per row
const unsigned invaderSpawnMax = 1;
unsigned long invaderIntervalMin;
unsigned long invaderIntervalMax;

// refresh interval for two characters in a single LCD cell (in ms)
const unsigned long flickerInterval = 10;

// TODO: better debounce handling of buttons
//const int playerControlIntervalMin = timeBase / 2;
//const int playerControlIntervalMin = timeBase;
const unsigned long playerControlIntervalMin = 150;


// hardware interfaces

// status LED pin
const int ledInfo = 13;

// output pin for tone()
const int speakerPin = 4;

// use unconnected analog input as random seed
const int randomPin = 5;

// game pad
// PWM available
const int ledLeft = 10;
const int ledRight = 9;
// top buttons trigger interrupts
const int buttonLeftTop = 3;
const int buttonLeftIRQ = 1;
const int buttonRightTop = 2;
const int buttonRightIRQ = 0;
// bottom buttons must be polled in loop()
const int buttonLeftBottom = 8;
const int buttonRightBottom = 7;

// LCD connector
const int lcdRsPin = 5;
//const int lcdRwPin = -1;  // you can connect R/W to GND and save a pin
const int lcdEnablePin = 11;
const int lcdD4Pin = A0;
const int lcdD5Pin = A1;
const int lcdD6Pin = A2;
const int lcdD7Pin = A3;
const int lcdBacklightPin = 6;  // you can connect backlight+ to 5V via fixed resistor and save a pin

const int lcdCols = 16;
const int lcdRows = 2;

// initialize LCD functions
//LiquidCrystal lcd(lcdRsPin, lcdRwPin, lcdEnablePin, lcdD4Pin, lcdD5Pin, lcdD6Pin, lcdD7Pin);
LiquidCrystal lcd(lcdRsPin, lcdEnablePin, lcdD4Pin, lcdD5Pin, lcdD6Pin, lcdD7Pin);



// characters from the LCD default set
const byte lcdCharSpace = 0x20;

// custom LCD characters in play state
const byte lcdCharInvaderRightID = 0;
const byte lcdCharInvaderLeftID = 1;
const byte lcdCharPlayerRightID = 2;
const byte lcdCharPlayerLeftID = 3;
const byte lcdCharShotRightID = 4;
const byte lcdCharShotLeftID = 5;
const byte lcdCharInvaderHitID = 6;
const byte lcdCharPlayerHitID = 7;

// charTypes enum value must match lcdChars* array index
typedef enum { 
    none=0, invader=1, player=2, shot=3, invaderHit=4, playerHit=5
} charTypes;

const byte lcdCharsRight[6] = { 
    lcdCharSpace, lcdCharInvaderRightID, lcdCharPlayerRightID, lcdCharShotRightID, lcdCharInvaderHitID, lcdCharPlayerHitID
};

const byte lcdCharsLeft[6] = { 
    lcdCharSpace, lcdCharInvaderLeftID, lcdCharPlayerLeftID, lcdCharShotLeftID, lcdCharInvaderHitID, lcdCharPlayerHitID
};


// pointers into title strings, used for scrolling
const char *titleRow1Ptr;
const char *titleRow2Ptr;

// title finished scrolling in both rows
boolean titleFinished;


// states for switch in loop()
typedef enum { 
    titleDisplayInit, titleDisplayScroll, playInit, playRun, gameOverDisplayInit, gameOverDisplayScroll, paused, noOp
} gameStates;
gameStates gameState;


// relict from an older version. really necessary?
typedef enum { 
    left, right
} playerStates;
playerStates playerState;

unsigned int playerPos;
unsigned int playerLifes;


// loop timers
unsigned long lastMillis = 0;
unsigned long elapsedTitleScrollMillis = 0;
unsigned long elapsedPlayMillis = 0;
unsigned long elapsedInvaderMillis = 0;
unsigned long elapsedFlickerMillis = 0;
unsigned long elapsedNoteMillis = 0;
unsigned long elapsedWobbleBacklightMillis = 0;
unsigned long elapsedDemoMillis = 0;
unsigned long lastPlayerControlMillis = 0;


// used in loop() to play tunes
unsigned int currentNoteIdx;
unsigned long currentNoteDuration;
boolean melodyPause;
boolean melodyFinished;


// flicker backlight: PWM-dim from 100% (255) to 0 and back on
boolean wobbleBacklight = false;
int wobbleBacklightValue = 255;
const unsigned long wobbleBacklightInterval = 1;
const int wobbleBacklightStep = 4;


// the battlefield
charTypes gameArena[lcdRows*2][lcdCols];


// used in loop() to display parallel half-columns
boolean flickerState = false;


// ignore button interrupts if false
boolean leftButtonEnabled = false;
boolean rightButtonEnabled = false;
// button interrupts set variables to true
volatile boolean leftButtonPressed;
volatile boolean rightButtonPressed;


// demo mode
boolean demo;
boolean demoHaveTarget;
boolean demoMove;
unsigned int demoTargetPos;
// reuse left/right enum
playerStates demoMovePos;
// how long to play demo before returning to title (in ms)
unsigned long demoInterval = 30000;


// clear gameArena. does not update display
void wipeDisplayMap() {
    for (int i=0; i < lcdRows*2; i++) {
        for (int j=0; j < lcdCols; j++) {
            gameArena[i][j] = none;
        }
    }
}

// write gameArena to LCD
void updateDisplay() {
    for (int i=0; i < lcdRows; i++) {
        lcd.setCursor(0, i);
        for (int j=0; j < lcdCols; j++) {
            lcd.write(lcdCharsLeft[gameArena[(i*2)][j]]);
            // overwrite half-column characters
            if (gameArena[(i*2)+1][j] != none) {
                lcd.setCursor(j, i);
                lcd.write(lcdCharsRight[gameArena[(i*2)+1][j]]);
            }
        }
    }
    flickerState = false;

    // display playerLifes with ':' and '.' in bottom row
    for (int i=0; i < playerLifes/2; i++) {
        lcd.setCursor(0, (lcdRows-1) - i);
        lcd.write(':');
    }
    for (int i=0; i < playerLifes % 2; i++) {
        lcd.setCursor(0, (lcdRows-1) - (i + (playerLifes/2)));
        lcd.write('.');
    }
}


// button interrupts
void leftButtonInterrupt() {
    if (leftButtonEnabled) {
        leftButtonPressed = true;
        digitalWrite(ledLeft, HIGH);
    }
}

void rightButtonInterrupt() {
    if (rightButtonEnabled) {
        rightButtonPressed = true;
        digitalWrite(ledRight, HIGH);
    }
}


// load custom LCD characters for play state into CGRAM
void uploadGameChars() {
    /*
    byte lcdCharEmpty[8] = {
     B00000,
     B00000,
     B00000,
     B00000,
     B00000,
     B00000,
     B00000,
     B00000,
     };
     */

    byte lcdCharInvaderRight[8] = {
        B00000,
        B00000,
        B00000,
        B10011,
        B01101,
        B00111,
        B01101,
        B10011,
    };

    byte lcdCharInvaderLeft[8] = {
        B10011,
        B01101,
        B00111,
        B01101,
        B10011,
        B00000,
        B00000,
        B00000,
    };

    byte lcdCharPlayerRight[8] = {
        B00000,
        B00000,
        B00000,
        B11100,
        B00110,
        B11011,
        B00110,
        B11100,
    };

    byte lcdCharPlayerLeft[8] = {
        B11100,
        B00110,
        B11011,
        B00110,
        B11100,
        B00000,
        B00000,
        B00000,
    };

    byte lcdCharShotRight[8] = {
        B00000,
        B00000,
        B00000,
        B00000,
        B00000,
        B11011,
        B00000,
        B00000,
    };

    byte lcdCharShotLeft[8] = {
        B00000,
        B00000,
        B11011,
        B00000,
        B00000,
        B00000,
        B00000,
        B00000,
    };

    byte lcdCharInvaderHit[8] = {
        B10001,
        B01010,
        B10001,
        B10110,
        B01101,
        B10001,
        B01010,
        B10001,
    };

    byte lcdCharPlayerHit[8] = {
        B00010,
        B01000,
        B10001,
        B11010,
        B01010,
        B10001,
        B01000,
        B00010,
    };


    lcd.createChar(lcdCharInvaderRightID, lcdCharInvaderRight);
    lcd.createChar(lcdCharInvaderLeftID, lcdCharInvaderLeft);
    lcd.createChar(lcdCharPlayerRightID, lcdCharPlayerRight);
    lcd.createChar(lcdCharPlayerLeftID, lcdCharPlayerLeft);
    lcd.createChar(lcdCharShotRightID, lcdCharShotRight);
    lcd.createChar(lcdCharShotLeftID, lcdCharShotLeft);
    lcd.createChar(lcdCharInvaderHitID, lcdCharInvaderHit);
    lcd.createChar(lcdCharPlayerHitID, lcdCharPlayerHit);
}


// initialize pin modes, attach interrupt functions
void setup() {
    // status LED on
    pinMode(ledInfo, OUTPUT);
    digitalWrite(ledInfo, HIGH);

    pinMode(ledLeft, OUTPUT);
    digitalWrite(ledLeft, HIGH);

    pinMode(ledRight, OUTPUT);
    digitalWrite(ledRight, HIGH);

    pinMode(lcdBacklightPin, OUTPUT);
    digitalWrite(lcdBacklightPin, HIGH);

    // buttons pulled HIGH by internal resistors
    pinMode(buttonLeftTop, INPUT);
    digitalWrite(buttonLeftTop, HIGH);
    leftButtonPressed = false;
    leftButtonEnabled = false;
    attachInterrupt(buttonLeftIRQ, leftButtonInterrupt, FALLING);

    pinMode(buttonRightTop, INPUT);
    digitalWrite(buttonRightTop, HIGH);
    rightButtonPressed = false;
    rightButtonEnabled = false;
    attachInterrupt(buttonRightIRQ, rightButtonInterrupt, FALLING);

    pinMode(buttonLeftBottom, INPUT);
    digitalWrite(buttonLeftBottom, HIGH);

    pinMode(buttonRightBottom, INPUT);
    digitalWrite(buttonRightBottom, HIGH);

    // set up the LCD's number of columns and rows: 
    lcd.begin(lcdCols, lcdRows);

    lcd.clear();
    lcd.noAutoscroll();

    wipeDisplayMap();
    gameState = titleDisplayInit;

    randomSeed(analogRead(randomPin));

    lastMillis = millis();

    Serial.begin(serialRate);
    Serial.println("\nSetup complete");

    tone(speakerPin, 2600, 40);

    // status LED off
    digitalWrite(ledInfo, LOW);
    digitalWrite(ledLeft, LOW);
    digitalWrite(ledRight, LOW);
}


void loop() {
    unsigned long currentMillis;
    unsigned long elapsedMillis;
    charTypes currentChar;
    const byte *rowChars;


    currentMillis = millis();

    // millis() will overflow after approximately 50 days.
    if (currentMillis < lastMillis) {
        elapsedMillis = (MAXULONG - lastMillis) + currentMillis;
    } else {
        elapsedMillis = currentMillis - lastMillis;
    }
    lastMillis = currentMillis;
    // Serial.print("elapsedMillis=");
    // Serial.println(elapsedMillis);

    elapsedWobbleBacklightMillis += elapsedMillis;
    if (wobbleBacklight && elapsedWobbleBacklightMillis > wobbleBacklightInterval) {
        elapsedWobbleBacklightMillis = 0;
        if (wobbleBacklightValue > -256) {
            analogWrite(lcdBacklightPin, abs(wobbleBacklightValue));
            wobbleBacklightValue -= wobbleBacklightStep;
        } else {
            wobbleBacklightValue = 255;
            digitalWrite(lcdBacklightPin, HIGH);
            wobbleBacklight = false;
        }
    }

    switch (gameState) {
    case titleDisplayInit:
        // TODO: create custom title chars
        // TODO: load title chars into CGRAM

        // upper row scrolls from bottom to center, pointer moves backwards
        titleRow1Ptr = titleRow1 + strlen(titleRow1)-1;
        // lower row scrolls from top to center, pointer moves forward
        titleRow2Ptr = titleRow2;

        lcd.clear();

        elapsedTitleScrollMillis = 0;
        titleFinished = false;
        
        elapsedNoteMillis = 0;
        currentNoteIdx = 0;
        currentNoteDuration = 0;
        melodyPause = true;
        melodyFinished = false;

        leftButtonEnabled = true;
        rightButtonEnabled = true;

        gameState = titleDisplayScroll;

        // both bottom buttons pressed during titleDisplayInit: play demo for a day
        if ((digitalRead(buttonLeftBottom) == LOW) && (digitalRead(buttonRightBottom) == LOW)) {
            demoInterval = 86400 * 1000;
            demo = true;
        }
        break;

    case titleDisplayScroll:
        elapsedTitleScrollMillis += elapsedMillis;
        if (!titleFinished && elapsedTitleScrollMillis > titleScrollInterval) {
            elapsedTitleScrollMillis = 0;

            if (titleRow1Ptr >= titleRow1) {
                lcd.setCursor(0, 0);
                lcd.print(titleRow1Ptr);
                titleRow1Ptr--;
            }

            if (*titleRow2Ptr != '\0') {
                lcd.setCursor(lcdCols - (titleRow2Ptr - titleRow2)-1, 1);
                // let the LCD library clip the string, so we don't have to modify it
                lcd.print(titleRow2);
                titleRow2Ptr++;
            }

            if (titleRow1Ptr <= titleRow1 && *titleRow2Ptr == '\0') {
                titleFinished = true;
            }
        }

        elapsedNoteMillis += elapsedMillis;
        if (!melodyFinished && elapsedNoteMillis > currentNoteDuration) {
            elapsedNoteMillis = 0;
            if (melodyPause) {
                // pause between notes ended, play next note
                // or return to start if all notes have been played
                if (++currentNoteIdx >= titleMelodyNotes) {
                    currentNoteIdx = 0;
                    melodyFinished = true;
                } else {
                    // to calculate the note duration, take one second
                    // divided by the note type.
                    //e.g. quarter note = 1000 / 4, eighth note = 1000/8, etc.
                    currentNoteDuration = 1000/titleNoteDurations[currentNoteIdx];
                    tone(speakerPin, titleMelody[currentNoteIdx]);
                    melodyPause = false;
                }
            } else {
                // to distinguish the notes, set a minimum time between them.
                // the note's duration + 30% seems to work well:
                currentNoteDuration = 1000/titleNoteDurations[currentNoteIdx] * 1.30;
                noTone(speakerPin);
                melodyPause = true;
            }
        }

        // finished title, start game
        if (titleFinished && melodyFinished) {
            // wait for button or timeout
            if ((leftButtonPressed || rightButtonPressed || (digitalRead(buttonLeftBottom) == LOW) || (digitalRead(buttonRightBottom) == LOW)) ||
                (elapsedTitleScrollMillis > titleTimeout && elapsedNoteMillis > titleTimeout)) {

                // timeout -> start demo
                demo = (elapsedTitleScrollMillis > titleTimeout || elapsedNoteMillis > titleTimeout);

                leftButtonPressed = false;
                rightButtonPressed = false;
                digitalWrite(ledLeft, LOW);
                digitalWrite(ledRight, LOW);
                wobbleBacklight = true;
                gameState = playInit;
                return;
            }
        }

        break;

    case playInit:
        lcd.clear();
        wipeDisplayMap();

        noTone(speakerPin);

        // load sprites into CGRAM
        uploadGameChars();

        // both bottom buttons pressed during playInit: display all game sprites
        if ((digitalRead(buttonLeftBottom) == LOW) && (digitalRead(buttonRightBottom) == LOW)) {
            for (int k=0; k < 8; k++) {
                for (int i=0; i < lcdRows; i++) {
                    lcd.setCursor(0, i);
                    for (int j=0; j < lcdCols; j += 2) {
                        lcd.write(k);
                        lcd.write(lcdCharSpace);
                    }
                }
                delay(1000);
            }
            lcd.clear();
        }

        // player starts at center of the screen
        playerPos = lcdRows;
        playerState = left;
        gameArena[playerPos][1] = player;

        playerLifes = (lcdRows*2);

        gameState = playRun;
        leftButtonEnabled = true;
        rightButtonEnabled = true;

        demoHaveTarget = false;
        demoMove = false;

        // increase difficulty for demo
        if (demo) {
            invaderIntervalMin = demoInvaderIntervalMin;
            invaderIntervalMax = demoInvaderIntervalMax;
        } else {
            invaderIntervalMin = defaultInvaderIntervalMin;
            invaderIntervalMax = defaultInvaderIntervalMax;
        }
        break;

    case playRun:
        // pause game
        if (rightButtonPressed) {
            tone(speakerPin, 400, 50);
            gameState = paused;
            rightButtonPressed = false;
            return;
        } 

        // refresh half-columns where two characters are to be displayed in one LCD cell
        elapsedFlickerMillis += elapsedMillis;
        if (elapsedFlickerMillis > flickerInterval) {
            for (int i=0; i < lcdRows; i++) {
                for (int j=0; j < lcdCols; j++) {
                    if ((gameArena[(i*2)][j] != none) && (gameArena[(i*2)+1][j] != none)) {
                        lcd.setCursor(j, i);
                        if (flickerState) {
                            lcd.write(lcdCharsRight[gameArena[(i*2)+1][j]]);
                        } else {
                            lcd.write(lcdCharsLeft[gameArena[(i*2)][j]]);
                        }
                    }
                }
            }
            flickerState = !flickerState;
            elapsedFlickerMillis = 0;
        }

        if (demo) {
            // play demo for a while, then return to title screen
            elapsedDemoMillis += elapsedMillis;
            if (elapsedDemoMillis > demoInterval) {
                elapsedDemoMillis = 0;
                demo = false;
                gameState = titleDisplayInit;
                leftButtonPressed = false;
                rightButtonPressed = false;
                leftButtonEnabled = false;
                rightButtonEnabled = false;
                digitalWrite(ledLeft, LOW);
                digitalWrite(ledRight, LOW);
                return;
            }

            // select the first lowest invader in a column that doesn't already have a shot fired at it
            if (!demoHaveTarget) {
                for (int i=0; i < (lcdRows*2); i++) {
                    // limit scan range
                    for (int j=0; j < min(lcdRows*2 + 8, lcdCols); j++) {
                        if (gameArena[i][j] == shot) {
                            break;
                        }
                        if (gameArena[i][j] == invader && !demoHaveTarget) {
                            demoTargetPos = i;
                            demoHaveTarget = true;
                            break;
                        }
                    }
                }
            }

            // nothing to shoot at. sit and wait
            if (!demoHaveTarget) {
                demoMove = false;
            } else {
                if (playerPos == demoTargetPos) {
                    // fire if under the target
                    demoHaveTarget = false;
                    demoMove = false;
                    leftButtonPressed = true;
                    digitalWrite(ledLeft, HIGH);
                } else {
                    // otherwise move one step closer
                    demoMovePos = (playerPos < demoTargetPos) ? (right) : (left);
                    demoMove = true;
                    digitalWrite(ledRight, HIGH);
                }
            }
        }


        // move player left
        if (digitalRead(buttonLeftBottom) == LOW || (demoMove && demoMovePos == left)) {
            // ignore buttons for playerControlIntervalMin ms after last activation
            // TODO: button should be pressed for xx ms
            // TODO: handle overflowing millis
            digitalWrite(ledRight, LOW);
            if (currentMillis - lastPlayerControlMillis > playerControlIntervalMin) {
                if (playerState == right)  {
                    gameArena[playerPos][1] = none;
                    // update display
                    lcd.setCursor(1, playerPos/2);
                    lcd.write(lcdCharSpace);
                    playerPos--;
                    playerState = left;
                    gameArena[playerPos][1] = player;
                    lcd.setCursor(1, playerPos/2);
                    lcd.write(lcdCharPlayerLeftID);
                    tone(speakerPin, 1000, 10);
                } else {
                    if (playerPos > 0) {
                        gameArena[playerPos][1] = none;
                        lcd.setCursor(1, playerPos/2);
                        lcd.write(lcdCharSpace);
                        playerPos--;
                        playerState = right;
                        gameArena[playerPos][1] = player;
                        lcd.setCursor(1, playerPos/2);
                        lcd.write(lcdCharPlayerRightID);
                        tone(speakerPin, 1000, 10);
                    }
                }
                lastPlayerControlMillis = currentMillis;
            }
        }

        // move player right
        if (digitalRead(buttonRightBottom) == LOW || (demoMove && demoMovePos == right)) {
            // ignore buttons for playerControlIntervalMin ms after last activation
            // TODO: button should be pressed for xx ms
            // TODO: handle overflowing millis
            digitalWrite(ledRight, LOW);
            if (currentMillis - lastPlayerControlMillis > playerControlIntervalMin) {
                if (playerState == left)  {
                    gameArena[playerPos][1] = none;
                    lcd.setCursor(1, playerPos/2);
                    lcd.write(lcdCharSpace);
                    playerPos++;
                    playerState = right;
                    gameArena[playerPos][1] = player;
                    lcd.setCursor(1, playerPos/2);
                    lcd.write(lcdCharPlayerRightID);
                    tone(speakerPin, 1000, 10);
                } else {
                    if (playerPos < (lcdRows*2)-1) {
                        gameArena[playerPos][1] = none;
                        lcd.setCursor(1, playerPos/2);
                        lcd.write(lcdCharSpace);
                        playerPos++;
                        playerState = left;
                        gameArena[playerPos][1] = player;
                        lcd.setCursor(1, playerPos/2);
                        lcd.write(lcdCharPlayerLeftID);
                        tone(speakerPin, 1000, 10);
                    }
                }
                lastPlayerControlMillis = currentMillis;
            }
        }

        // move everything else
        elapsedPlayMillis += elapsedMillis;
        if (elapsedPlayMillis > playInterval) {
            Serial.print("\ncurrentMillis=");
            Serial.print(currentMillis);
            Serial.print("\t elapsedPlayMillis=");
            Serial.print(elapsedPlayMillis);
            Serial.print("\t elapsedInvaderMillis=");
            Serial.print(elapsedInvaderMillis);
            Serial.print("\t lastPlayerControlMillis=");
            Serial.print(lastPlayerControlMillis);
            Serial.print("\t playerPos=");
            Serial.print(playerPos);
            Serial.print("\t playerState=");
            Serial.println((playerState == left)?("left"):("right"));

            // scan arena backwards and move shots forward (up)
            Serial.println("5432109876543210");
            for (int i=(lcdRows*2)-1; i >= 0; i--) {
                for (int j=lcdCols-1; j >= 1; j--) {
                    switch (currentChar = gameArena[i][j]) {
                    case shot:
                        Serial.print("<");
                        // collision test
                        if (j < lcdCols-1) {
                            if (gameArena[i][j+1] == invader) {
                                gameArena[i][j+1] = invaderHit;
                                if (!demo) {
                                    tone(speakerPin, 300, 100);
                                }
                            } else {
                                gameArena[i][j+1] = shot;
                            }
                        }
                        gameArena[i][j] = none;
                        break;
                    case playerHit:
                        Serial.print("n");
                        gameArena[i][j] = player;
                        break;
                    case invaderHit:
                        Serial.print("X");
                        gameArena[i][j] = none;
                        break;
                    default:
                        Serial.print("_");
                        break;
                    }
                }
                Serial.println("");
            }

            // fire shot
            if (leftButtonPressed) {
                if (!demo) {
                    tone(speakerPin, 500, 50);
                }
                if (gameArena[playerPos][2] == invader) {
                    gameArena[playerPos][2] = invaderHit;
                    if (!demo) {
                        tone(speakerPin, 300, 100);
                    }
                } else {
                    gameArena[playerPos][2] = shot;
                }
                digitalWrite(ledLeft, LOW);
                leftButtonPressed = false;
            } 

            // scan arena forward and move invaders backwards (down)
            Serial.println("0123456789012345");
            for (int i=0; i < (lcdRows*2); i++) {
                for (int j=1; j < lcdCols; j++) {
                    switch (currentChar = gameArena[i][j]) {
                    case invader:
                        Serial.print("i");
                        gameArena[i][j] = none;
                        // collision test
                        if (j > 1) {
                            if (gameArena[i][j-1] == shot) {
                                gameArena[i][j-1] = invaderHit;
                                if (!demo) {
                                    tone(speakerPin, 300, 100);
                                }
                            } else if (gameArena[i][j-1] == player) {
                                // lost one guy
                                gameArena[i][j-1] = playerHit;
                                tone(speakerPin, 50, 200);

                                if (--playerLifes == 0) {
                                    updateDisplay();
                                    delay(timeBase*4);
                                    gameState = gameOverDisplayInit;
                                    return;
                                }

                                wobbleBacklight = true;
                            } else {
                                gameArena[i][j-1] = invader;
                            }
                        }
                        break;
                    default:
                        Serial.print("_");
                        break;
                    }
                }
                Serial.println("");
            }

            // send reinforcements
            elapsedInvaderMillis += elapsedPlayMillis;
            if (elapsedInvaderMillis > random(invaderIntervalMin, invaderIntervalMax)) {
                elapsedInvaderMillis = 0;
                for (int i=0; i <= random(0, invaderSpawnMax); i++) {
                    gameArena[random(0, lcdRows*2)][lcdCols-1] = invader;
                }
            }

            // write the updated map to the LCD
            updateDisplay();
            elapsedPlayMillis = 0;
            // randomSeed(analogRead(randomPin));
        }
        break;

    case gameOverDisplayInit:
        // TODO: load title chars into CGRAM

        titleRow1Ptr = gameOverRow1;
        titleRow2Ptr = gameOverRow2;

        currentNoteIdx = 0;
        currentNoteDuration = 0;
        melodyPause = true;
        melodyFinished = false;
        titleFinished = false;
        elapsedTitleScrollMillis = 0;
        elapsedNoteMillis = 0;

        gameState = gameOverDisplayScroll;
        break;

    case gameOverDisplayScroll:
        elapsedTitleScrollMillis += elapsedMillis;
        if (!titleFinished && elapsedTitleScrollMillis > titleScrollInterval) {
            elapsedTitleScrollMillis = 0;

            if (*titleRow1Ptr != '\0') {
                lcd.setCursor(((lcdCols - strlen(gameOverRow1))/2) + (titleRow1Ptr - gameOverRow1), 0);
                lcd.write(*titleRow1Ptr);
                titleRow1Ptr++;
            }

            if (*titleRow2Ptr != '\0') {
                lcd.setCursor(((lcdCols - strlen(gameOverRow2))/2) + (titleRow2Ptr - gameOverRow2), 1);
                lcd.write(*titleRow2Ptr);
                titleRow2Ptr++;
            }

            if (*titleRow1Ptr == '\0' && *titleRow2Ptr == '\0') {
                titleFinished = true;
            }
        }

        elapsedNoteMillis += elapsedMillis;
        if (!melodyFinished && elapsedNoteMillis > currentNoteDuration) {
            elapsedNoteMillis = 0;
            if (melodyPause) {
                if (++currentNoteIdx >= titleMelodyNotes) {
                    currentNoteIdx = 0;
                    melodyFinished = true;
                } else {
                    melodyPause = false;
                    // to calculate the note duration, take one second
                    // divided by the note type.
                    //e.g. quarter note = 1000 / 4, eighth note = 1000/8, etc.
                    currentNoteDuration = 1000/gameOverNoteDurations[currentNoteIdx];
                    tone(speakerPin, gameOverMelody[currentNoteIdx]);
                }
            } else {
                melodyPause = true;
                noTone(speakerPin);
                // to distinguish the notes, set a minimum time between them.
                // the note's duration + 30% seems to work well:
                currentNoteDuration = 1000/gameOverNoteDurations[currentNoteIdx] * 1.30;
            }
        }

        // finished display, return to title
        if (titleFinished && melodyFinished) {
            delay(2000);
            gameState = titleDisplayInit;
            return;
        }

        break;

    case paused:
        if (rightButtonPressed) {
            gameState = playRun;
            tone(speakerPin, 100, 100);
            rightButtonPressed = false;
            digitalWrite(ledRight, LOW);
            return;
        }
        break;

    default:
        break;
    }
}
