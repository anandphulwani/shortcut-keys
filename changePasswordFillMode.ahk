#IfWinActive
F1:: ; F1 hotkey.
    }

ReenablePasswordAutoFill:
    PasswordAutoFillMode := true
    ToolTip, % "Password automatic fill mode is now enabled."
    SetTimer, ReenablePasswordAutoFill, Off
    SetTimer, RemoveToolTip, -5000
return
#IfWinActive ; turn off context sensitivity for the new hotkey
