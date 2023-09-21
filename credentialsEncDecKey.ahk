#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
; SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.

#Include %A_ScriptDir%\Includes\JSON.ahk
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

If ( !parsedCredentialsJSON.haskey("passwords") || !parsedCredentialsJSON.passwords.haskey("password"))
{
    MsgBox, Does not contain normal password key or password.password key. Exiting program.
    ExitApp
}
