class AppLogger {
    static MaxBytes := 512 * 1024
    static KeepFiles := 3

    __New(component, directory := "") {
        this.Component := component
        this.Directory := directory == "" ? EnvGet("LOCALAPPDATA") "\ShortcutKeys\logs" : directory
        this.Path := this.Directory "\" component ".log"
        try DirCreate(this.Directory)
        catch {
            this.Directory := A_Temp "\ShortcutKeys\logs"
            this.Path := this.Directory "\" component ".log"
            DirCreate(this.Directory)
        }
    }

    Info(message, fields := unset) => this.Write("INFO", message, fields?)
    Warn(message, fields := unset) => this.Write("WARN", message, fields?)
    Error(message, fields := unset) => this.Write("ERROR", message, fields?)

    Write(level, message, fields := unset) {
        try {
            this.Rotate()
            line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " this.Redact(message)
            if IsSet(fields) && fields is Map {
                for key, value in fields {
                    if RegExMatch(key, "i)password|secret|credential|text|value")
                        value := "<redacted>"
                    line .= " " key "=" this.Redact(String(value))
                }
            }
            FileAppend(line "`r`n", this.Path, "UTF-8")
        }
    }

    Redact(message) {
        message := RegExReplace(String(message), "i)(password|secret|credential|value)=\S+", "$1=<redacted>")
        return StrLen(message) > 1000 ? SubStr(message, 1, 1000) "..." : message
    }

    Rotate() {
        if !FileExist(this.Path) || FileGetSize(this.Path) < AppLogger.MaxBytes
            return
        oldest := this.Path "." AppLogger.KeepFiles
        if FileExist(oldest)
            FileDelete(oldest)
        Loop AppLogger.KeepFiles - 1 {
            index := AppLogger.KeepFiles - A_Index
            source := this.Path "." index
            if FileExist(source)
                FileMove(source, this.Path "." (index + 1), true)
        }
        FileMove(this.Path, this.Path ".1", true)
    }
}
