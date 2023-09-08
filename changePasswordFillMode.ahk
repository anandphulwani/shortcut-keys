#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
; SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.

+F8:: ; Shift+F8 hotkey.
    PasswordAutoFillMode := !PasswordAutoFillMode
    ToolTip, % "Password automatic fill mode set to: " . ( PasswordAutoFillMode ? "Enabled" : "Disabled" )
    SetTimer, RemoveToolTip, -1500
    if (PasswordAutoFillMode) {
        WaitForWindowToAppear()
    }
return