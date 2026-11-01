import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Graphics; 
import Toybox.Application.Properties; 
import Toybox.FitContributor;
import Toybox.Attention;
import Toybox.System;

class TestView extends WatchUi.DataField {

    enum {
        STATE_START,
        STATE_H2O,
        STATE_CARB,
        STATE_NO_DATA,
        STATE_SLOW,
        STATE_SPEED,
        STATE_OK
    }

    private var targetPower as Number = 200;     
    private var hrZone4 as Number = 165;         
    private var fuelIntervalSec as Number = 1200; 
    private var targetBufferWatts as Number = 20; 
    private const POWER_SMOOTHING_WINDOW = 15; // ~15s window - smooths normal power spikes without masking real pacing drift

    private var isAlertActive as Boolean = false;
    private var cachedHrStatusAtAlertStart as Boolean = false; 
    private var uiState as Number = STATE_START;
    private var nextAlertSec as Number = 0;

    private var uiBackgroundColor as Number = Graphics.COLOR_WHITE;
    private var uiTextColor as Number = Graphics.COLOR_BLACK;
    private var livePowerValue as Number = 0; 

    private var powerHistory as Array<Number> = [] as Array<Number>;
    private var lastKnownGoodHeartRate as Number = 0;
    private var missedPowerSamples as Number = 0;

    private var wasSlowLastSecond as Boolean = false;
    private var wasSpeedLastSecond as Boolean = false;

    private var nutritionFitField as FitContributor.Field?;
    private var fuelAlertFitField as FitContributor.Field?;

    function initialize() {
        DataField.initialize(); 
        loadUserSettings();
        var firstAlertCapSec = 900; // 15 min — don't delay the very first fueling prompt past this, even on longer intervals
        nextAlertSec = (fuelIntervalSec < firstAlertCapSec) ? fuelIntervalSec : firstAlertCapSec;

        nutritionFitField = createField(
            "Pacing State",
            0, 
            FitContributor.DATA_TYPE_UINT8, 
            { :mesgType => FitContributor.MESG_TYPE_RECORD }
        );

        fuelAlertFitField = createField(
            "Fuel Alert",
            1,
            FitContributor.DATA_TYPE_UINT8,
            { :mesgType => FitContributor.MESG_TYPE_RECORD }
        );
    }

    function loadUserSettings() as Void {
        var rawFtp = Properties.getValue("userFtp");
        var rawRace = Properties.getValue("raceType");
        var rawHr = Properties.getValue("userHrThreshold");
        var rawFuelTimer = Properties.getValue("fuelTimer"); 
        var rawBuffer = Properties.getValue("pacingBuffer"); 

        if (rawHr != null) {
            hrZone4 = rawHr as Number;
        }

        if (rawFtp != null && rawRace != null) {
            var ftp = rawFtp as Number;
            var raceSelection = rawRace as Number;

            if (raceSelection == 0) {       targetPower = (ftp * 0.95).toNumber(); } 
            else if (raceSelection == 1) {  targetPower = (ftp * 0.87).toNumber(); } 
            else if (raceSelection == 2) {  targetPower = (ftp * 0.80).toNumber(); } 
            else if (raceSelection == 3) {  targetPower = (ftp * 0.72).toNumber(); }
        }

        if (rawFuelTimer != null) {
            fuelIntervalSec = rawFuelTimer as Number;
        }

        if (rawBuffer != null) {
            targetBufferWatts = rawBuffer as Number;
        }
    }

