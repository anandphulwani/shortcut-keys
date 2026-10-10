; JXON for AutoHotkey v2, vendored from TheArkive/JXON_ahk2.
; MIT license; see THIRD_PARTY_NOTICES.md.

Jxon_Load(&src, args*) {
    key := "", isKey := false
    stack := [tree := []]
    next := '"{[01234567890-tfn'
    pos := 0

    while ((ch := SubStr(src, ++pos, 1)) != "") {
        if InStr(" `t`n`r", ch)
            continue
        if !InStr(next, ch, true) {
            lines := StrSplit(SubStr(src, 1, pos), "`n")
            line := lines.Length
            column := pos - InStr(src, "`n",, -(StrLen(src) - pos + 1))
            message := Format("{}: line {} col {} (char {})"
                , next == "" ? ["Extra data", ch := SubStr(src, pos)][1]
                : next == "'" ? "Unterminated string starting at"
                : next == "\" ? "Invalid \escape"
                : next == ":" ? "Expecting ':' delimiter"
                : next == '"' ? "Expecting object key enclosed in double quotes"
                : next == '"}' ? "Expecting object key or object closing '}'"
                : next == ",}" ? "Expecting ',' delimiter or object closing '}'"
                : next == ",]" ? "Expecting ',' delimiter or array closing ']'"
                : ["Expecting JSON value", ch := SubStr(src, pos, (SubStr(src, pos) ~= "[\]\},\s]|$") - 1)][1]
                , line, column, pos)
            throw Error(message, -1, ch)
        }

        obj := stack[1]
        isArray := obj is Array

        if i := InStr("{[", ch) {
            val := i == 1 ? Map() : []
            isArray ? obj.Push(val) : obj[key] := val
            stack.InsertAt(1, val)
            next := '"' ((isKey := ch == "{") ? "}" : "{[]0123456789-tfn")
        } else if InStr("}]", ch) {
            stack.RemoveAt(1)
            next := stack[1] == tree ? "" : stack[1] is Array ? ",]" : ",}"
        } else if InStr(" ,:", ch) && ch != " " {
            isKey := !isArray && ch == ","
            next := isKey ? '"' : '"{[0123456789-tfn'
        } else {
            if ch == '"' {
                i := pos
                while i := InStr(src, '"',, i + 1) {
                    val := StrReplace(SubStr(src, pos + 1, i - pos - 1), "\\", "\u005C")
                    if SubStr(val, -1) != "\"
                        break
                }
                if !i {
                    pos--, next := "'"
                    continue
                }
                pos := i
                val := StrReplace(val, "\/", "/")
                val := StrReplace(val, '\"', '"')
                val := StrReplace(val, "\b", "`b")
                val := StrReplace(val, "\f", "`f")
                val := StrReplace(val, "\n", "`n")
                val := StrReplace(val, "\r", "`r")
                val := StrReplace(val, "\t", "`t")
                i := 0
                while i := InStr(val, "\",, i + 1) {
                    if SubStr(val, i + 1, 1) != "u" {
                        pos -= StrLen(SubStr(val, i)), next := "\"
                        continue 2
                    }
                    codepoint := Abs("0x" SubStr(val, i + 2, 4))
                    val := SubStr(val, 1, i - 1) Chr(codepoint) SubStr(val, i + 6)
                }
                if isKey {
                    key := val, next := ":"
                    continue
                }
            } else {
                val := SubStr(src, pos, i := RegExMatch(src, "[\]\},\s]|$",, pos) - pos)
                if IsInteger(val) || IsFloat(val)
                    val += 0
                else if val == "true" || val == "false"
                    val := val == "true"
                else if val == "null"
                    val := ""
                else {
                    pos--, next := "#"
                    continue
                }
                pos += i - 1
            }
            isArray ? obj.Push(val) : obj[key] := val
            next := obj == tree ? "" : isArray ? ",]" : ",}"
        }
    }
    return tree[1]
}

Jxon_Dump(obj, indent := "", level := 1) {
    if IsObject(obj) {
        if !(obj is Array || obj is Map)
            throw TypeError("Only Map and Array values can be encoded as JSON")
        if IsInteger(indent) {
            if indent < 0
                throw ValueError("Indent must be non-negative")
            indentText := ""
            Loop indent
                indentText .= " "
            indent := indentText
        }
        currentIndent := ""
        Loop indent ? level : 0
            currentIndent .= indent
        isArray := obj is Array
        output := ""
        for key, value in obj {
            if !isArray
                output .= Jxon_Escape(String(key)) (indent ? ": " : ":")
            output .= Jxon_Dump(value, indent, level + 1) (indent ? ",`n" currentIndent : ",")
        }
        if output != "" {
            output := Trim(output, ",`n" indent)
            if indent != ""
                output := "`n" currentIndent output "`n" SubStr(currentIndent, StrLen(indent) + 1)
        }
        return isArray ? "[" output "]" : "{" output "}"
    }
    if obj is Number
        return obj
    return Jxon_Escape(String(obj))
}

Jxon_Escape(value) {
    value := StrReplace(value, "\", "\\")
    value := StrReplace(value, "`t", "\t")
    value := StrReplace(value, "`r", "\r")
    value := StrReplace(value, "`n", "\n")
    value := StrReplace(value, "`b", "\b")
    value := StrReplace(value, "`f", "\f")
    value := StrReplace(value, '"', '\"')
    return '"' value '"'
}
