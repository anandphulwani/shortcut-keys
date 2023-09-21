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
#InstallKeybdHook
#SingleInstance ignore

#Include %A_ScriptDir%\Includes\IncludeVariables.ahk
#Include %A_ScriptDir%\credentialsEncDecKey.ahk

PasswordAutoFillMode := true
toolTip2Mesg := 

#Include %A_ScriptDir%\changePasswordFillMode.ahk
#Include %A_ScriptDir%\fillAutomaticallyCaller.ahk

#Include %A_ScriptDir%\fillOnKeyPress.ahk

#Include %A_ScriptDir%\textToSend.ahk

RemoveToolTip:
    SetTimer, RemoveToolTip, Off
    ToolTip
return
