#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
#NoTrayIcon
#SingleInstance Off
#Persistent
; #Warn  ; Enable warnings to assist with detecting common errors.
; SendMode Input  ; Recommended for new scripts due to its superior speed and reliability. ; TODO: Check this later
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
SetTitleMatchMode, 1

If (A_Args.Length() != 2 && A_Args.Length() != 3)
{
    MsgBox, % "Incorrect length of arguments ( WindowId, longPress, additionalModifiers ) sent to the script, Args length is " . A_Args.Length() . "."
    for n, param in A_Args ; For each parameter:
    {
        MsgBox Parameter number %n% is %param%.
    }
    ExitApp
}

paramWindowId := A_Args[1]
paramLongPress := A_Args[2]
paramAdditionalModifiers := A_Args[3]

SetTimer, BailOut, 60000 ; exits after 60 seconds
;
;
;
#Include %A_ScriptDir%\Includes\IncludeVariables.ahk
#Include %A_ScriptDir%\Includes\MouseGestures.ahk
#Include %A_ScriptDir%\credentialsEncDecKey.ahk

#Include %A_ScriptDir%\fillOnKeyPress_functions.ahk

; Variables required for `displayTooltipAndResetByGesture.ahk` : Start
toolTip2Mesg := 
paramTimeoutToRemoveTooltip :=
mouseX := mouseY := 0
; Variables required for `displayTooltipAndResetByGesture.ahk` : End

If (paramLongPress)
{
    AddMessageAndDisplayTooltip("Long press Block (" . A_ThisHotkey . ")")
    fillOnKeyPress(true, paramAdditionalModifiers, paramWindowId)
}
Else
{
    AddMessageAndDisplayTooltip("Short press Block (" . A_ThisHotkey . ")")
    fillOnKeyPress(false, paramAdditionalModifiers, paramWindowId)
}

Loop 100
{
    Sleep 50
}
ExitApp

#Include %A_ScriptDir%\Includes\IncludeVariables.ahk
#Include %A_ScriptDir%\Includes\MouseGestures.ahk
#Include %A_ScriptDir%\displayTooltipAndResetByGesture.ahk

Return 

BailOut:
ExitApp
