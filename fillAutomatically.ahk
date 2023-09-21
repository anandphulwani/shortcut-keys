#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
#SingleInstance Off
; #Warn  ; Enable warnings to assist with detecting common errors.
; SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
SetTitleMatchMode, 1

If (A_Args.Length() != 2)
{
    MsgBox, % "Incorrect length of arguments ( WindowType, WindowId ) sent to the script, Args length is " . A_Args.Length() . "."
    for n, param in A_Args ; For each parameter:
    {
        MsgBox Parameter number %n% is %param%.
    }
    ExitApp
}

#Include %A_ScriptDir%\Includes\IncludeVariables.ahk
#Include %A_ScriptDir%\Includes\GetPasswordBoxLength.ahk
#Include %A_ScriptDir%\credentialsEncDecKey.ahk

WindowType := A_Args[1]
currWindowId := A_Args[2]

If ( WindowType == "Radmin security")
{
    WinWait, % WindowType, , 5
    If ErrorLevel
    {
        MsgBox, % "WinWait timed out" . WindowType
        ExitApp
    }
    ; WinGet, currWindowId, ID
    WinGetTitle, currWindowTitle

    If (!parsedCredentialsJSON["autofill"].HasKey(WindowType))
    {
        MsgBox, % "parsed Credentials JSON doesn't have key with the name: " . WindowType
        ExitApp
    }

    MatchedWindowTypeKey :=
    For parsedCredentialsJSONWindowTypeKey in parsedCredentialsJSON["autofill"][WindowType].GetKeys()
    {
        If RegExMatch(currWindowTitle, "^" . parsedCredentialsJSONWindowTypeKey . "$")
        {
            MatchedWindowTypeKey := parsedCredentialsJSONWindowTypeKey
        }
    }

    If (MatchedWindowTypeKey == "")
    {
        MsgBox, % "parsed Credentials JSON doesn't match a title with the current window title: " . currWindowTitle
        ExitApp
    }

    windowComponents := parsedCredentialsJSON["autofill"][WindowType][MatchedWindowTypeKey]["Components"]

    If (parsedCredentialsJSON["autofill"][WindowType][MatchedWindowTypeKey].HasKey("WinMove"))
    {
        winMove = parsedCredentialsJSON["autofill"][WindowType][MatchedWindowTypeKey]["WinMove"]
        winMoveArr := StrSplit(winMove, ",")
        WinMove, % winMoveArr[1], % winMoveArr[2]
    }

    tooltipMesg := "Window Id: " . currWindowId . "`r`n"
    tooltipMesg .= "Window Title: " . currWindowTitle . "`r`n"
    tooltipMesg .= "Logging In...." . "`r`n"

    ; stringified := JSON.Dump(windowComponents,, 4)
    ; stringified := StrReplace(stringified, "`n", "`r`n") 
    ; tooltipMesg .= stringified . "`r`n"
    ; ToolTip, % tooltipMesg
    ; Sleep 20000
    ; ExitApp

    ComponentsExecuted := {}
    For componentId, componentProperties in windowComponents
    {
        If (componentProperties.HasKey("IfExecuted") && !ComponentsExecuted.HasKey(componentProperties.IfExecuted))
        {
            continue
        }

        WaitControlLoad(componentId, currWindowTitle)
        If (componentProperties.Type == "Textbox")
        {
            ControlGetText, GetTxtFromBox, % componentId
            If (GetTxtFromBox == componentProperties.Value)
            {
                tooltipMesg .= "Continuing, as already data set in the " . componentProperties.Label . " (" . componentProperties.Type . ") primary check block, " . componentId . " : " . componentProperties.Value . "`r`n"
                ToolTip, % tooltipMesg
                continue
            }
        }
        Else If (componentProperties.Type == "Checkbox")
        {
            ControlGet, isChecked, Checked, , % componentId
            If (isChecked == componentProperties.Value)
            {
                tooltipMesg .= "Continuing, as already checkbox state set in the " . componentProperties.Label . " (" . componentProperties.Type . ") primary check block, " . componentId . "`r`n"
                ToolTip, % tooltipMesg
                continue
            }
        }

        If (componentProperties.Type == "Textbox" || componentProperties.Type == "Passwordbox")
        {
            tooltipMesg .= "Got in the " . componentProperties.Label . " (" . componentProperties.Type . ") secondary block, " . componentId . " : " . componentProperties.Value . "`r`n"
            ToolTip, % tooltipMesg
            ControlSetText, % componentId, % componentProperties.Value
            Sleep, 10
        } 
        Else If (componentProperties.Type == "Checkbox" || componentProperties.Type == "Button")
        {
            tooltipMesg .= "Got in the " . componentProperties.Label . " (" . componentProperties.Type . ") secondary block, " . componentId . "`r`n"
            ToolTip, % tooltipMesg
            ControlClick, % componentId
            Sleep, 10
        }

        If (componentProperties.Type == "Textbox")
        {
            ControlGetText, GetTxtFromBox, % componentId
            While (componentProperties.Value != GetTxtFromBox && A_INDEX < 20) {
                ControlSetText, % componentId, % componentProperties.Value
                tooltipMesg .= "Got in the " . componentProperties.Label . " (" . componentProperties.Type . ") loop, " . componentId . " : " . A_INDEX . "`r`n"
                ToolTip, % tooltipMesg
                Sleep, 10
                ControlGetText, GetTxtFromBox, % componentId
                if (A_INDEX == 19)
                {
                    MsgBox, % "Unable to `Textbox` set " . componentProperties.Label . " loop, tried setting value '" . componentProperties.Value . "', 19 times."
                    ExitApp
                }
            }
            ComponentsExecuted[componentId] := true
        }
        Else If (componentProperties.Type == "Passwordbox")
        {
            conParams := componentProperties.ControlParameters
            GetLengthFromBox := GetPasswordBoxLength(componentId, currWindowId, conParams.controlLeftPaddingPixel, conParams.perCharacterPixel, conParams.perCharacterLeftPaddingPixel, conParams.perCharacterRightPaddingPixel)
            While (StrLen(componentProperties.Value) != GetLengthFromBox && A_INDEX < 20) {
                ControlSetText, % componentId, % componentProperties.Value
                tooltipMesg .= "Got in the " . componentProperties.Label . " (" . componentProperties.Type . ") loop, " . componentId . " : " . A_INDEX . "`r`n"
                ToolTip, % tooltipMesg 
                Sleep, 10
                GetLengthFromBox := GetPasswordBoxLength(componentId, currWindowId, conParams.controlLeftPaddingPixel, conParams.perCharacterPixel, conParams.perCharacterLeftPaddingPixel, conParams.perCharacterRightPaddingPixel)
                if (A_INDEX == 19)
                {
                    MsgBox, % "Unable to `Textbox` set " . componentProperties.Label . " loop, tried setting value '" . componentProperties.Value . "', 19 times."
                    ExitApp
                }
            }
            ComponentsExecuted[componentId] := true
        }
        Else If (componentProperties.Type == "Checkbox")
        {
            Sleep 5000
            ControlGet, isChecked, Checked, , % componentId
            While (componentProperties.Value != isChecked && A_INDEX < 20) {
                ControlClick, % componentId
                tooltipMesg .= "Got in the " . componentProperties.Label . " (" . componentProperties.Type . ") loop, " . componentId . " : " . A_INDEX . "`r`n"
                ToolTip, % tooltipMesg
                Sleep, 10
                ControlGet, isChecked, Checked, , % componentId
                if (A_INDEX == 19)
                {
                    MsgBox, % "Unable to `Checkbox` set " . componentProperties.Label . " loop, tried setting value '" . componentProperties.Value . "', 19 times."
                    ExitApp
                }
            }
            ComponentsExecuted[componentId] := true
        }
        Else If (componentProperties.Type == "Button")
        {
            while(componentProperties.WaitForWindowClose && WinExist(A) && A_INDEX < 20) {
                ControlClick, % componentId
                tooltipMesg .= "Got in the " . componentProperties.Label . " (" . componentProperties.Type . ") loop, " . componentId . " : " . A_INDEX . "`r`n"
                ToolTip, % tooltipMesg
                Sleep, 10
                if (A_INDEX == 19)
                {
                    MsgBox, % "Unable to `Button` click " . componentProperties.Label . " loop, 19 times."
                    ExitApp
                }
            }
            ComponentsExecuted[componentId] := true
        }
    }
    ToolTip, % tooltipMesg
    Sleep 15000 ; Just to display the tooltip
}
Else If WinExist("asdasdasdasdasdasdasdasdasdasdasdasdasdadsasdasdgfgakjhsdjsadfhkjsdfhjksdgfhjsdgfkjhsadfyedsfsadgflhkjsagdfhjsgdkjfbsdcxv")
{
    ; Dummy loop to give an idea how to add other windows
    ; ControlSendRaw, ahk_parent, % parsedCredentialsJSON.password.password
    Send, % parsedCredentialsJSON.password.password
    return
}