#Requires AutoHotkey v2.0.30
#SingleInstance Off
#NoTrayIcon
#Warn All, OutputDebug

#Include Includes\Jxon.ahk
#Include Includes\App.ahk
#Include Includes\Logger.ahk
#Include Includes\PipeIpc.ahk
#Include Includes\BrowserBridgePipe.ahk

class BrowserBridgeWorker {
    __New() {
        this.Logger := AppLogger("browser-worker")
        this.Server := ""
        this.Pending := ""
        this.Input := ""
        this.Output := ""
        this.Snapshot := Map("version", 1, "generation", "locked", "rules", [])
    }

    Run() {
        this.Server := BrowserPipeServer()
        this.Input := FileOpen("*", "r")
        this.Output := FileOpen("*", "w")
        if !this.Input || !this.Output
            ExitApp(65)
        reader := PipeFrameReader(this.Input)
        PipeProtocol.Write(this.Output, Map("protocolVersion", AppInfo.ProtocolVersion, "kind", "ready", "role", "browser", "pid", ProcessExist(), "workerId", GetOption(A_Args, "--worker-id")))
        try loop {
            parent := reader.ReadAvailable()
            if parent["closed"]
                break
            for message in parent["messages"] {
                if MapGet(message, "kind") == "shutdown"
                    return
                if MapGet(message, "kind") == "control" {
                    this.HandleControl(message)
                    continue
                }
                this.HandleParent(message)
            }
            result := this.Server.Poll()
            for incoming in result["messages"]
                this.HandleExtension(incoming["client"], incoming["message"])
            this.CheckPending()
            Sleep(10)
        } finally {
            this.Server.Close()
        }
    }

    HandleParent(job) {
        try {
            PipeProtocol.ValidateJob(job, "browser")
            payload := job["payload"]
            action := String(MapGet(payload, "action", "status"))
            if action == "cacheSnapshot" {
                this.ApplySnapshot(MapGet(payload, "snapshot", 0))
                this.Reply(WorkerReply(job, true, "CACHE_READY"))
                return
            }
            if this.Pending is Map
                throw AppError("The browser worker is busy", "BROWSER_BUSY")
            if action == "status" {
                this.Reply(WorkerReply(job, true, "READY", "Browser bridge ready; " this.Server.Clients.Count " extension connection(s)"))
                return
            }
            if action == "listSessions" {
                waiting := Map()
                for clientId in this.Server.Clients.Clone() {
                    waiting[clientId] := true
                    try this.Server.Send(clientId, Map("kind", "list", "requestId", job["jobId"]))
                    catch
                        waiting.Delete(clientId)
                }
                this.Pending := Map("job", job, "action", action, "waiting", waiting, "deadline", A_TickCount + 2000)
                this.CheckPending()
                return
            }
            if action == "sendBatch" {
                sessionId := String(MapGet(payload, "sessionId"))
                separator := InStr(sessionId, ":")
                if !separator
                    throw AppError("The selected browser session is invalid", "BROWSER_SESSION_INVALID")
                clientId := SubStr(sessionId, 1, separator - 1)
                if !this.Server.Clients.Has(clientId)
                    throw AppError("The selected browser extension disconnected", "BROWSER_DISCONNECTED")
                tabId := Integer(SubStr(sessionId, separator + 1))
                known := false
                for session in this.Server.Clients[clientId]["sessions"] {
                    if Integer(MapGet(session, "tabId", -1)) == tabId && MapGet(session, "url") == MapGet(payload, "expectedUrl") {
                        known := true
                        break
                    }
                }
                if !known
                    throw AppError("The selected noVNC session changed or disconnected", "BROWSER_SESSION_CHANGED")
                text := String(MapGet(payload, "text"))
                if StrLen(text) > 64
                    throw AppError("Browser batches must contain at most 64 UTF-16 units", "BROWSER_BATCH_TOO_LONG")
                delayMs := Max(0, Min(1000, Integer(MapGet(payload, "delayMs", 0))))
                this.Server.Send(clientId, Map("kind", "send", "requestId", job["jobId"], "tabId", tabId, "expectedUrl", MapGet(payload, "expectedUrl"), "text", text, "delayMs", delayMs))
                this.Pending := Map("job", job, "action", action, "clientId", clientId, "deadline", A_TickCount + Max(5000, 64 * delayMs + 5000))
                return
            }
            throw AppError("The browser action is invalid", "BROWSER_ACTION_INVALID")
        } catch as caughtError {
            this.Reply(WorkerReply(job, false, caughtError is AppError ? caughtError.Code : "UNEXPECTED", SafeErrorMessage(caughtError)))
        }
    }

    HandleControl(message) {
        if MapGet(message, "protocolVersion", 0) != AppInfo.ProtocolVersion || MapGet(message, "action") != "cacheSnapshot"
            return
        try this.ApplySnapshot(MapGet(MapGet(message, "payload", Map()), "snapshot", 0))
        catch as caughtError
            this.Logger.Warn("Browser cache control was rejected", Map("code", caughtError is AppError ? caughtError.Code : Type(caughtError)))
    }

    ApplySnapshot(value) {
        snapshot := RequireMap(value, "browser cache snapshot")
        if MapGet(snapshot, "version", 0) != 1 || !(MapGet(snapshot, "rules", 0) is Array)
            throw AppError("Browser cache snapshot is invalid", "BROWSER_CACHE_INVALID")
        this.Snapshot := snapshot
        for clientId in this.Server.Clients.Clone()
            try this.SendSnapshot(this.Server.Clients[clientId])
    }

