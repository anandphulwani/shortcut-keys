Process Priority,,High                 ; Run faster
SetBatchLines -1

RC4txt2hex(Data,Pass) {
   Format := A_FormatInteger
   SetFormat Integer, Hex
   b := 0, j := 0
   VarSetCapacity(Result,StrLen(Data)*2)
   Loop 256
      a := A_Index - 1
     ,Key%a% := Asc(SubStr(Pass, Mod(a,StrLen(Pass))+1, 1))
     ,sBox%a% := a
   Loop 256
      a := A_Index - 1
     ,b := b + sBox%a% + Key%a%  & 255
     ,sBox%a% := (sBox%b%+0, sBox%b% := sBox%a%) ; SWAP(a,b)
   Loop Parse, Data
      i := A_Index & 255
     ,j := sBox%i% + j  & 255
     ,k := sBox%i% + sBox%j%  & 255
     ,sBox%i% := (sBox%j%+0, sBox%j% := sBox%i%) ; SWAP(i,j)
     ,Result .= SubStr(Asc(A_LoopField)^sBox%k%, -1, 2)
   StringReplace Result, Result, x, 0, All
   SetFormat Integer, %Format%
   Return Result
}

RC4hex2txt(Data,Pass) {
   b := 0, j := 0, x := "0x"
   VarSetCapacity(Result,StrLen(Data)//2)
   Loop 256
      a := A_Index - 1
     ,Key%a% := Asc(SubStr(Pass, Mod(a,StrLen(Pass))+1, 1))
     ,sBox%a% := a
   Loop 256
      a := A_Index - 1
     ,b := b + sBox%a% + Key%a%  & 255
     ,sBox%a% := (sBox%b%+0, sBox%b% := sBox%a%) ; SWAP(a,b)
   Loop % StrLen(Data)//2
      i := A_Index  & 255
     ,j := sBox%i% + j  & 255
     ,k := sBox%i% + sBox%j%  & 255
     ,sBox%i% := (sBox%j%+0, sBox%j% := sBox%i%) ; SWAP(i,j)
     ,Result .= Chr((x . SubStr(Data,2*A_Index-1,2)) ^ sBox%k%)
   Return Result
}