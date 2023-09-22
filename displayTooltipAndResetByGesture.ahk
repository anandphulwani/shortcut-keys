AddMessageAndDisplayTooltip(message, timeoutToRemoveTooltip := false)
{
    global paramTimeoutToRemoveTooltip, toolTip2Mesg
    If (message != "")
    {
        toolTip2Mesg .= message . "`r`n"
    }
    ToolTip, % toolTip2Mesg

    If (timeoutToRemoveTooltip != false)
    {
        SetTimer, RemoveToolTip, % timeoutToRemoveTooltip
        paramTimeoutToRemoveTooltip := timeoutToRemoveTooltip
        SetTimer, CheckForGestureToClearToolTip, -1
    }
}

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
            ToolTip, Tooltip Cleared
            If (InStr(A_ScriptName, "fillAutomatically"))
            {
                Sleep, 500
                ExitApp
            }
            Else
            {
                SetTimer, RemoveToolTip, -500
            }
            Break
        }
    }
return

RemoveToolTip:
    SetTimer, RemoveToolTip, Off
    ToolTip
return
