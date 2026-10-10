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
