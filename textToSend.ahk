^F8:: ; Ctrl+F8 hotkey.
    global toolTip2Mesg, parsedCredentialsJSON
    toolTip2Mesg := 
    ToolTip

    if WinExist("ahk_group ShortcutKeys_Text_To_Send_Grp")
    {
        WinActivate
        return
    }
    Gui, 1:Add, Text, vMyText, Please enter commands to send (Use Ctl+Enter To Submit):
    Gui, 1:Add, Edit, w600 h150 vinput
    Gui, 1:Add, Button, gokay_pressed X150 Y180 w150, OK
    Gui, 1:Add, Button, cancel X+20 YP+0 w150, Cancel
    Gui, 1:Show, Center autosize, ShortcutKeys-Text To Send
    Gui, 1:+LastFound
    Gui1_ID := WinExist()
    GroupAdd, ShortcutKeys_Text_To_Send_Grp, ahk_id %Gui1_ID%
Return
#IfWinActive, ahk_group ShortcutKeys_Text_To_Send_Grp
okay_pressed:
    Gui 1:+LastFoundExist
    if (!WinExist()) {
        return
    }
    Gui 1:Submit
    Gui 1:Destroy
    CurrentKeyDelay := A_KeyDelay
    CurrentKeyDuration := A_KeyDuration
    SetKeyDelay, 30, 10
    BlockInput, On
    Send, {Blind}{Text}%input%
    BlockInput, Off
    SetKeyDelay, %CurrentKeyDelay%, %CurrentKeyDuration%
    AddMessageAndDisplayTooltip("Entering data:" . input, -5000)
Return
ButtonCancel:
GuiEscape:
GuiClose:
    Gui, 1:Destroy
    Gui, Destroy
return
#IfWinActive ; turn off context sensitivity
