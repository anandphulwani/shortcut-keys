;
; AutoHotkey Version: 1.x
; Language:       English
; Platform:       Win9x/NT
; Author:         A.N.Other <myemail@nowhere.com>
;
; Script Function:
;	Template script (you can customize this template by editing "ShellNew\Template.ahk" in your Windows folder)
;
SetTitleMatchMode, 1
#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
; SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetKeyDelay, 10, 10
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.

#Persistent
#UseHook, Off ; Switching it to On makes long press non functionaly
#InstallKeybdHook
#SingleInstance ignore

#Include %A_ScriptDir%\Includes\IncludeVariables.ahk
#Include %A_ScriptDir%\Includes\MouseGestures.ahk
#Include %A_ScriptDir%\credentialsEncDecKey.ahk
#Include %A_ScriptDir%\customTrayMenu_Options.ahk

PasswordAutoFillMode := true
toolTip2Mesg := 

; Variables required for `displayTooltipAndResetByGesture.ahk` : Start
paramTimeoutToRemoveTooltip :=
mouseX := mouseY := 0
; Variables required for `displayTooltipAndResetByGesture.ahk` : End

#Include %A_ScriptDir%\fillAutomaticallyCaller.ahk
#Include %A_ScriptDir%\fillOnKeyPress_functions.ahk

;
;
;
; From here On all those blocks which are subroutine and end with Return or are functions
;
;
;

#Include %A_ScriptDir%\fillOnKeyPress.ahk

#Include %A_ScriptDir%\common_gui_functions.ahk
#Include %A_ScriptDir%\changePasswordFillMode.ahk
#Include %A_ScriptDir%\textToSend.ahk

#Include %A_ScriptDir%\displayTooltipAndResetByGesture.ahk
#Include %A_ScriptDir%\customTrayMenu_Functions.ahk
