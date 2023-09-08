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

F8:: ; F8 hotkey.
    If WinExist("Radmin security: ")
    {
        Username = User	
        Password = % parsedCredentialsJSON.password.password

        bufferClipboard := clipboard
        WinActivate ; Uses the last found window.

        WaitControlLoad("Edit1", "Radmin security: ")	
        WaitControlLoad("Edit2", "Radmin security: ")	
        WaitControlLoad("Button1", "Radmin security: ")	
        WaitControlLoad("Button2", "Radmin security: ")

	    ControlSetText, Edit1, % Username, Radmin security:
	    ControlSetText, Edit2, % Password, Radmin security:
	
        clipboard := Username
        Clip:= clipboard, SetTxt:= ""
        ControlGetText, SetTxt, Edit1, Radmin security:
        While (Clip != SetTxt && A_index < 5) {
            ToolTip, Got in the User loop
            ControlSetText, Edit1, % clipboard, Radmin security:
            Sleep, 100
            ControlGetText, SetTxt, Edit1, Radmin security:
        }

        ; TODO: Get pixel color from selected window
        ; TODO: Check password length to compute the last asterisk is present
        PixelGetColor, passwordLastLetterColor, 154, 90
        While (passwordLastLetterColor != 0x000000 && A_index < 5) {
            ToolTip, Got in the Password loop
            ControlSetText, Edit2, % Password, Radmin security:
            Sleep, 100
            PixelGetColor, passwordLastLetterColor, 154, 90
        }

        ControlGet, saveUserChkBox, Checked , , Button1, Radmin security:
        If (saveUserChkBox = 0)
        {
            BringControlToFocus("Button1")
            WaitUntilControlHasFocus("Button1")
            ControlSend, Button1, {Space}, Radmin security:
        }

        While (WinExist("Radmin security: ")) {	
            ControlClick, OK, Radmin security:	
            Sleep, 500	
        }

        clipboard:= bufferClipboard
        return
    }
    Else If WinExist("asdasdasdasdasdasdasdasdasdasdasdasdasdadsasdasdgfgakjhsdjsadfhkjsdfhjksdgfhjsdgfkjhsadfyedsfsadgflhkjsagdfhjsgdkjfbsdcxv")
    {
        ; Dummy loop to give an idea how to add other windows
        ; ControlSendRaw, ahk_parent, % parsedCredentialsJSON.password.password, A
        Send, % parsedCredentialsJSON.password.password
        return
    }
    Else
    {
        WinGetTitle, CurrTitle, A
        ToolTip, Doing entry in 3 deci - seconds on %CurrTitle%.
        Sleep, 20
        ToolTip, Doing entry in 2 deci - seconds on %CurrTitle%.
        Sleep, 20
        ToolTip, Doing entry in 1 deci - seconds on %CurrTitle%.
        Sleep, 20
        ToolTip

        WinGetTitle, CurrTitle, A
        ; ControlSend, ahk_parent, % parsedCredentialsJSON.password.password, A
        Send, % parsedCredentialsJSON.password.password

        ToolTip, Entry done on %CurrTitle%.
        SetTimer, RemoveToolTip, -5000
        return
    }
return

^F8:: ; Ctrl+F8 hotkey.
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
    ^ENTER::
    ^NUMPADENTER::
    okay_pressed:
        Gui 1:+LastFoundExist
        if (!WinExist()) {
            return
        }
        Gui 1:Submit
        Gui 1:Destroy
        CurrentKeyDelay := A_KeyDelay
        SetKeyDelay, 30
        SendEvent, {Raw}%input%
        SetKeyDelay, %CurrentKeyDelay%
    Return
    ButtonCancel:
    GuiEscape:
    GuiClose:
        Gui, 1:Destroy
        Gui, Destroy
return

#IfWinActive ; turn off context sensitivity
RemoveToolTip:
    ToolTip
return
