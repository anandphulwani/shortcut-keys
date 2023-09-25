#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
#NoTrayIcon
#SingleInstance Off
#Persistent
; #Warn  ; Enable warnings to assist with detecting common errors.
; SendMode Input  ; Recommended for new scripts due to its superior speed and reliability. ; TODO: Check this later
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
SetTitleMatchMode, 1

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

;
;
;
#Include %A_ScriptDir%\Includes\IncludeVariables.ahk
#Include %A_ScriptDir%\Includes\MouseGestures.ahk
#Include %A_ScriptDir%\credentialsEncDecKey.ahk

; Variables required for `displayTooltipAndResetByGesture.ahk` : Start
toolTip2Mesg := 
paramTimeoutToRemoveTooltip :=
mouseX := mouseY := 0
; Variables required for `displayTooltipAndResetByGesture.ahk` : End

Gui, 1:Add, Text, vMyText, Please enter commands to send (Use Ctl+Enter To Submit):
Gui, 1:Add, Edit, w600 h150 vinput
Gui, 1:Add, Button, gokay_pressed X150 Y180 w150, OK
Gui, 1:Add, Button, cancel X+20 YP+0 w150, Cancel
Gui, 1:Show, Center autosize, ShortcutKeys-Text To Send
Gui, 1:+LastFound
Gui1_ID := WinExist()
GroupAdd, ShortcutKeys_Text_To_Send_Grp, ahk_id %Gui1_ID%
Return

#IfWinActive, ahk_group ShortcutKeys_Text_To_Send_Grp ;
    okay_pressed:
        Gui 1:+LastFoundExist
        if (!WinExist()) {
            return
        }
        Gui 1:Submit
        Gui 1:Destroy

        ; isMessageAdded := false
        ; while (GetKeyState("Ctrl") || GetKeyState("Shift"))
        ; {
        ;     If (!isMessageAdded)
        ;     {
        ;         isMessageAdded := true
        ;         AddMessageAndDisplayTooltip(StartTime . ": Waiting for Shift/Ctrl key to be released.....")
        ;     }
        ;     Sleep 5
        ; }

        ; WinGet, currentWindowId, ID, A
        WinGetTitle, currentTitle, ahk_id %paramWindowId%
        AddMessageAndDisplayTooltip("Current title:" . currentTitle . ", Current Id:" . paramWindowId)
        CurrentKeyDelay := A_KeyDelay
        CurrentKeyDuration := A_KeyDuration
        SetKeyDelay, 30, 30

        Run, %A_ScriptDir%\keyboardBlockerOnFocus.exe %paramWindowId%, , , keyboardBlockerOnFocusPID
        ; BlockInput, On
        ; Send, {Blind}{Text}%input%
        Send {Ctrl Up}
        Sleep 30
        Send {Shift Up}
        Sleep 30
        Send {Alt Up}
        Sleep 30
        ControlSendRaw,, %input%, ahk_id %paramWindowId%
        ; BlockInput, Off

        PostMessage, 8192, , , , ahk_pid %keyboardBlockerOnFocusPID%
        SetKeyDelay, %CurrentKeyDelay%, %CurrentKeyDuration%
        AddMessageAndDisplayTooltip("Entering data:" . input, -5000)
        Loop 100
        {
            Sleep 50
        }
    ExitApp
    Return
    ButtonCancel:
    GuiEscape:
    GuiClose:
        Gui, 1:Destroy
        Gui, Destroy
    ExitApp
    return
#IfWinActive

#Include %A_ScriptDir%\Includes\IncludeVariables.ahk
#Include %A_ScriptDir%\Includes\MouseGestures.ahk
#Include %A_ScriptDir%\common_gui_functions.ahk
#Include %A_ScriptDir%\displayTooltipAndResetByGesture.ahk

Return 