    private function triggerAlertHardwareCues() as Void {
        try {
            if (Toybox has :Attention && Attention has :playTone) {
                Attention.playTone(Attention.TONE_LOUD_BEEP);
            }

            if (Toybox has :Attention && Attention has :vibrate) {
                var vibePattern = [
                    new Attention.VibeProfile(80, 1000),  
                    new Attention.VibeProfile(0, 200),    
                    new Attention.VibeProfile(80, 1000)   
                ] as Array<Attention.VibeProfile>;
                
                Attention.vibrate(vibePattern);
            }
        } catch (e) {
            // A failed tone/vibe must never take down the data field
        }
    }
    function compute(info as Activity.Info) as Void {
        var elapsedMs = info.elapsedTime;
        if (elapsedMs == null || elapsedMs == 0) {
            uiState = STATE_START;
            uiBackgroundColor = Graphics.COLOR_WHITE;
            uiTextColor = Graphics.COLOR_BLACK;
            
            if (nutritionFitField != null) { nutritionFitField.setData(STATE_START); }
            if (fuelAlertFitField != null) { fuelAlertFitField.setData(0); }
            return;
        }

        var currentPower = info.currentPower;
        var currentHr = info.currentHeartRate;
        var totalSec = elapsedMs / 1000;

        if (currentPower != null) {
            missedPowerSamples = 0;
            powerHistory.add(currentPower as Number);
            if (powerHistory.size() > POWER_SMOOTHING_WINDOW) {
                powerHistory.remove(0);
            }
            var sumPower = 0;
            for (var i = 0; i < powerHistory.size(); i++) {
                sumPower += powerHistory[i];
            }
            livePowerValue = (sumPower / powerHistory.size()).toNumber();
        } else {
            missedPowerSamples++;
            if (missedPowerSamples > 2) {
                powerHistory = [] as Array<Number>; 
                livePowerValue = 0;
            }
        }

        if (currentHr != null) {
            lastKnownGoodHeartRate = currentHr;
        }

        if (powerHistory.size() == 0) {
            uiState = STATE_NO_DATA;
            uiBackgroundColor = Graphics.COLOR_LT_GRAY;
            uiTextColor = Graphics.COLOR_BLACK;
        } else {
            uiTextColor = Graphics.COLOR_WHITE;

            var highCutoff = targetPower + targetBufferWatts;
            var lowCutoff = targetPower - targetBufferWatts;
            
            var upperRelease = highCutoff - 3;
            var lowerRelease = lowCutoff + 3;

            if (livePowerValue > (wasSlowLastSecond ? upperRelease : highCutoff)) {
                uiState = STATE_SLOW;
                uiBackgroundColor = Graphics.COLOR_RED; 
                wasSlowLastSecond = true;
                wasSpeedLastSecond = false;
            } else if (livePowerValue < (wasSpeedLastSecond ? lowerRelease : lowCutoff)) {
                uiState = STATE_SPEED;
                uiBackgroundColor = ColorScheme.getSpeedColor();
                wasSlowLastSecond = false;
                wasSpeedLastSecond = true;
            } else {
                uiState = STATE_OK;
                uiBackgroundColor = Graphics.COLOR_GREEN; 
                wasSlowLastSecond = false;
                wasSpeedLastSecond = false;
            }
        }

        var pacingStateForFit = uiState; // snapshot pacing state BEFORE any fuel-alert display override below

        if (!isAlertActive && totalSec >= nextAlertSec) {
            isAlertActive = true;
            nextAlertSec = totalSec + fuelIntervalSec;
            var evaluationHr = (currentHr != null) ? currentHr : lastKnownGoodHeartRate;
            cachedHrStatusAtAlertStart = (evaluationHr > 0 && evaluationHr > hrZone4);

            triggerAlertHardwareCues();
        } else if (isAlertActive && totalSec >= (nextAlertSec - fuelIntervalSec + 15)) {
            isAlertActive = false;
        }

        var fuelIndicatorForFit = 0; // 0 = no alert, 1 = carb reminder, 2 = H2O-only reminder

        if (isAlertActive) {
            uiBackgroundColor = Graphics.COLOR_WHITE;
            uiTextColor = Graphics.COLOR_BLACK;
            uiState = cachedHrStatusAtAlertStart ? STATE_H2O : STATE_CARB;
            fuelIndicatorForFit = cachedHrStatusAtAlertStart ? 2 : 1;
        }

        if (nutritionFitField != null) {
            nutritionFitField.setData(pacingStateForFit.toNumber());
        }
        if (fuelAlertFitField != null) {
            fuelAlertFitField.setData(fuelIndicatorForFit.toNumber());
        }
    }

