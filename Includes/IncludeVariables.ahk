#Include %A_ScriptDir%\Includes\Acc.ahk

SplitPath, A_ScriptName,,,, ScriptName
IniRead, WinDelay, Parameters.ini, %ScriptName%, WinDelay
IniRead, ControlDelay, Parameters.ini, %ScriptName%, ControlDelay
IniRead, KeyDelay, Parameters.ini, %ScriptName%, KeyDelay
IniRead, MouseDelay, Parameters.ini, %ScriptName%, MouseDelay

SetWinDelay, WinDelay
SetControlDelay, ControlDelay
SetKeyDelay, KeyDelay
SetMouseDelay, MouseDelay

WaitControlLoad(mi="", wTit="", timeout=86400000)
    {
    DetectHiddenText, On
    if (timeout<0)
        return -1
    if(wTit == "")
        WinGetActiveTitle, wTit
    ControlGet, R, Visible,, %mi%, %wTit%
    if(!R)
        {
        Sleep, 100
        Tooltip, Waiting For Control To Load: %mi% and timingout at %timeout%
        WaitControlLoad(mi, wTit, timeout-100)
        }
    else
        return 1
    }

WaitControlUnload(mi="", wTit="", timeout=86400000)
    {
    DetectHiddenText, On
    if (timeout<0)
        return -1
    if(wTit == "")
        WinGetActiveTitle, wTit
    ControlGet, R, Visible,, %mi%, %wTit%
    if(R)
        {
        Sleep, 100
        Tooltip, Waiting For Control To Unload: %mi% and timingout at %timeout%
        WaitControlUnload(mi, wTit, timeout-100)
        }
    else
        return 1
    }

BringControlToFocus(mi="", timeout=86400000)
    {
    if(timeout>86000000 and timeout<86398000)
        Msgbox, Waiting for Control Name %mi%.
    DetectHiddenText, On
    if (timeout<0)
        return -1
    WinGetActiveTitle, wTit
    ControlFocus, %mi%, %wTit%
    if(ErrorLevel)
        {
        ErrorLevel = 0
        Sleep, 100
        BringControlToFocus(mi, timeout-100)
        }
    else
        {
        return 1
        }
    }

WaitUntilControlHasFocus(mi="", timeout=86400000)
    {
    if(timeout>86000000 and timeout<86398000)
        Msgbox, Waiting for Control Name %mi%.
    DetectHiddenText, On
    if (timeout<0)
        return -1
    WinGetActiveTitle, wTit
    ControlGetFocus, CurrFocus, %wTit%
    if(ErrorLevel or %CurrFocus% != %mi%)
        {
        ErrorLevel = 0
        Sleep, 100
        WaitUntilControlHasFocus(mi, timeout-100)
        }
    else
        return 1
    }


ActivateWindow(mi,timeout=86400000)
    {
    if (timeout<0)
        return -1
    WinActivate,ahk_class %mi%
    WinGetClass, class, A
    If(%mi%==%class%)
        return 1
    else
        {
        ActivateWindow(mi, timeout-100)
        }
    }


ActivateWindowAndWaitControlLoad(control,window)
    {
    ActivateWindow(%window%)
    returnVal = WaitControlLoad(%control%,1000)
    if(returnVal == -1)
        ActivateWindowAndWaitControlLoad(%control%, %window%)
    }

ListActiveWindows()
    {
    WinGetClass, class, A
    WinGetActiveTitle, wTit
    if(class != "progman")
        {
        Msgbox, The Class is %class%, and title is %wTit%.
        Sleep, 1000
        }
    Sleep, 100
    ListActiveWindows()
    ;Class= CoverWindowClass
    ;Class= WorkerW
    }

WaitForContextMenuCnt(conMenuCnt, timeout=86400000)
    {
    if (timeout<0)
        return -1
    WinGet, currConMenuCnt, Count, ahk_class #32768
    if(timeout>86000000 and timeout<86398000)
        {
        Sleep 10000
        Tooltip, currConMenuCnt is %currConMenuCnt% and conMenuCnt is %conMenuCnt%.
        Sleep 10000
        }
    if (currConMenuCnt != conMenuCnt)
        {
        Sleep 100
        WaitForContextMenuCnt(conMenuCnt, timeout-100)
        }
    ; Sleep 1000
    }

GetContextMenuCnt()
    {
    WinGet, cnt, Count, ahk_class #32768
    return cnt
    }


ActivateDesktop(timeout=86400000) ; ahk_class WorkerW, WorkerWs
    {
    if (timeout<0)
        return -1
    if(timeout>86000000 and timeout<86398000)
        {
        Sleep 10000
        WinGetClass, currActClass, A
        Tooltip, currActClass is %currActClass%
        Sleep 10000
        }
    ; Send #d
    WinActivate, ahk_class Progman
    WinWaitActive, ahk_class Progman,,1
    WinGetClass, currActClass, A
    if(currActClass != "Progman")
        {
        Sleep 100
        ActivateDesktop(timeout-100)
        }
    Click 0, 0 ;
    }


; ListActiveWindows()
; WaitControlLoad("SysListView321",ahk_class Progman)
; ActivateWindowAndWaitControlLoad("SysListView321",Progman)

