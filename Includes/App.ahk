class AppInfo {
    static Name := "ShortcutKeys"
    static Version := "2.1.0"
    static ProtocolVersion := 2
    static CredentialSchemaVersion := 2
    static CredentialPath := A_ScriptDir "\credentials.json.enc"
    static RegistryPath := "HKCU\Software\shortcut-keys"
    static RegistryValue := "credentialsEncDecKeyDpapi"
    static LegacyRegistryPath := "HKLM\SOFTWARE\shortcut-keys"
    static LegacyRegistryValue := "credentialsEncDecKey"
    static LegacyRegistryPassword := "randomSaltToEncryptTheKey"
    static DefaultControlTimeoutMs := 5000
    static DefaultRetryMs := 50
}

class AppError extends Error {
    __New(message, code := "APP_ERROR", extra := "") {
        super.__New(message, -1, extra)
        this.Code := code
    }
}

MapGet(map, key, default := "") {
    return Type(map) == "Map" && map.Has(key) ? map[key] : default
}

MapDeleteIfPresent(map, key) {
    if Type(map) != "Map"
        return false
    try {
        map.Delete(key)
        return true
    } catch {
        return false
    }
}

MapTakeIfPresent(map, key, &value) {
    if Type(map) != "Map"
        return false
    try {
        value := map.Delete(key)
        return true
    } catch {
        return false
    }
}

RequireMap(value, name) {
    if Type(value) != "Map"
        throw AppError(name " must be a JSON object", "INVALID_CONFIG")
    return value
}

RequireArray(value, name) {
    if Type(value) != "Array"
        throw AppError(name " must be a JSON array", "INVALID_CONFIG")
    return value
}

JsonLoad(text) {
    value := Jxon_Load(&text)
    if Type(value) != "Map"
        throw AppError("The JSON root must be an object", "INVALID_JSON")
    return value
}

JsonDump(value, indent := 2) {
    return Jxon_Dump(value, indent)
}

Utf8Encode(text, includeNull := false) {
    required := StrPut(text, "UTF-8")
    bytesBuffer := Buffer(required, 0)
    StrPut(text, bytesBuffer, "UTF-8")
    return Map("buffer", bytesBuffer, "length", includeNull ? required : required - 1)
}

Utf8Decode(buffer, length := unset) {
    return IsSet(length) ? StrGet(buffer.Ptr, length, "UTF-8") : StrGet(buffer.Ptr, "UTF-8")
}

BufferClone(source, length := unset) {
    bytes := IsSet(length) ? length : source.Size
    clone := Buffer(bytes, 0)
    if bytes
        DllCall("RtlMoveMemory", "Ptr", clone.Ptr, "Ptr", source.Ptr, "UPtr", bytes)
    return clone
}

SecureZero(buffer) {
    if Type(buffer) == "Buffer" && buffer.Size {
        Loop buffer.Size
            NumPut("UChar", 0, buffer, A_Index - 1)
    }
}

SafeErrorMessage(error) {
    if error is AppError
        return error.Code ": " error.Message
    return Type(error) ": " error.Message
}

QuoteArgument(value) {
    value := String(value)
    return '"' StrReplace(value, '"', '\"') '"'
}

GetOption(args, name, default := "") {
    for index, arg in args {
        if arg == name && index < args.Length
            return args[index + 1]
        prefix := name "="
        if SubStr(arg, 1, StrLen(prefix)) == prefix
            return SubStr(arg, StrLen(prefix) + 1)
    }
    return default
}

HasOption(args, name) {
    for arg in args
        if arg == name || SubStr(arg, 1, StrLen(name) + 1) == name "="
            return true
    return false
}

NormalizeLineEndings(text) {
    text := StrReplace(String(text), "`r`n", "`n")
    text := StrReplace(text, "`r", "`n")
    text := StrReplace(text, Chr(0x2028), "`n")
    return StrReplace(text, Chr(0x2029), "`n")
}

NormalizeCompatibilityText(text) {
    text := String(text)
    if text == ""
        return text
    required := DllCall("Normaliz\NormalizeString", "Int", 5, "Str", text, "Int", StrLen(text), "Ptr", 0, "Int", 0, "Int")
    if required <= 0
        return text
    normalized := Buffer(required * 2, 0)
    written := DllCall("Normaliz\NormalizeString", "Int", 5, "Str", text, "Int", StrLen(text), "Ptr", normalized.Ptr, "Int", required, "Int")
    return written > 0 ? StrGet(normalized, written, "UTF-16") : text
}

NormalizeKeyboardText(text) {
    text := NormalizeCompatibilityText(NormalizeLineEndings(text))
    replacements := Map(
        Chr(0x00A0), " ",
        Chr(0x2018), "'", Chr(0x2019), "'", Chr(0x201A), "'", Chr(0x201B), "'",
        Chr(0x201C), Chr(34), Chr(0x201D), Chr(34), Chr(0x201E), Chr(34), Chr(0x201F), Chr(34),
        Chr(0x2010), "-", Chr(0x2011), "-", Chr(0x2012), "-", Chr(0x2013), "-", Chr(0x2014), "-",
        Chr(0x2026), "..."
    )
    for source, replacement in replacements
        text := StrReplace(text, source, replacement)
    return RegExReplace(text, "[\x{200B}-\x{200D}\x{2060}\x{FEFF}]")
}

SplitTextLines(text) {
    text := NormalizeLineEndings(text)
    lines := []
    start := 1
    while position := InStr(text, "`n",, start) {
        lines.Push(SubStr(text, start, position - start))
        start := position + 1
    }
    lines.Push(SubStr(text, start))
    return lines
}