    private function drawArrow(dc as Graphics.Dc, centerX as Number, centerY as Number, pointUp as Boolean) as Void {
        var size = 10; 
        var points;
        
        if (pointUp) {
            points = [
                [centerX, centerY - size],          
                [centerX - size, centerY + size],  
                [centerX + size, centerY + size]   
            ];
        } else {
            points = [
                [centerX - size, centerY - size],  
                [centerX + size, centerY - size],  
                [centerX, centerY + size]          
            ];
        }
        
        dc.fillPolygon(points);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        var deviceSettings = System.getDeviceSettings();
        var screenW = deviceSettings.screenWidth;
        var screenH = deviceSettings.screenHeight;
        var isRoundScreen = (deviceSettings.screenShape != System.SCREEN_SHAPE_RECTANGLE);

        // Establish the rigid, unchanging center point and physical radius of the watch glass circumference
        var centerX = screenW / 2.0;
        var centerY = screenH / 2.0;
        var radius  = screenW / 2.0;

        // 1. SETUP BACKGROUND & COLORS (UNTOUCHED)
        var requiresBurnInProtection = (deviceSettings has :requiresBurnInProtection) && deviceSettings.requiresBurnInProtection;
        var currentBgColor = uiBackgroundColor;
        var currentTextColor = uiTextColor;

        if (requiresBurnInProtection) {
            currentBgColor = Graphics.COLOR_BLACK;
            currentTextColor = Graphics.COLOR_WHITE;
        }

        dc.setColor(currentBgColor, currentBgColor);
        dc.fillRectangle(0, 0, width, height);
        dc.setColor(currentTextColor, Graphics.COLOR_TRANSPARENT);

        // 2. DEFINE SYSTEM STATES & TEXT PAYLOADS
        var longText = "";
        var shortText = "";

        if (uiState == STATE_START) {
            longText = "PRESS START";        shortText = "START";
        } else if (uiState == STATE_H2O) {
            longText = "ALERT: H2O ONLY!";     shortText = "H2O!";
        } else if (uiState == STATE_CARB) {
            longText = "FUEL: TAKE CARBS";     shortText = "FUEL";
        } else if (uiState == STATE_NO_DATA) {
            longText = "--W (NO DATA)";       shortText = "--W";
        } else if (uiState == STATE_SLOW) {
            longText = livePowerValue + "W (SLOW DOWN)"; shortText = livePowerValue + "W";
        } else if (uiState == STATE_SPEED) {
            longText = livePowerValue + "W (SPEED UP)";  shortText = livePowerValue + "W";
        } else if (uiState == STATE_OK) {
            longText = livePowerValue + "W (PACE OK)";   shortText = livePowerValue + "W";
        }

        // 3. IDENTIFY FIELD PLACEMENT PROFILE
        var fieldGlobalX = 0;
        var fieldGlobalY = 0;
        var obscurity = getObscurityFlags();

        if (obscurity & WatchUi.DataField.OBSCURE_TOP) {
            fieldGlobalY = 0;
        } else if (obscurity & WatchUi.DataField.OBSCURE_BOTTOM) {
            fieldGlobalY = screenH - height;
        } else {
            fieldGlobalY = (screenH - height) / 2;
        }

        if (obscurity & WatchUi.DataField.OBSCURE_LEFT) {
            fieldGlobalX = 0;
        } else if (obscurity & WatchUi.DataField.OBSCURE_RIGHT) {
            fieldGlobalX = screenW - width;
        } else {
            fieldGlobalX = (screenW - width) / 2;
        }

        // Detect if the field is running inside a side-by-side split grid (like 4-field columns)
        var isSplitPane = (width <= (screenW * 0.55));

        // 4. THE FOUR-CORNER CIRCUMFERENCE CRASH GATE, FOR SOME SANITY
        var stringToDraw = longText;
        var textFont = Graphics.FONT_MEDIUM; // ALWAYS attempt maximum visualization size first
        var isSmallLayout = false;

        var fontHeight = dc.getFontHeight(textFont);
        var textWidth = dc.getTextWidthInPixels(stringToDraw, textFont);

        var passesCheck = false;

        while (!passesCheck) {
            // Find where the 4 corners of text bounding box align over the physical glass grid
            var textLeftX  = fieldGlobalX + (width / 2.0) - (textWidth / 2.0);
            var textRightX = fieldGlobalX + (width / 2.0) + (textWidth / 2.0);
            var textTopY   = fieldGlobalY + (height / 2.0) - (fontHeight / 2.0);
            var textBotY   = fieldGlobalY + (height / 2.0) + (fontHeight / 2.0);

            // Establish an 8-pixel buffer zone to shield text letters from overlapping the bezel boundary
            var buffer = 8;
            
            // Measure the absolute physical distance from the screen center to each of the 4 outer text corners
            var distTL = Math.sqrt(Math.pow((textLeftX - buffer) - centerX, 2) + Math.pow((textTopY - buffer) - centerY, 2));
            var distTR = Math.sqrt(Math.pow((textRightX + buffer) - centerX, 2) + Math.pow((textTopY - buffer) - centerY, 2));
            var distBL = Math.sqrt(Math.pow((textLeftX - buffer) - centerX, 2) + Math.pow((textBotY + buffer) - centerY, 2));
            var distBR = Math.sqrt(Math.pow((textRightX + buffer) - centerX, 2) + Math.pow((textBotY + buffer) - centerY, 2));

            // Round glass: check against the circular bezel. Rectangular screens (Edge): just check
            // the text fits inside this field's own box - there's no curved bezel to fight.
            var cornersAreInside;
            if (isRoundScreen) {
                cornersAreInside = (distTL < radius && distTR < radius && distBL < radius && distBR < radius);
            } else {
                cornersAreInside = ((textWidth + (buffer * 2)) <= width) && ((fontHeight + (buffer * 2)) <= height);
            }

            if (cornersAreInside) {
                // If the corners fit, apply a grid limit filter for side-by-side quadrant division lines
                if (isSplitPane && textWidth > (width * 0.82)) {
                    cornersAreInside = false;
                }
            }

            if (cornersAreInside) {
                passesCheck = true; // The text bounds reside cleanly within the visible circumference line
            } else {
                // If a corner breaks the circumference boundary line, downscale sizes sequentially
                if (textFont == Graphics.FONT_MEDIUM) {
                    textFont = Graphics.FONT_SMALL;
                } else if (textFont == Graphics.FONT_SMALL) {
                    textFont = Graphics.FONT_XTINY;
                } else if (textFont == Graphics.FONT_XTINY && stringToDraw.equals(longText)) {
                    // Non-negotiable threshold: Long text cannot avoid crossing the circumference line.
                    // Immediately transition to my short string pairing configuration.
                    stringToDraw = shortText;
                    isSmallLayout = true; // Signal layout arrow inclusion engine activation
                    textFont = Graphics.FONT_MEDIUM; // Reset size optimization gate back to large for short payload
                } else if (textFont == Graphics.FONT_MEDIUM && stringToDraw.equals(shortText)) {
                    textFont = Graphics.FONT_SMALL;
                } else if (textFont == Graphics.FONT_SMALL && stringToDraw.equals(shortText)) {
                    textFont = Graphics.FONT_XTINY;
                    passesCheck = true; 
                } else {
                    passesCheck = true; 
                }

                // Update footprint width parameters for the next evaluation pass
                fontHeight = dc.getFontHeight(textFont);
                textWidth = dc.getTextWidthInPixels(stringToDraw, textFont);
            }
        }

        // Structural constraint guard to block thick fonts from clipping horizontal divider rules (like thin 7/8 layouts)
        if (height < 60) {
            textFont = Graphics.FONT_XTINY;
            if (height < 45) {
                stringToDraw = shortText;
                isSmallLayout = true;
                textWidth = dc.getTextWidthInPixels(stringToDraw, textFont);
            }
        }

        // 5. DRAW HEADER TITLE SECTION (UNTOUCHED)
        var isSmallLayoutFlag = (height < 100 || width < 180);
        if (!isSmallLayoutFlag && !requiresBurnInProtection) {
            var headerY = (height * 0.12).toNumber(); 
            dc.drawText(width / 2, headerY, Graphics.FONT_XTINY, "RACE PACE & FUEL", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // 6. COMPACT BOUNDS DRAW ENGINE (TEXT + ARROW)
        var hasArrow = isSmallLayout && (uiState == STATE_SLOW || uiState == STATE_SPEED);

        if (hasArrow) {
            var arrowWidth = 10; 
            var arrowSpacing = 6; 
            
            // Calculate a perfect unified center point for the text + arrow block combined
            var totalBlockWidth = textWidth + arrowSpacing + arrowWidth;
            var startX = (width - totalBlockWidth) / 2;
            
            // FIXED REDEFINITION BUG: Changed variable name to avoid duplicate definition crash
            var arrowCenterY = height / 2;

            // Draw text cleanly left-aligned from the safe layout group coordinate
            dc.drawText(
                startX, 
                arrowCenterY, 
                textFont, 
                stringToDraw, 
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
            );

            // Compute arrow position cleanly following the text block boundary edge footprint
            var arrowX = startX + textWidth + arrowSpacing + (arrowWidth / 2);

            if (uiState == STATE_SLOW) {
                drawArrow(dc, arrowX, arrowCenterY, false); 
            } else if (uiState == STATE_SPEED) {
                drawArrow(dc, arrowX, arrowCenterY, true);  
            }

        } else {
            // Clean centered draw path for text-only states
            dc.drawText(
                width / 2,                          
                height / 2,                         
                textFont, 
                stringToDraw,                      
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
    }
}
