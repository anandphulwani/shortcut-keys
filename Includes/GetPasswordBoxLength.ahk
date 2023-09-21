#Include %A_ScriptDir%\Includes\Gdip_CustomFunctions.ahk

GetPasswordBoxLength(passwordControl, windowId, controlLeftPaddingPixel, perCharacterPixel , perCharacterLeftPaddingPixel, perCharacterRightPaddingPixel)
{
    backgroundColorOfControl := GetBackgroundColorOfControl(passwordControl, windowId)
    ControlGetPos, ControlX, ControlY, ControlWidth, ControlHeight, %passwordControl%, ahk_id %windowId%

    CenterX := ControlX + ControlWidth / 2
    CenterY := ControlHeight / 2

    bitmapFromControl := GdipCF_createBitmapBasedOnMode("component", windowId, passwordControl)
    lengthOfPassword := 0
    Loop
    {
        XPos := controlLeftPaddingPixel 
        + (( perCharacterLeftPaddingPixel + perCharacterPixel + perCharacterRightPaddingPixel ) * ( lengthOfPassword + 1 )) 
        - ((perCharacterPixel / 2) + perCharacterRightPaddingPixel)

        currentIterationPixelColor := GdipCF_ARGBtoRGB(Gdip_GetPixel(bitmapFromControl, XPos, CenterY)) . ""

        If (currentIterationPixelColor = backgroundColorOfControl)
        {
            Break
        }
        lengthOfPassword++
    }
    return lengthOfPassword
}

GetBackgroundColorOfControl(control, windowId)
{
    DominantColors := GdipCF_getDominantColor(1, "component", windowId, control)
    return DominantColors.Pop().color
}
