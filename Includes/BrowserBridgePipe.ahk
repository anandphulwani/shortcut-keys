class BrowserBridgeEndpoint {
    static HostName := "com.shortcutkeys.bridge"

    static SessionId() {
        sessionId := 0
        if !DllCall("ProcessIdToSessionId", "UInt", ProcessExist(), "UInt*", &sessionId)
            throw OSError(A_LastError, -1, "ProcessIdToSessionId failed")
        return sessionId
    }

    static Path() {
        directory := EnvGet("SHORTCUT_KEYS_BRIDGE_DIR")
        if directory == ""
            directory := EnvGet("LOCALAPPDATA") "\ShortcutKeys"
        DirCreate(directory)
        return directory "\browser-bridge-" BrowserBridgeEndpoint.SessionId() ".json"
    }

    static RandomName() {
        bytes := Buffer(16, 0)
        status := DllCall("bcrypt\BCryptGenRandom", "Ptr", 0, "Ptr", bytes.Ptr, "UInt", bytes.Size, "UInt", 2, "UInt")
        if status
            throw AppError("Unable to create a browser bridge identifier", "BROWSER_BRIDGE_RANDOM")
        identifier := ""
        Loop bytes.Size
            identifier .= Format("{:02x}", NumGet(bytes, A_Index - 1, "UChar"))
        return "\\.\pipe\ShortcutKeys-" BrowserBridgeEndpoint.SessionId() "-" identifier
    }

    static Publish(pipeName) {
        path := BrowserBridgeEndpoint.Path()
        temporary := path "." ProcessExist() ".tmp"
        value := JsonDump(Map("protocolVersion", AppInfo.ProtocolVersion, "pipe", pipeName, "pid", ProcessExist()))
        FileAppend(value, temporary, "UTF-8")
        FileMove(temporary, path, 1)
    }

    static Read() {
        path := BrowserBridgeEndpoint.Path()
        if !FileExist(path)
            throw AppError("The ShortcutKeys browser worker is not running", "BROWSER_BRIDGE_UNAVAILABLE")
        endpoint := JsonLoad(FileRead(path, "UTF-8"))
        if MapGet(endpoint, "protocolVersion") != AppInfo.ProtocolVersion
            throw AppError("The browser bridge protocol is incompatible", "BROWSER_BRIDGE_VERSION")
        pipeName := String(MapGet(endpoint, "pipe"))
        if !RegExMatch(pipeName, "^\\\\\.\\pipe\\ShortcutKeys-[0-9]+-[0-9a-f]{32}$")
            throw AppError("The browser bridge endpoint is invalid", "BROWSER_BRIDGE_UNAVAILABLE")
        return endpoint
    }
}

class BrowserPipeServer {
    __New() {
        this.Name := BrowserBridgeEndpoint.RandomName()
        this.Clients := Map()
        this.NextId := 1
        this.Listener := 0
        this.SecurityDescriptor := 0
        this.CreateSecurity()
        this.Listen()
        BrowserBridgeEndpoint.Publish(this.Name)
    }

    CreateSecurity() {
        ; Only the process owner, Administrators and SYSTEM can connect.
        descriptor := 0
        if !DllCall("advapi32\ConvertStringSecurityDescriptorToSecurityDescriptorW"
            , "Str", "D:P(A;;GA;;;OW)(A;;GA;;;BA)(A;;GA;;;SY)"
            , "UInt", 1, "Ptr*", &descriptor, "Ptr", 0)
            throw OSError(A_LastError, -1, "Browser pipe security descriptor failed")
        this.SecurityDescriptor := descriptor
    }

    Listen() {
        attributes := Buffer(A_PtrSize == 8 ? 24 : 12, 0)
        NumPut("UInt", attributes.Size, attributes, 0)
        NumPut("Ptr", this.SecurityDescriptor, attributes, A_PtrSize == 8 ? 8 : 4)
        NumPut("Int", 0, attributes, A_PtrSize == 8 ? 16 : 8)
        ; PIPE_NOWAIT keeps this worker's event loop responsive.
        handle := DllCall("CreateNamedPipeW", "Str", this.Name, "UInt", 3
            , "UInt", 0x9, "UInt", 255, "UInt", 65536, "UInt", 65536
            , "UInt", 0, "Ptr", attributes.Ptr, "Ptr")
        if handle == -1 || !handle
            throw OSError(A_LastError, -1, "CreateNamedPipeW failed")
        this.Listener := handle
    }

    Poll() {
        accepted := []
        if this.Listener {
            connected := DllCall("ConnectNamedPipe", "Ptr", this.Listener, "Ptr", 0, "Int")
            if connected || A_LastError == 535 {
                clientId := RegExReplace(this.Name, "^.*-", "") "-" this.NextId++
                pipeFile := FileOpen(this.Listener, "h")
                this.Clients[clientId] := Map("id", clientId, "file", pipeFile, "reader", PipeFrameReader(pipeFile), "sessions", [])
                accepted.Push(this.Clients[clientId])
                this.Listener := 0
                this.Listen()
            } else if A_LastError != 536
                throw OSError(A_LastError, -1, "ConnectNamedPipe failed")
        }
        messages := []
        for clientId, client in this.Clients.Clone() {
            try result := client["reader"].ReadAvailable()
            catch {
                this.Drop(clientId)
                continue
            }
            for message in result["messages"]
                messages.Push(Map("client", client, "message", message))
            if result["closed"]
                this.Drop(clientId)
        }
        return Map("accepted", accepted, "messages", messages)
    }

    Send(clientId, message) {
        if !this.Clients.Has(clientId)
            throw AppError("The browser extension disconnected", "BROWSER_DISCONNECTED")
        try PipeProtocol.Write(this.Clients[clientId]["file"], message)
        catch {
            this.Drop(clientId)
            throw AppError("The browser extension disconnected", "BROWSER_DISCONNECTED")
        }
    }

    Drop(clientId) {
        if !this.Clients.Has(clientId)
            return
        client := this.Clients.Delete(clientId)
        try client["file"].Close()
    }

    Close() {
        for clientId in this.Clients.Clone()
            this.Drop(clientId)
        if this.Listener {
            DllCall("CloseHandle", "Ptr", this.Listener)
            this.Listener := 0
        }
        if this.SecurityDescriptor {
            DllCall("LocalFree", "Ptr", this.SecurityDescriptor)
            this.SecurityDescriptor := 0
        }
        path := BrowserBridgeEndpoint.Path()
        try {
            if FileExist(path) && MapGet(JsonLoad(FileRead(path, "UTF-8")), "pipe") == this.Name
                FileDelete(path)
        }
    }

    __Delete() => this.Close()
}

class BrowserPipeClient {
    static Connect(timeoutMs := 1500) {
        endpoint := BrowserBridgeEndpoint.Read()
        started := A_TickCount
        loop {
            handle := DllCall("CreateFileW", "Str", endpoint["pipe"], "UInt", 0xC0000000
                , "UInt", 0, "Ptr", 0, "UInt", 3, "UInt", 0, "Ptr", 0, "Ptr")
            if handle != -1 && handle
                return FileOpen(handle, "h")
            if A_TickCount - started >= timeoutMs
                throw AppError("Could not connect to the ShortcutKeys browser worker", "BROWSER_BRIDGE_UNAVAILABLE")
            Sleep(50)
        }
    }
}
