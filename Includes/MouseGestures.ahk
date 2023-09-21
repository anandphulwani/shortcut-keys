; ~Ctrl::
;     GetMouseGesture(True)
;     While GetKeyState( LTrim(A_ThisHotkey, "~") )
;     {
;         ToolTip % MG := GetMouseGesture()
;         Sleep 150
;     }
;     ;left <= 20% of screen width, right >= 80% of screen width, top <= 20% of screen height, bottom >= 80% of screen height
;     MQ := SubStr(MouseQuadrant(20, 80, 20, 80), 1, 1) ; take only the first letter of the quadrant, for simplified function names...

;     If IsFunc(MG "_" MQ)
;     {
;         %MG%_%MQ%()
;     }
;     Else If IsFunc(MG)
;     {
;         %MG%(); example allows creation of gestures by defining functions that comprise U, D, R, L as function name, with no upper limit on the extent of the gesture, i.e UDUDUDUDL for ex.
;     }
;     ToolTip
;     GetMouseGesture(True)
; Return

UDL()
{
    MsgBox % "Function Run, if no function was defined for specific quadrant. Or Quadrant Has No Assigned Function.`n`n CurrentQuadrant:`n`t" MouseQuadrant(20, 80, 20, 80)
}

UDL_T()	; function defined gesture example for example below
{
    MsgBox Gesture On Top
}

UDL_L() ; function defined gesture example for example below
{
    MsgBox Gesture To The LEFT
}

UDL_R() ; function defined gesture example for example below
{
    MsgBox Gesture To The Right
}

;returns if screen is on top, bottom, center, left, right area of screen given the defined scope in percent of each area...see example.
/*
					Top
	___________________________________
	L	|						|	R
	E	|						|	y
	F	|		C E N T E R		|	T
	T	|						|
	____|_______________________|______
					Bottom
*/
;defined scopes are in 'percent', i.e left scope means anything below defined % is designated left, right scope is anything above defined %...
MouseQuadrant(leftScope, rightScope, topScope, bottomScope, coordMode := "screen")
{
    CoordMode, Mouse, % coordMode
    MouseGetPos, mX, mY, mHwnd, mCtrl
    WinGetPos, wX, wY, wW, hH, A
    If (mX <= leftScope/100*(coordMode = "screen" ? A_ScreenWidth : wW) && mY >= topScope/100*(coordMode = "screen" ? A_ScreenHeight : hH) && mY <= bottomScope/100*(coordMode = "screen" ? A_ScreenHeight : hH))
    {
        Return "LEFT"
    }
    Else If (mX >= rightScope/100*(coordMode = "screen" ? A_ScreenWidth : wW) && mY >= topScope/100*(coordMode = "screen" ? A_ScreenHeight : hH) && mY <= bottomScope/100*(coordMode = "screen" ? A_ScreenHeight : hH))
    {
        Return "RIGHT"
    }
    Else If (mY <= topScope/100*(coordMode = "screen" ? A_ScreenHeight : hH))
    {
        Return "TOP"
    }
    Else If (mY >= bottomScope/100*(coordMode = "screen" ? A_ScreenHeight : hH))
    {
        Return "BOTTOM"
    }
    Else
    {
        Return "CENTER"
    }
}

GetMouseGesture(reset := false)
{
    Static
    mousegetpos, xpos2, ypos2
    dx := xpos2 - xpos1
    dy := ypos1 - ypos2
    abs(dy) >= abs(dx) ? (dy > 0 ? (track := "u") : (track := "d")) : (dx > 0 ? (track := "r") : (track := "l"))
    If abs(dy) < 4 and abs(dx) < 4
        track := ""
    xpos1 := xpos2
    ypos1 := ypos2
    If track <> SubStr(gesture, 0, 1)
        gesture := gesture . track
    gesture := (reset ? "" : gesture)
    Return gesture
}
