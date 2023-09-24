#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
; #NoTrayIcon
#SingleInstance Off
#Persistent
; #Warn  ; Enable warnings to assist with detecting common errors.
; SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
SetTitleMatchMode, 1

; Variables required for `displayTooltipAndResetByGesture.ahk` : Start
toolTip2Mesg := 
paramTimeoutToRemoveTooltip :=
mouseX := mouseY := 0
; Variables required for `displayTooltipAndResetByGesture.ahk` : End

If (A_Args.Length() != 1)
{
    MsgBox, % "Incorrect length of arguments ( WindowId ) sent to the script, Args length is " . A_Args.Length() . "."
    for n, param in A_Args ; For each parameter:
    {
        MsgBox Parameter number %n% is %param%.
    }
    ExitApp
}

paramWindowId := A_Args[1]
WinGetTitle, currWindowTitle, ahk_id %paramWindowId%

BlockKeyboardInputs(state = "Off")
{
    static keys
    keys=Alt,Shift,Ctrl,Space,Enter,Tab,Esc,BackSpace,Del,Ins,Home,End,PgDn,PgUp,Up,Down,Left,Right,CtrlBreak,ScrollLock,PrintScreen,CapsLock
    ,Pause,AppsKey,LWin,LWin,NumLock,Numpad0,Numpad1,Numpad2,Numpad3,Numpad4,Numpad5,Numpad6,Numpad7,Numpad8,Numpad9,NumpadDot
    ,NumpadDiv,NumpadMult,NumpadAdd,NumpadSub,NumpadEnter,NumpadIns,NumpadEnd,NumpadDown,NumpadPgDn,NumpadLeft,NumpadClear
    ,NumpadRight,NumpadHome,NumpadUp,NumpadPgUp,NumpadDel,Media_Next,Media_Play_Pause,Media_Prev,Media_Stop,Volume_Down,Volume_Up
    ,Volume_Mute,Browser_Back,Browser_Favorites,Browser_Home,Browser_Refresh,Browser_Search,Browser_Stop,Launch_App1,Launch_App2
    ,Launch_Mail,Launch_Media,F1,F2,F3,F4,F5,F6,F7,F8,F9,F10,F11,F12,F13,F14,F15,F16,F17,F18,F19,F20,F21,F22
    ,1,2,3,4,5,6,7,8,9,0,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z
    ,²,&,é,",',(,-,è,_,ç,à,),=,$,£,ù,*,~,#,{,[,|,``,\,^,@,],},;,:,!,?,.,/,§,<,>,vkBC
    Loop,Parse,keys, `,
        Hotkey, *%A_LoopField%, KeyboardDummyLabel, %state% UseErrorLevel
    Return
    ; hotkeys need a label, so give them one that do nothing
    KeyboardDummyLabel:
    Return
}

DllCall("SetTaskmanWindow", "Ptr", A_ScriptHwnd)
DllCall("SetShellWindow", "Ptr", A_ScriptHwnd)
mmSize := 20
VarSetCapacity(MINIMIZEDMETRICS, mmSize, 0)
NumPut(mmSize, MINIMIZEDMETRICS, 0, "UInt")
DllCall("SystemParametersInfo", "UInt", SPI_GETMINIMIZEDMETRICS := 0x002B, "UInt", mmSize, "Ptr", &MINIMIZEDMETRICS, "UInt", 0)
NumPut(NumGet(MINIMIZEDMETRICS, 16, "Int") | ARW_HIDE := 0x0008, MINIMIZEDMETRICS, 16, "Int")
DllCall("SystemParametersInfo", "UInt", SPI_SETMINIMIZEDMETRICS := 0x002C, "UInt", mmSize, "Ptr", &MINIMIZEDMETRICS, "UInt", 0)

DllCall( "RegisterShellHookWindow", "Ptr", A_ScriptHwnd)
MsgNum := DllCall( "RegisterWindowMessage", Str,"SHELLHOOK" )
OnMessage( MsgNum, "ShellMessage" )
OnMessage( 8192, "MessageMon" )
Return

MessageMon(wParam, lParam, msg, hwnd)
{
    BlockKeyboardInputs("Off")
    ExitApp
}

tooltipMesg :=
currentKeyboardBlockMode := false
ShellMessage( wParam, lParam )
{
    global paramWindowId, currentKeyboardBlockMode, tooltipMesg
    changeKeyboardBlockModeTo :=
    If (paramWindowId == lParam && (wParam == 1 || wParam == 4 || wParam == 17 || wParam == 32772)) ; HSHELL_WINDOWACTIVATED Or HSHELL_RUDEAPPACTIVATED
    {
        changeKeyboardBlockModeTo := true
        WinGetClass, sClass, ahk_id %lParam%
        WinGetTitle, sTitle, ahk_id %lParam%
        ; tooltipMesg .= "Event: " . wParam . " : " . sTitle . "`r`n"
        ; Tooltip, % tooltipMesg
    }
    Else
    {
        changeKeyboardBlockModeTo := false
    }
    If (currentKeyboardBlockMode != changeKeyboardBlockModeTo)
    {
        changeKeyboardBlockModeTo ? BlockKeyboardInputs("On") : BlockKeyboardInputs("Off")
        ; tooltipMesg .= " Changing keyboard block mode to: " . changeKeyboardBlockModeTo . "`r`n"
        ; Tooltip, % tooltipMesg
        currentKeyboardBlockMode := changeKeyboardBlockModeTo
    }
    Tooltip, % tooltipMesg
}

#Include %A_ScriptDir%\Includes\IncludeVariables.ahk
#Include %A_ScriptDir%\Includes\MouseGestures.ahk
#Include %A_ScriptDir%\displayTooltipAndResetByGesture.ahk
