#Include %A_ScriptDir%\Includes\Gdip_All.ahk

pToken := GdipCF_initialize()
/*
	for testing/benchmark purposes
*/
GdipCF_createBitmapBasedOnMode(mode, windowId := "", component := "") {
    if (mode = "screen")
        return Gdip_BitmapFromScreen(1) ; main monitor

    if (mode = "debug")
        return Gdip_BitmapFromScreen("300|300|20|20") ; forum thread tests

    if (mode = "torture")
        return Gdip_CreateBitmapFromFile("noise.png") ; random color noise torture test

    if (mode = "window")
        return Gdip_BitmapFromHWND(windowId) ; capture bitmap from window id

    if (mode = "component")
    {
        windowsBitmap := Gdip_BitmapFromHWND(windowId)
        ; Gdip_SaveBitmapToFile(windowsBitmap,"test11.png")
        ControlGetPos, ControlX, ControlY, ControlWidth, ControlHeight, %component%, ahk_id %windowId%
        ; MsgBox, % ControlX . ":" . ControlY . ":" . ControlWidth . ":" . ControlHeight
        return Gdip_CloneBitmapArea(windowsBitmap, ControlX, ControlY, ControlWidth, ControlHeight) ; capture bitmap from window's component
    }

    throw Exception("Invalid mode specified!")
}

/*
	returns the specified amount of most dominant colors
*/
GdipCF_getDominantColor(numDominantColors := 1, mode := "screen", windowId := "", component := "") {
    pBitmap := GdipCF_createBitmapBasedOnMode(mode, windowId, component)
    ; Gdip_SaveBitmapToFile(pBitmap,"test12.png")
    bitmapWidth := Gdip_GetImageWidth(pBitmap)
    bitmapHeight := Gdip_GetImageHeight(pBitmap)

    Gdip_LockBits(pBitmap, 0, 0, bitmapWidth, bitmapHeight, Stride, Scan0, BitmapData)

    ColorOccurences := GdipCF_getLockBitColorOccurences(bitmapWidth, bitmapHeight, Stride, Scan0)
    SortedColors := GdipCF_sortColorArray(ColorOccurences)
    DominantColors := GdipCF_pickDominantColorsFromSortedArray(SortedColors, numDominantColors)

    Gdip_UnlockBits(pBitmap, BitmapData)
    Gdip_DisposeImage(pBitmap)

    return DominantColors
}

/*
	retrieves the hex RGB of every pixel in the selected region sequentially
	computes the number of occurences of each pixel
	returns a data structure of the type:
	{
		"0xC0FFEE" : 385,
		"0x0DEAD0" : 22,
		"0x0BEEF0" : 1
	}
*/
GdipCF_getLockBitColorOccurences(width, height, stride, scan) {
    ColorOccurences := {}

    Loop, % width {
        x := A_Index - 1
        Loop, % height {
            y := A_Index - 1

            pixelColor := GdipCF_ARGBtoRGB(Gdip_GetLockBitPixel(scan, x, y, stride))

            if (ColorOccurences.HasKey(pixelColor . "")) {
                ColorOccurences[pixelColor . ""]++
            }
            else {
                ColorOccurences[pixelColor . ""] := 1
            }
        }
    }
    return ColorOccurences
}

/*
	sorts the passed array ascending in a way such that
	the key reflects the total number of times a given color has occured and
	the value contains an array of color, to allow for the case where
	multiple distinct colors have occured the same number of times
	return a data structure of the following type:
	{
		1 :
		{
			1 : "0x0BEEF0"
		},
		22 :
		{
			1 : "0x0DEAD0",
			2 : "0x1DEAD1"
		},
		385 :
		{
			1 : "0xC0FFEE"
		}
	}
*/
GdipCF_sortColorArray(Colors) {
    SortedColors := {}

    for pixelColor, numOccurences in Colors {
        if (SortedColors.HasKey(numOccurences)) {
            SortedColors[numOccurences].push(pixelColor)
        }
        else {
            SortedColors[numOccurences] := [pixelColor]
        }
    }

    return SortedColors
}

/*
	computes the numDominantColors most dominant colors
	if multiple colors have the same number of occurences,
	they are picked in the order that they appear in the data structure.
	returns example data structure for numDominantColors = 4:
	{
		1 : {"color" : "0xC0FFEE", "occurences" : 385 },
		2 : {"color" : "0x0DEAD0", "occurences" : 22 },
		3 : {"color" : "0x1DEAD1", "occurences" : 22 },
		4 : {"color" : "0x0BEEF0", "occurences" : 1 }
	}
*/
GdipCF_pickDominantColorsFromSortedArray(SortedColors, numDominantColors) {
    DominantColors := {}
    colorRank := 1

    Loop, % numDominantColors {
        if (colorRank > numDominantColors) {
            break
        }

        occurences := SortedColors.MaxIndex()
        lastElement := SortedColors.Pop()

        for index, color in lastElement {
            if (colorRank > numDominantColors) {
                break
            }

            DominantColors[colorRank] := {"occurences" : occurences, "color" : color}
            colorRank++
        }
    }

    return DominantColors
}

; ARBG to RGB conversion function
GdipCF_ARGBtoRGB(ARGB) {
    RGB := Format("0x{:X}", ARGB) ; prepend '0x' infront and convert to hex
    RGB := StrReplace(RGB, "0xFF", "0x") ; remove Alpha channel, leave only RGB
    return RGB
}

GdipCF_ARGBtoHEX(ARGB) {
    HEX := Format("0x{:X}", ARGB) ; prepend '0x' infront and convert to hex
    return HEX
}

GdipCF_initialize() {
    GdipCF_checkForAdminPrivileges()
    pToken := initializeGdip()
    OnExit(Func("GdipCF_cleanUp").Bind(pToken))
    return
}

GdipCF_checkForAdminPrivileges() {
    if !(A_IsAdmin) {
        MsgBox, % "Run with administrative rights."
        . "`r`n" . "The script will now exit."
        ExitApp
    }
}

initializeGdip() {
    if !(pToken := Gdip_Startup()) {
        MsgBox, % "Failed to load GDI+."
        . "`r`n" . "The script will now exit."
        ExitApp
    }
    return pToken
}

GdipCF_cleanUp(pToken) {
    Gdip_Shutdown(pToken)
    ExitApp
}

class DebugModes {
    static currentMode := 0
    Modes := {1 : "SCREEN"
        , 2 : "DEBUG"
        , 3 : "TORTURE"}

        cycle() {
            if (++this.currentMode > this.Modes.Length()) {
                this.currentMode := 1
            }

        return this.Modes[this.currentMode]
    }
}
