#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
; #NoTrayIcon
#SingleInstance Off
#Persistent
; #Warn  ; Enable warnings to assist with detecting common errors.
; SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
SetTitleMatchMode, 1

; Variables required for `displayTooltipAndResetByGesture.ahk` : Start
toolTip2Mesg := 
paramTimeoutToRemoveTooltip :=
mouseX := mouseY := 0
; Variables required for `displayTooltipAndResetByGesture.ahk` : End

If (A_Args.Length() != 1)
{
    MsgBox, % "Incorrect length of arguments ( WindowId ) sent to the script, Args length is " . A_Args.Length() . "."
    for n, param in A_Args ; For each parameter:
    {
        MsgBox Parameter number %n% is %param%.
    }
    ExitApp
}

paramWindowId := A_Args[1]
; WinGetTitle, currWindowTitle, ahk_id %paramWindowId%

currentKeyboardBlockMode := false
hHookKeyboardBlock := 0
BlockKeyboardInputs(changeToState)
{
    ; AddMessageAndDisplayTooltip("In BlockKeyboardInputs fucntion")
    global currentKeyboardBlockMode, hHookKeyboardBlock
    if (currentKeyboardBlockMode == changeToState)
    {
        Return
    }
    currentKeyboardBlockMode := changeToState
    If (changeToState)
    {
        AddMessageAndDisplayTooltip("BlockKeyboardInputs state to set: true.")
        hHookKeyboardBlock := DllCall("SetWindowsHookEx", "Ptr", WH_KEYBOARD_LL:=13, "Ptr", RegisterCallback("Hook_Keyboard","Fast"), "Uint", DllCall("GetModuleHandle", "Uint", 0, "Ptr"), "Uint", 0, "Ptr")

        ; Hotkey, LButton, checkWindowToDoNothingLButton
        ; Hotkey, RButton, checkWindowToDoNothingRButton
        ; Hotkey, MButton, checkWindowToDoNothingMButton
        AddMessageAndDisplayTooltip("BlockKeyboardInputs state to set: true: Done.")
    }
    Else
    {
        AddMessageAndDisplayTooltip("BlockKeyboardInputs state to set false.")
        DllCall("UnhookWindowsHookEx", "Ptr", hHookKeyboardBlock)
        hHookKeyboardBlock := 0

        ; Hotkey, LButton, Off
        ; Hotkey, MButton, Off
        ; Hotkey, RButton, Off
        AddMessageAndDisplayTooltip("BlockKeyboardInputs state to set false: Done.")
    }
}

Hook_Keyboard(nCode, wParam, lParam)
{
    static count = 0 ; track our position while correctly typing the password
    isKeyUp := NumGet(lParam+0, 8, "UInt") & 0x80 ; is this a keyUp event (or keyDown)
    gotScanCode := NumGet(lParam+0, 4, "UInt") ; get the scan code of the key pressed/released
    return 1
}

DllCall("SetTaskmanWindow", "Ptr", A_ScriptHwnd)
DllCall("SetShellWindow", "Ptr", A_ScriptHwnd)
mmSize := 20
VarSetCapacity(MINIMIZEDMETRICS, mmSize, 0)
NumPut(mmSize, MINIMIZEDMETRICS, 0, "UInt")
DllCall("SystemParametersInfo", "UInt", SPI_GETMINIMIZEDMETRICS := 0x002B, "UInt", mmSize, "Ptr", &MINIMIZEDMETRICS, "UInt", 0)
NumPut(NumGet(MINIMIZEDMETRICS, 16, "Int") | ARW_HIDE := 0x0008, MINIMIZEDMETRICS, 16, "Int")
DllCall("SystemParametersInfo", "UInt", SPI_SETMINIMIZEDMETRICS := 0x002C, "UInt", mmSize, "Ptr", &MINIMIZEDMETRICS, "UInt", 0)

DllCall( "RegisterShellHookWindow", "Ptr", A_ScriptHwnd)
MsgNum := DllCall( "RegisterWindowMessage", Str,"SHELLHOOK" )
OnMessage( MsgNum, "ShellMessage" )
OnMessage( 8192, "MessageMon" )
BlockKeyboardInputs(true)

Hotkey, LButton, checkWindowToDoNothingLButton
Hotkey, RButton, checkWindowToDoNothingRButton
Hotkey, MButton, checkWindowToDoNothingMButton

Return

MessageMon(wParam, lParam, msg, hwnd)
{
    global MsgNum
    OnMessage( MsgNum, "" )
    BlockKeyboardInputs(false)
    AddMessageAndDisplayTooltip("Exiting keyboardBlockerOnFocus.exe", -10000)
    Loop, 200
    {
        Sleep, 50
    }
    ExitApp
}

ShellMessage( wParam, lParam )
{
    global paramWindowId, tooltipMesg
    WinGet, currentActiveWindowId, ID , A
    If (paramWindowId == lParam && paramWindowId == currentActiveWindowId && (wParam == 1 || wParam == 4 || wParam == 17 || wParam == 32772)) ; HSHELL_WINDOWACTIVATED Or HSHELL_RUDEAPPACTIVATED
    {
        WinGetClass, sClass, ahk_id %lParam%
        WinGetTitle, sTitle, ahk_id %lParam%
        AddMessageAndDisplayTooltip("Event: " . wParam . ", Title: " . sTitle ", ")
        BlockKeyboardInputs(true)
    }
    Else If (paramWindowId != currentActiveWindowId)
    {
        BlockKeyboardInputs(false)
    }
}

#Include %A_ScriptDir%\Includes\IncludeVariables.ahk
#Include %A_ScriptDir%\Includes\MouseGestures.ahk
#Include %A_ScriptDir%\displayTooltipAndResetByGesture.ahk

checkWindowToDoNothingLButton:
checkWindowToDoNothingMButton:
checkWindowToDoNothingRButton:
    MouseGetPos, , , windowUnderCursor
    If (currentKeyboardBlockMode && windowUnderCursor == paramWindowId)
    {
        Return
    }
    Else
    {
        If ( A_ThisHotkey == "LButton" )
        {
            Click, Left
        }
        Else If ( A_ThisHotkey == "RButton" )
        {
            Click, Right
        }
        Else If ( A_ThisHotkey == "MButton" )
        {
            Click, Middle
        }
    }
Return
