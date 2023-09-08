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
#SingleInstance ignore
#Include %A_ScriptDir%\Includes\IncludeVariables.ahk
#Include %A_ScriptDir%\Includes\JSON.ahk
#Include %A_ScriptDir%\Includes\RC4Functions.ahk
#Include %A_ScriptDir%\Includes\Crypt.ahk

#Include %A_ScriptDir%\credentialsEncDecKey.ahk

If ( !parsedCredentialsJSON.haskey("password") || !parsedCredentialsJSON.password.haskey("password"))
{
    MsgBox, Does not contain normal password key or password.password key. Exiting program.
    ExitApp ; Exit the AutoHotkey script
}

PasswordAutoFillMode := true
; WaitForWindowToAppear()

#Include %A_ScriptDir%\changePasswordFillMode.ahk

#Include %A_ScriptDir%\fillOnKeyPress.ahk

#Include %A_ScriptDir%\textToSend.ahk

#IfWinActive ; turn off context sensitivity
RemoveToolTip:
    ToolTip
return
