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

BlockKeyboardInputs(state = "Off")
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
    ;track our position while correctly typing the password
    static count = 0

    ;is this a keyUp event (or keyDown)
    isKeyUp := NumGet(lParam+0, 8, "UInt") & 0x80

    ;get the scan code of the key pressed/released
    gotScanCode := NumGet(lParam+0, 4, "UInt")

    ;track the left/right shift keys, to handle capitals and symbols in passwords, because getkeystate calls don't work with our method of locking the keyboard
    ;if you can figure out how to use a getkeystate call to check for shift, or you have a better way to handle upper case letters and symbols, let me know
    ; static shifted = 0
    ; if(gotScanCode = 0x2A || gotScanCode = 0x36) {
    ;     if(isKeyUp) {
    ;         shifted := 0
    ;     } else {
    ;         shifted := 1
    ;     }
    ;     return 1
    ; }

    ; ;check password progress/completion
    ; if (!settings.DisablePassword() && !isKeyUp) {
    ;     expectedCharacter := SubStr(settings.Password(), count+1, 1)
    ;     expectedScanCode := GetKeySC(expectedCharacter)
    ;     requiresShift := requiresShift(expectedCharacter)

    ;     ;did they type the correct next password letter?
    ;     if(expectedScanCode == gotScanCode && requiresShift == shifted) {
    ;         count := count + 1

    ;         ;password is complete!
    ;         if(count == StrLen(settings.Password())) {
    ;             count = 0
    ;             shifted = 0
    ;             LockKeyboard(false)
    ;         }
    ;     } else {
    ;         count = 0
    ;     }
    ; }

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
BlockKeyboardInputs("On")
Return

MessageMon(wParam, lParam, msg, hwnd)
{
    global MsgNum
    OnMessage( MsgNum, "" )
    BlockKeyboardInputs("Off")
    AddMessageAndDisplayTooltip("Exiting keyboardBlockerOnFocus.exe", -10000)
    Loop, 200
    {
        Sleep, 50
    }
    ExitApp
}

currentKeyboardBlockMode := false
ShellMessage( wParam, lParam )
{
    global paramWindowId, currentKeyboardBlockMode, tooltipMesg
    WinGet, currentActiveWindowId, ID , A
    changeKeyboardBlockModeTo := ""
    If (paramWindowId == lParam && paramWindowId == currentActiveWindowId && (wParam == 1 || wParam == 4 || wParam == 17 || wParam == 32772)) ; HSHELL_WINDOWACTIVATED Or HSHELL_RUDEAPPACTIVATED
    {
        changeKeyboardBlockModeTo := true
        WinGetClass, sClass, ahk_id %lParam%
        WinGetTitle, sTitle, ahk_id %lParam%
        AddMessageAndDisplayTooltip("Event: " . wParam . ", Title: " . sTitle ", ")
    }
    Else If (paramWindowId != currentActiveWindowId)
    {
        changeKeyboardBlockModeTo := false
    }
    If (changeKeyboardBlockModeTo != "" && currentKeyboardBlockMode != changeKeyboardBlockModeTo)
    {
        changeKeyboardBlockModeTo ? BlockKeyboardInputs("On") : BlockKeyboardInputs("Off")
        AddMessageAndDisplayTooltip("Changing keyboard block mode to: " . changeKeyboardBlockModeTo)
        currentKeyboardBlockMode := changeKeyboardBlockModeTo
    }
}

#Include %A_ScriptDir%\Includes\IncludeVariables.ahk
#Include %A_ScriptDir%\Includes\MouseGestures.ahk
#Include %A_ScriptDir%\displayTooltipAndResetByGesture.ahk