    HandleExtension(client, message) {
        if !(message is Map)
            return
        kind := String(MapGet(message, "kind"))
        if kind == "hello" {
            client["browser"] := String(MapGet(message, "browser", "Browser"))
            this.UpdateApprovedOrigins(client, MapGet(message, "approvedOrigins", []), MapGet(message, "allowAllSites", false))
            this.SendSnapshot(client)
            return
        }
        if kind == "permissions" {
            this.UpdateApprovedOrigins(client, MapGet(message, "approvedOrigins", []), MapGet(message, "allowAllSites", false))
            this.SendSnapshot(client)
            return
        }
        if !(this.Pending is Map) || MapGet(message, "requestId") != this.Pending["job"]["jobId"]
            return
        if this.Pending["action"] == "listSessions" && kind == "sessions" {
            sessions := MapGet(message, "sessions", [])
            if sessions is Array {
                client["sessions"] := []
                for session in sessions {
                    if !(session is Map)
                        continue
                    tabId := Integer(MapGet(session, "tabId", -1))
                    url := String(MapGet(session, "url"))
                    if tabId < 0 || !RegExMatch(url, "i)^https?://")
                        continue
                    client["sessions"].Push(Map("tabId", tabId, "url", url, "label", String(MapGet(session, "label", "noVNC console"))))
                }
            }
            if this.Pending["waiting"].Has(client["id"])
                this.Pending["waiting"].Delete(client["id"])
            this.CheckPending()
            return
        }
        if this.Pending["action"] == "sendBatch" && kind == "sent" && client["id"] == this.Pending["clientId"] {
            job := this.Pending["job"]
            this.Pending := ""
            if MapGet(message, "ok", false)
                this.Reply(WorkerReply(job, true, "ACCEPTED", "noVNC accepted the key events"))
            else
                this.Reply(WorkerReply(job, false, String(MapGet(message, "code", "BROWSER_SEND_FAILED")), "The selected noVNC console did not accept the key events"))
        }
    }

    UpdateApprovedOrigins(client, origins, allowAllSites := false) {
        approved := Map()
        if origins is Array {
            for origin in origins {
                value := String(origin)
                if RegExMatch(value, "i)^https?://[a-z0-9.-]+(?::\d+)?$")
                    approved[value] := true
            }
        }
        client["approvedOrigins"] := approved
        client["allowAllSites"] := !!allowAllSites
    }

    SendSnapshot(client) {
        approved := MapGet(client, "approvedOrigins", Map())
        filtered := []
        for rule in this.Snapshot["rules"] {
            match := rule["match"]
            browser := StrLower(String(MapGet(match, "browser", "")))
            if browser != "" && browser != StrLower(String(MapGet(client, "browser", "")))
                continue
            if !MapGet(client, "allowAllSites", false) && !approved.Has(String(MapGet(match, "origin")))
                continue
            if match.Has("frameOrigin") && !MapGet(client, "allowAllSites", false) && !approved.Has(String(match["frameOrigin"]))
                continue
            filtered.Push(rule)
        }
        this.Server.Send(client["id"], Map("kind", "cacheSnapshot", "snapshot", Map(
            "version", 1, "generation", this.Snapshot["generation"], "rules", filtered)))
    }

    CheckPending() {
        if !(this.Pending is Map)
            return
        pending := this.Pending
        if pending["action"] == "listSessions" && (pending["waiting"].Count == 0 || A_TickCount >= pending["deadline"]) {
            sessions := []
            for clientId, client in this.Server.Clients {
                for session in client["sessions"]
                    sessions.Push(Map("sessionId", clientId ":" session["tabId"], "url", session["url"], "label", MapGet(client, "browser", "Browser") " - " session["label"] " (tab " session["tabId"] ")"))
            }
            response := WorkerReply(pending["job"], true)
            response["sessions"] := sessions
            this.Pending := ""
            this.Reply(response)
        } else if pending["action"] == "sendBatch" && (!this.Server.Clients.Has(pending["clientId"]) || A_TickCount >= pending["deadline"]) {
            this.Pending := ""
            this.Reply(WorkerReply(pending["job"], false, "BROWSER_TIMEOUT", "Browser extension disconnected or timed out"))
        }
    }

    Reply(response) {
        PipeProtocol.Write(this.Output, response)
    }
}

class BrowserNativeHost {
    Run() {
        input := FileOpen("*", "r")
        output := FileOpen("*", "w")
        if !input || !output
            ExitApp(65)
        pipe := BrowserPipeClient.Connect()
        inputReader := PipeFrameReader(input)
        pipeReader := PipeFrameReader(pipe)
        try loop {
            browser := inputReader.ReadAvailable()
            if browser["closed"]
                break
            for message in browser["messages"]
                PipeProtocol.Write(pipe, message)
            worker := pipeReader.ReadAvailable()
            if worker["closed"]
                break
            for message in worker["messages"]
                PipeProtocol.Write(output, message)
            Sleep(10)
        } finally {
            pipe.Close()
        }
    }
}

try {
    if HasOption(A_Args, "--persistent-worker")
        BrowserBridgeWorker().Run()
    else
        BrowserNativeHost().Run()
} catch {
    ; The browser may start its native host before the controller. Never show
    ; an AutoHotkey error dialog or write protocol-invalid text to stdout.
    ExitApp(65)
}
ExitApp(0)
