;
; AutoHotkey Version: 1.x
; Language:       English
; Platform:       Win9x/NT
; Author:         A.N.Other <myemail@nowhere.com>
;
; Script Function:
;	Template script (you can customize this template by editing "ShellNew\Template.ahk" in your Windows folder)
;
SetTitleMatchMode, 2
#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
; SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetKeyDelay, 10, 10
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.

#Persistent
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
        WinActivate ; Uses the last found window.

        WaitControlLoad("Edit1")
        WaitControlLoad("Edit2")
        WaitControlLoad("Button1")
        WaitControlLoad("Button2")

        BringControlToFocus("Edit1")
        WaitUntilControlHasFocus("Edit1")
        ; Sleep, 2000 
        ControlSend, Edit1, {End}, A	
        ; Sleep, 2000 	
        ; ControlSend, Edit1, {Shift down}{Home}{Shift up}, A	
        ; Sleep, 2000 	
        ; ControlSend, Edit1, {Del}, A
        ; Sleep, 2000 
        ControlSend, Edit1, {Shift down}u{Shift up}, A
        ; Sleep, 2000 
        ControlSend, Edit1, ser, A

        BringControlToFocus("Edit2")
        ; Sleep, 2000 
        WaitUntilControlHasFocus("Edit2")
        ; Sleep, 2000 
        ControlSend, Edit2, % parsedCredentialsJSON.password.password, A
        ; Sleep, 2000 

        ControlGet, saveUserChkBox, Checked , , Button1, A
        If (saveUserChkBox = 0)
        {
            BringControlToFocus("Button1")
            WaitUntilControlHasFocus("Button1")
            ControlSend, Button1, {Space}, A
        }

        BringControlToFocus("OK")
        WaitUntilControlHasFocus("OK")
        ControlSend, OK, {Space}, A
        WinWaitClose, "Radmin security: "
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
        Sleep, 80
        ToolTip, Doing entry in 2 deci - seconds on %CurrTitle%.
        Sleep, 80
        ToolTip, Doing entry in 1 deci - seconds on %CurrTitle%.
        Sleep, 80
        ToolTip

        WinGetTitle, CurrTitle, A
        ; ControlSend, ahk_parent, % parsedCredentialsJSON.password.password, A
        Send, % parsedCredentialsJSON.password.password

        ToolTip, Entry done on %CurrTitle%.
        Sleep, 2000
        ToolTip
        return
    }
return

^F8:: ; Ctrl+F8 hotkey.
    InputBox, CommandToRun
    CurrentKeyDelay := A_KeyDelay
    SetKeyDelay, 30
    SendEvent, {Raw}%CommandToRun%
    SetKeyDelay, %CurrentKeyDelay%
return