WaitForHwndToChange(objname, hWndInfoComp,timeout=86400000)
    {
    if (timeout<0)
        return -1
    ControlGet, hWndInfo , hWnd,, %objname%, A
    if(hWndInfo = hWndInfoComp)
        {
        Tooltip, hWndInfo is %hWndInfo% and Original was %hWndInfoComp%
        Sleep 100
        WaitForHwndToChange(objname, hWndInfoComp, timeout-100)
        }
    else
        {
        Tooltip, Exiting on hWndInfo is %hWndInfo% and Original was %hWndInfoComp%
        }
    }

WaitForChildCountToChange(objname, childIndex, orgChildCount,timeout=86400000)
    {
    if (timeout<0)
        return -1

    ControlGet, hWndInfo , hWnd,, %objname%, A
    directUIObj := Acc_ObjectFromWindow(hWndInfo)
    childObj := Acc_Children(directUIObj)[childIndex]
    currChildCount := childObj.accChildCount

    if(orgChildCount == currChildCount)
        {
        Sleep 100
        ; Tooltip, Childcount remains the same %currChildCount% and timingout at %timeout%
        WaitForChildCountToChange(objname, childIndex, orgChildCount,timeout-100)
        }
    else
        {
        ; Tooltip, Childs have changed
        }
    }

WaitForDefaultActionToSet(obj, defaultActionToWait, timeout=86400000)
    {
    if (timeout<0)
        return -1
    currDefaultAction := obj.accDefaultAction(0)
    if(defaultActionToWait != currDefaultAction)
        {
        Sleep 100
        Tooltip, default action still not set and finding %defaultActionToWait% and current action is %currDefaultAction% and timingout at %timeout%
        WaitForDefaultActionToSet(obj, defaultActionToWait, timeout-100)
        }
    else
        {
        Tooltip, default action have changed
        }
    }


WaitForRadioChecked(radioObjName, winTitle, timeout=86400000)
    {
    if (timeout<0)
        return -1
    ControlGet, radioState, Checked,, %radioObjName%, %winTitle%
    if(radioState != 1)
        {
        Sleep 100
        Tooltip, radio not checked its value is %radioState% and timingout at %timeout%
        WaitForRadioChecked(radioObjName, winTitle, timeout-100)
        }
    else
        {
        Tooltip, radio is checked
        }
    }

WaitForRadioUnchecked(radioObjName, winTitle, timeout=86400000)
    {
    if (timeout<0)
        return -1
    ControlGet, radioState, Checked,, %radioObjName%, %winTitle%
    if(radioState != 0)
        {
        Sleep 100
        Tooltip, radio not unchecked its value is %radioState% and timingout at %timeout%
        WaitForRadioUnchecked(radioObjName, winTitle, timeout-100)
        }
    else
        {
        Tooltip, radio is unchecked
        }
    }

WaitForPixelColorToSet(XCordinate, YCordinate, ColorToMatch, timeout=86400000)
    {
    PixelGetColor, OutputVar, %XCordinate%, %YCordinate%
    while(OutputVar != ColorToMatch and timeout>0)
        {
        Sleep 100
        timeout := timeout-100
        Tooltip, Color still not matched and timingout at %timeout% and Color To Match %ColorToMatch% and Found Color %OutputVar%
        PixelGetColor, OutputVar, %XCordinate%, %YCordinate%
        }
    if (timeout <= 0)
        return -1
    else
        {
        Tooltip, Found Color at timeout %timeout% and OutputVar is %OutputVar% and ColorToMatch is %ColorToMatch%
        return 1
        }
    }

WaitForControlToGetFocus(cntrl_name, timeout=86400000)
    {
    if (timeout<0)
        return -1
    ControlGetFocus, OutputVar
    if(OutputVar != cntrl_name)
        {
        Sleep 100
        Tooltip, Control still not in focus and timingout at %timeout% and Control To Focus %cntrl_name% and Found Focus At %OutputVar%
        WaitForControlToGetFocus(cntrl_name, timeout-100)
        }
    else
        {
        Tooltip, Control in focus - %OutputVar%
        }
    }

WaitUntilNameMatches(obj, nameToWait, timeout=86400000)
    {
    if (timeout<0)
        return -1
    currName := obj.accName(0)
    if(nameToWait != currName)
        {
        Sleep 100
        Tooltip, name still not set waiting for %nameToWait% and current name is %currName% and timingout at %timeout%
        WaitUntilNameMatches(obj, nameToWait, timeout-100)
        }
    else
        {
        Tooltip, name has been found
        }
    }

RemoveConsecutiveDuplicates(inputString) 
    {
    ; Initialize an empty string to store the result
    resultString := ""

    ; Initialize a variable to store the previous character
    prevChar := ""

    ; Iterate through each character in the input string
    for i, char in StrSplit(inputString, "")
        {
        ; If the current character is different from the previous character, add it to the result string
        if (i = 1 || char != prevChar)
            resultString .= char

        ; Update the previous character for the next iteration
        prevChar := char
        }

    ; Return the result string
    return resultString
    }
