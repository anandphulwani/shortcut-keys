fillOnKeyPress(isSlow, textToEnter, currentWindowId)
{
    global toolTip2Mesg, parsedCredentialsJSON
    sleepTime := 0
    SetKeyDelay, 10, 10
    if(isSlow)
    {
        ; Increase the delay
        sleepTime := 100
        SetKeyDelay, 100, 50
    }
    WinGetTitle, CurrTitle, A
    Loop, 3
    {
        AddMessageAndDisplayTooltip("Doing entry in " . (3 - (A_INDEX - 1)) . " deci - seconds on " . CurrTitle)
        Sleep, % sleepTime
    }

    passwordToSend := textToEnter
    mode := "controlsend"
    If (mode == "send")
    {
        BlockInput, On
        ; This works perfectly, but the key speed is too much
        ; Send, {Blind}{Text}%passwordToSend%
        ; If the Shift key is pressed, the password is sent as it was send with Shift key pressed, all things in capital and special characters.
        ; Send, {Blind}%passwordToSend%
        ; The Shift key is released when this is sent, while it is pressed physically, applies to the next two options below
        ; Send, {Text}%passwordToSend%
        ; Send, %passwordToSend%

        Loop, Parse, passwordToSend
        {
            Send, {Blind}{Text}%A_LoopField%
            Sleep, % sleepTime
        }
        BlockInput, Off
    }
    Else If (mode == "controlsend")
    {
        Loop, Parse, passwordToSend
        {
            ControlSend,, {Blind}{Text}%A_LoopField%, ahk_id %currentWindowId%
            Sleep, % sleepTime
        }
        ; ControlSend, ahk_parent, % parsedCredentialsJSON.password.password, A
    }
    AddMessageAndDisplayTooltip("Password sent is: " . passwordToSend)

    if(isSlow)
    {
        ; Bring back to normal
        SetKeyDelay, 10, 10
    }
    AddMessageAndDisplayTooltip("Entry done on " . CurrTitle, -5000)
}
