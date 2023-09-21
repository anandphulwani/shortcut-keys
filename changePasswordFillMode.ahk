#IfWinActive
F1:: ; F1 hotkey.
    global toolTip2Mesg, parsedCredentialsJSON
    toolTip2Mesg := 
    ToolTip

    StartTime := A_TickCount

    longPress := false
    while GetKeyState(A_ThisHotkey)
    {
        if (A_TickCount - StartTime >= 200 && !longPress)
        {
            longPress := true
            SoundBeep, 1000, 120
            AddMessageAndDisplayTooltip(StartTime . ": Long press Activated {" . A_ThisHotkey . "}")
        }
        Sleep 5
    }
    If (longPress)
    {
        AddMessageAndDisplayTooltip(StartTime . ": Long press Block {" . A_ThisHotkey . "}")
        Suspend, On
        SendInput, {%A_ThisHotkey%}
        Sleep, 20
        Suspend, Off
    }
    Else
    {
        AddMessageAndDisplayTooltip(StartTime . ": Short press Block {" . A_ThisHotkey . "}")
        if(PasswordAutoFillMode)
        {
            ; Create a GUI for selecting options
            if WinExist("ahk_group ShortcutKeys_Reenable_Password_Autofillmode_Grp")
            {
                WinActivate
                return
            }
            Gui, 2:Font, s30 cBlack Bold Verdana
            Gui, 2:Add, Text, x10 y10 w400 Center cBlack vMyText1, Mode: Disabled

            Gui, 2:Font,
            Gui, 2:Margin, 5, 5
            Gui, 2:Add, Text, y+30 vMyText2, Re-enable password auto fill mode (Use Enter To Submit):
            Gui, 2:Add, DropDownList, y+5 vSelectedOption w400 , 1 Minute|5 Minutes||10 Minutes|30 Minutes|1 Hour|5 Hours|Never
            Gui, 2:Add, Button, Default g2okay_pressed X50 Y150 w150, OK
            Gui, 2:Add, Button, cancel g2cancel_pressed X+20 YP+0 w150, Cancel
            ; GuiControl, +Center, MyText1
            Gui, 2:Show, Center autosize, Select Re-enable password auto fill mode
            Gui, 2:+LastFound
            Gui2_ID := WinExist()
            GroupAdd, ShortcutKeys_Reenable_Password_Autofillmode_Grp, ahk_id %Gui2_ID%
            return
        }
        Else
        {
            PasswordAutoFillMode := !PasswordAutoFillMode
            AddMessageAndDisplayTooltip(StartTime . ": Password automatic fill mode set to: " . ( PasswordAutoFillMode ? "Enabled" : "Disabled" ))
        }
    }
    AddMessageAndDisplayTooltip("", -5000)
return

#IfWinActive, ahk_group ShortcutKeys_Reenable_Password_Autofillmode_Grp
2cancel_pressed:
2GuiClose:
2GuiEscape:
    Gui, 2:Destroy
    Gui, Destroy
return
; ^ENTER::
; ^NUMPADENTER::
2okay_pressed:
    global toolTip2Mesg, parsedCredentialsJSON
    ; Gui, Submit, NoHide
    Gui 2:+LastFoundExist
    if (!WinExist()) {
        return
    }
    GuiControlGet, SelectedOption
    Gui 2:Submit
    Gui 2:Destroy

    PasswordAutoFillMode := false
    AddMessageAndDisplayTooltip("Password automatic fill mode set to: " . ( PasswordAutoFillMode ? "Enabled" : "Disabled" ))

    ; Process the selected option and disable PasswordAutoFillMode
    If (SelectedOption = "1 Minute")
    {
        SetTimer, ReenablePasswordAutoFill, % ( 1 * 60 * 1000 )
    }
    Else If (SelectedOption = "5 Minutes")
    {
        SetTimer, ReenablePasswordAutoFill, % (5 * 60 * 1000)
    }
    Else If (SelectedOption = "10 Minutes")
    {
        SetTimer, ReenablePasswordAutoFill, % (10 * 60 * 1000)
    }
    Else If (SelectedOption = "30 Minutes")
    {
        SetTimer, ReenablePasswordAutoFill, % (30 * 60 * 1000)
    }
    Else If (SelectedOption = "1 Hour")
    {
        SetTimer, ReenablePasswordAutoFill, % (1 * 60 * 60 * 1000)
    }
    Else If (SelectedOption = "5 Hours")
    {
        SetTimer, ReenablePasswordAutoFill, % (5 * 60 * 60 * 1000)
    }
    Else If (SelectedOption = "Never")
    {
        ; Do Nothing
    }
    AddMessageAndDisplayTooltip("Re-enabling password automatic fill mode in " . SelectedOption, -5000)
Return

ReenablePasswordAutoFill:
    global toolTip2Mesg, parsedCredentialsJSON
    toolTip2Mesg := 
    ToolTip

    PasswordAutoFillMode := true

    SetTimer, ReenablePasswordAutoFill, Off
    AddMessageAndDisplayTooltip("Password automatic fill mode is now enabled.", -5000)
return
#IfWinActive ; turn off context sensitivity for the new hotkey
