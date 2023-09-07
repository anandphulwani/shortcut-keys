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

credentialsFile := ".\credentials.json"
credentialsFileEnc := ".\credentials.json.enc"
credentialsEncDecKey := ""
hashOfcredentialsEncDecKey := "41DCDB6A6ACBA82A87DCAF931115218DFCBFE6ACCF08789856310E0DF7A68199"
saltOfcredentialsEncDecKey := "randomSaltToEncryptTheKey"

RegRead, defaultLoginPassword, HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon, DefaultPassword
If (ErrorLevel = 0)
{
    hash := Crypt.Hash.StrHash(defaultLoginPassword, 4) ; hashes string using SHA_256 algorithm
    If (hash == hashOfcredentialsEncDecKey)
    {
        credentialsEncDecKey := defaultLoginPassword
    }
}

If (credentialsEncDecKey == "")
{
    RegRead, credentialsEncDecKeyFromReg, HKEY_LOCAL_MACHINE\SOFTWARE\shortcut-keys, credentialsEncDecKey
    If (ErrorLevel = 0) 
    {
        decryptedKey := Crypt.Encrypt.StrDecrypt(credentialsEncDecKeyFromReg, saltOfcredentialsEncDecKey, 1, 4)
        hash := Crypt.Hash.StrHash(decryptedKey, 4)
        If (hash == hashOfcredentialsEncDecKey)
        {
            credentialsEncDecKey := decryptedKey
        }
        Else
        {
            MsgBox, Incorrect credentialsEncDecKey read from the registry. Program exiting.
            ExitApp
        }
    }
    Else
    {
        InputBox, enteredPassword, Enter Password, Please enter password to encrypt/decrypt credentials.json:, hide
        If ErrorLevel
        {
            MsgBox, You canceled or closed the input box. Program exiting.
            ExitApp
        }
        Else
        {
            hash := Crypt.Hash.StrHash(enteredPassword, 4) ; hashes string using SHA_256 algorithm
            If (hash == hashOfcredentialsEncDecKey)
            {
                encryptedKey := Crypt.Encrypt.StrEncrypt(enteredPassword, saltOfcredentialsEncDecKey, 1, 4)
                RegWrite, REG_SZ, HKEY_LOCAL_MACHINE\SOFTWARE\shortcut-keys, credentialsEncDecKey, %encryptedKey%
                If ErrorLevel
                {
                    MsgBox, Unable to save encryption key to registry. Program exiting.
                    ExitApp
                }
                Else
                {
                    credentialsEncDecKey := enteredPassword
                }
            }
            Else
            {
                MsgBox, Incorrect password. Program exiting.
                ExitApp
            }
        }
    }
}

If (credentialsEncDecKey == "")
{
    MsgBox, credentialsEncDecKey not set. Program exiting.
    ExitApp
}

If FileExist(credentialsFile)
{
    FileRead, credentialsContent, %credentialsFile%
    encryptedData := Crypt.Encrypt.StrEncrypt(credentialsContent, credentialsEncDecKey, 1, 4)
    If (encryptedData == "")
    {
        MsgBox, Unable to encrypt credentials.json data.
        ExitApp
    }
    Else
    {
        If FileExist(credentialsFileEnc)
        {
            FileDelete, %credentialsFileEnc%
            If ErrorLevel 
            {
                MsgBox, Unable to delete older credentials.json.enc file.
                ExitApp
            }
        }
        Else
        {
            MsgBox, older credentials.json.enc does not exist
        }
        FileAppend, %encryptedData%, %credentialsFileEnc%
        If ErrorLevel 
        {
            MsgBox, Unable to write credentials.json.enc file
            ExitApp
        }
        Else
        {
            FileDelete, %credentialsFile%
        }
    }
}

parsedCredentialsJSON := {}
If FileExist(credentialsFileEnc)
{
    FileRead, CredentialsEncContent, %credentialsFileEnc%
    If ErrorLevel 
    {
        MsgBox, Unable to read credentials.json.enc file
        ExitApp
    }
    decryptedCredentials := Crypt.Encrypt.StrDecrypt(CredentialsEncContent, credentialsEncDecKey, 1, 4)
    If (decryptedCredentials == 0)
    {
        MsgBox, Unable to decrypt credentials.json.enc file
        ExitApp
    }
    Try {
        parsedCredentialsJSON := JSON.Load(decryptedCredentials)
    } Catch e {
        MsgBox, credentials.json has a string which is invalid JSON
        ExitApp
    }
}
Else
{
    MsgBox, Neither Credentials.json nor Credentials.json.enc exists. Exiting program.
    ExitApp ; Exit the AutoHotkey script
}

If ( !parsedCredentialsJSON.haskey("password") || !parsedCredentialsJSON.password.haskey("password"))
{
    MsgBox, Does not contain normal password key or password.password key. Exiting program.
    ExitApp ; Exit the AutoHotkey script
}

F8:: ; F8 hotkey.
    If WinExist("Radmin security: ")
    {
        bufferClipboard:= clipboard
        WinActivate ; Uses the last found window.

        WaitControlLoad("Edit1", "Radmin security: ")	
        WaitControlLoad("Edit2", "Radmin security: ")	
        WaitControlLoad("Button1", "Radmin security: ")	
        WaitControlLoad("Button2", "Radmin security: ")

        clipboard = User
        ControlSetText, Edit1, 
        Clip:= clipboard, SetTxt:= ""
        While (Clip != SetTxt && A_index < 5) {
            ToolTip, Got in the User loop
            ControlSetText, Edit1, % clipboard, Radmin security:
            Sleep, 100
            ControlGetText, SetTxt, Edit1, Radmin security:
        }

        clipboard = % parsedCredentialsJSON.password.password
        ControlSetText, Edit2, 
        Clip:= clipboard, SetTxt:= ""
        While (Clip != SetTxt && A_index < 5) {
            ControlSetText, Edit2, % clipboard, Radmin security:
            Sleep, 10
            ControlGetText, SetTxt, Edit2, Radmin security:
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
