GetMouseCoordsForTooltip()
{
    global toolTip2Mesg
    MouseGetPos, MouseTooltipX, MouseTooltipY
    If (InStr(A_ScriptName, "autofillAsSoonAsWindowComesToFocus."))
    {
        MouseTooltipY -= 500
    }
    Else If (InStr(A_ScriptName, "keyboardBlockerOnFocus."))
    {
        MouseTooltipX -= 270
    }
    Else If (InStr(A_ScriptName, "F8ShiftF8AltF8."))
    {
        MouseTooltipX += 100
    }
    return [MouseTooltipX, MouseTooltipY]
}

AddMessageAndDisplayTooltip(message, timeoutToRemoveTooltip := false)
{
    global paramTimeoutToRemoveTooltip, toolTip2Mesg
    If (message != "")
    {
        toolTip2Mesg .= message . "`r`n"
    }
    coordsOfTooltip := GetMouseCoordsForTooltip()
    ToolTip, % toolTip2Mesg, coordsOfTooltip[1], coordsOfTooltip[2]

    If (timeoutToRemoveTooltip != false)
    {
        SetTimer, RemoveToolTip, % timeoutToRemoveTooltip
        paramTimeoutToRemoveTooltip := timeoutToRemoveTooltip
        SetTimer, CheckForGestureToClearToolTip, -1
    }
}
Return

CheckForGestureToClearToolTip:
    timeoutToRemoveTooltip := paramTimeoutToRemoveTooltip
    paramTimeoutToRemoveTooltip := 
    startTime := A_TickCount
    duration := Abs(timeoutToRemoveTooltip)
    GetMouseGesture(True)
    While (A_TickCount - startTime < duration) {
        MouseGetPos, currentX, currentY
        If (currentX != mouseX || currentY != mouseY) 
        {
            currGesture := GetMouseGesture()
        }
        Else
        {
            currGesture := GetMouseGesture(True)
        }

        currGesture := RemoveConsecutiveDuplicates(currGesture) 
        ; AddMessageAndDisplayTooltip(currGesture)
        Sleep, 50

        mouseX := currentX
        mouseY := currentY

        If (InStr(currGesture, "LRL") || InStr(currGesture, "RLR"))
        {
            coordsOfTooltip := GetMouseCoordsForTooltip()
            ToolTip, Tooltip Cleared, coordsOfTooltip[1], coordsOfTooltip[2]
            SetTimer, RemoveToolTip, -500
            Break
        }
    }
    If (InStr(A_ScriptName, "autofillAsSoonAsWindowComesToFocus."))
    {
        Sleep, 500
        ExitApp
    }
return

RemoveToolTip:
    SetTimer, RemoveToolTip, Off
    ToolTip
return
