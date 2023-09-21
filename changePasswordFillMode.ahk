+F8:: ; Shift+F8 hotkey.
    PasswordAutoFillMode := !PasswordAutoFillMode
    ToolTip, % "Password automatic fill mode set to: " . ( PasswordAutoFillMode ? "Enabled" : "Disabled" )
    SetTimer, RemoveToolTip, -1500
    if (PasswordAutoFillMode) {
        ; WaitForWindowToAppear()
#IfWinActive
    }
return
#IfWinActive ; turn off context sensitivity for the new hotkey
