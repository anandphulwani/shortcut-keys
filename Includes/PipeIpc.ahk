class PipeProtocol {
    static MaxFrameBytes := 16 * 1024 * 1024

    static Encode(message) {
        text := JsonDump(message)
        encoded := Utf8Encode(text)
        frame := Buffer(4 + encoded["length"], 0)
        NumPut("UInt", encoded["length"], frame, 0)
        if encoded["length"]
            DllCall("RtlMoveMemory", "Ptr", frame.Ptr + 4, "Ptr", encoded["buffer"].Ptr, "UPtr", encoded["length"])
        return frame
    }

    static Write(file, message) {
        frame := PipeProtocol.Encode(message)
        offset := 0
        while offset < frame.Size {
            remaining := frame.Size - offset
            chunk := Buffer(remaining, 0)
            DllCall("RtlMoveMemory", "Ptr", chunk.Ptr, "Ptr", frame.Ptr + offset, "UPtr", remaining)
            written := file.RawWrite(chunk, remaining)
            if written <= 0
                throw AppError("Unable to write a complete worker message", "IPC_WRITE_FAILED")
            offset += written
        }
        ; A persistent worker does not close stdout after each response, so the
        ; frame must be committed to the pipe explicitly.
        DllCall("FlushFileBuffers", "Ptr", file.Handle)
    }

    static Read(file) {
        header := PipeProtocol.ReadExact(file, 4, "Worker message header was truncated")
        length := NumGet(header, 0, "UInt")
        PipeProtocol.ValidateLength(length)
        body := PipeProtocol.ReadExact(file, length, "Worker message body was truncated")
        return JsonLoad(Utf8Decode(body, body.Size))
    }

    static ReadExact(file, length, errorMessage) {
        output := Buffer(length, 0)
        offset := 0
        while offset < length {
            chunk := Buffer(length - offset, 0)
            count := file.RawRead(chunk, chunk.Size)
            if count <= 0
                throw AppError(errorMessage, "IPC_TRUNCATED")
            DllCall("RtlMoveMemory", "Ptr", output.Ptr + offset, "Ptr", chunk.Ptr, "UPtr", count)
            offset += count
        }
        return output
    }

    static ValidateLength(length) {
        if length == 0 || length > PipeProtocol.MaxFrameBytes
            throw AppError("Worker message length is invalid", "IPC_INVALID_LENGTH")
    }

    static ReadStandardInput() {
        stream := FileOpen("*", "r")
        if !stream
            throw AppError("Worker standard input is unavailable", "IPC_UNAVAILABLE")
        return PipeProtocol.Read(stream)
    }

    static WriteStandardOutput(message) {
        stream := FileOpen("*", "w")
        if !stream
            throw AppError("Worker standard output is unavailable", "IPC_UNAVAILABLE")
        PipeProtocol.Write(stream, message)
    }

    static ValidateJob(job, expectedType := "") {
        RequireMap(job, "worker job")
        if MapGet(job, "protocolVersion", 0) != AppInfo.ProtocolVersion
            throw AppError("Unsupported worker protocol version", "IPC_VERSION")
        if MapGet(job, "kind") != "job"
            throw AppError("Worker received an invalid message kind", "IPC_MESSAGE_KIND")
        if expectedType != "" && MapGet(job, "type") != expectedType
            throw AppError("Worker received an unexpected job type", "IPC_JOB_TYPE")
        RequireMap(MapGet(job, "payload", 0), "worker payload")
        return job
    }
}

class PipeFrameReader {
    __New(file) {
        this.File := file
        this.Pending := Buffer(0)
    }

    ReadAvailable() {
        messages := []
        available := 0
        if !DllCall("PeekNamedPipe", "Ptr", this.File.Handle, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt*", &available, "Ptr", 0) {
            errorCode := A_LastError
            if errorCode == 109 || errorCode == 233
                return Map("closed", true, "messages", messages)
            throw OSError(errorCode, -1, "PeekNamedPipe failed")
        }
        if available {
            chunk := Buffer(available, 0)
            count := this.File.RawRead(chunk, chunk.Size)
            if count > 0
                this.Append(chunk, count)
        }
        loop {
            if this.Pending.Size < 4
                break
            length := NumGet(this.Pending, 0, "UInt")
            PipeProtocol.ValidateLength(length)
            if this.Pending.Size < length + 4
                break
            body := Buffer(length, 0)
            DllCall("RtlMoveMemory", "Ptr", body.Ptr, "Ptr", this.Pending.Ptr + 4, "UPtr", length)
            messages.Push(JsonLoad(Utf8Decode(body, body.Size)))
            this.Consume(length + 4)
        }
        return Map("closed", false, "messages", messages)
    }

    Append(source, length) {
        combined := Buffer(this.Pending.Size + length, 0)
        if this.Pending.Size
            DllCall("RtlMoveMemory", "Ptr", combined.Ptr, "Ptr", this.Pending.Ptr, "UPtr", this.Pending.Size)
        DllCall("RtlMoveMemory", "Ptr", combined.Ptr + this.Pending.Size, "Ptr", source.Ptr, "UPtr", length)
        this.Pending := combined
    }

    Consume(length) {
        remaining := this.Pending.Size - length
        next := Buffer(remaining, 0)
        if remaining
            DllCall("RtlMoveMemory", "Ptr", next.Ptr, "Ptr", this.Pending.Ptr + length, "UPtr", remaining)
        this.Pending := next
    }
}

class WorkerJobObject {
    __New(logger := unset) {
        this.Logger := IsSet(logger) ? logger : ""
        this.Handle := DllCall("CreateJobObjectW", "Ptr", 0, "Ptr", 0, "Ptr")
        if !this.Handle
            throw OSError(A_LastError, -1, "CreateJobObjectW failed")
        size := A_PtrSize == 8 ? 144 : 112
        information := Buffer(size, 0)
        NumPut("UInt", 0x2000, information, 16) ; JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if !DllCall("SetInformationJobObject", "Ptr", this.Handle, "Int", 9, "Ptr", information.Ptr, "UInt", information.Size) {
            errorCode := A_LastError
            this.Close()
            throw OSError(errorCode, -1, "SetInformationJobObject failed")
        }
    }

    Assign(processHandle) {
        if DllCall("AssignProcessToJobObject", "Ptr", this.Handle, "Ptr", processHandle)
            return true
        if IsObject(this.Logger)
            this.Logger.Warn("Worker could not be assigned to the application job object", Map("win32", A_LastError))
        return false
    }

    Close() {
        if this.Handle {
            DllCall("CloseHandle", "Ptr", this.Handle)
            this.Handle := 0
        }
    }

    __Delete() => this.Close()
}

class PersistentWorkerSupervisor {
    __New(logger := unset) {
        this.Logger := IsSet(logger) ? logger : AppLogger("worker-supervisor")
        this.Pools := Map()
        this.Queues := Map()
        this.Jobs := Map()
        this.Stopping := false
        this.Polling := false
        this.PollCallback := ObjBindMethod(this, "Poll")
        this.JobObject := WorkerJobObject(this.Logger)
    }

    Register(role, executable, workerScript := "", count := 1) {
        if this.Pools.Has(role)
            throw AppError("Worker role is already registered: " role, "WORKER_ROLE_DUPLICATE")
        if !FileExist(executable)
            throw AppError("Worker executable not found: " executable, "WORKER_MISSING")
        workers := []
        Loop Max(1, count)
            workers.Push(PersistentWorker(this, role, A_Index, executable, workerScript))
        this.Pools[role] := workers
        this.Queues[role] := []
    }

    Start() {
        this.Stopping := false
        for role, workers in this.Pools {
            for worker in workers
                worker.TryLaunch()
        }
        SetTimer(this.PollCallback, 25)
    }

    Submit(role, jobType, payload, callback := unset, timeoutMs := 60000) {
        if !this.Pools.Has(role)
            throw AppError("Worker role is not registered: " role, "WORKER_ROLE_MISSING")
        jobId := ProcessExist() "-" A_TickCount "-" Random(1000, 9999)
        job := Map(
            "protocolVersion", AppInfo.ProtocolVersion,
            "kind", "job",
            "jobId", jobId,
            "type", jobType,
            "payload", payload
        )
        queued := Map(
            "job", job,
            "callback", IsSet(callback) ? callback : "",
            "timeoutMs", Max(100, timeoutMs),
            "queuedAt", A_TickCount
        )
        this.Jobs[jobId] := queued
        this.Queues[role].Push(queued)
        this.Dispatch(role)
        return jobId
    }

    Cancel(jobId) {
        if !this.Jobs.Has(jobId)
            return false
        for role, queue in this.Queues {
            for index, queued in queue {
                if queued["job"]["jobId"] == jobId {
                    queue.RemoveAt(index)
                    this.FinishQueued(queued, WorkerReply(queued["job"], false, "CANCELED", "Job was canceled before dispatch"))
                    return true
                }
            }
        }
        for role, workers in this.Pools {
            for worker in workers {
                if worker.Current is Map && worker.Current["job"]["jobId"] == jobId {
                    queued := worker.Current
                    worker.Current := ""
                    this.FinishQueued(queued, WorkerReply(queued["job"], false, "CANCELED", "Job was canceled"))
                    worker.Terminate(125)
                    return true
                }
            }
        }
        return false
    }

    Poll() {
        if this.Stopping || this.Polling
            return
        this.Polling := true
        try {
            for role, workers in this.Pools {
                for worker in workers
                    worker.Poll()
                this.Dispatch(role)
            }
        } finally {
            this.Polling := false
        }
    }

    Dispatch(role) {
        if this.Stopping || !this.Queues.Has(role) || this.Queues[role].Length == 0
            return
        for worker in this.Pools[role] {
            if this.Queues[role].Length == 0
                break
            if worker.State == "ready" && !(worker.Current is Map)
                worker.Assign(this.Queues[role].RemoveAt(1))
        }
    }

    HandleReady(worker, message) {
        if MapGet(message, "protocolVersion", 0) != AppInfo.ProtocolVersion || MapGet(message, "role") != worker.Role {
            this.Logger.Error("Worker handshake was rejected", Map("role", worker.Role, "workerId", worker.WorkerId))
            worker.Terminate(126)
            return
        }
        worker.State := "ready"
        worker.RestartCount := 0
        this.Logger.Info("Worker ready", Map("role", worker.Role, "workerId", worker.WorkerId, "pid", worker.ProcessId))
        this.Dispatch(worker.Role)
    }

    HandleResponse(worker, response) {
        if !(worker.Current is Map) {
            this.Logger.Warn("Worker returned a response without an active job", Map("role", worker.Role, "workerId", worker.WorkerId))
            return
        }
        queued := worker.Current
        if MapGet(response, "jobId") != queued["job"]["jobId"] {
            this.Logger.Warn("Worker returned a mismatched job id", Map("role", worker.Role, "workerId", worker.WorkerId))
            worker.Terminate(127)
            return
        }
        worker.Current := ""
        worker.State := "ready"
        this.FinishQueued(queued, response)
        this.Dispatch(worker.Role)
    }

    HandleWorkerExit(worker, exitCode := "") {
        if worker.Current is Map {
            queued := worker.Current
            worker.Current := ""
            this.FinishQueued(queued, WorkerReply(queued["job"], false, "WORKER_EXITED", "Worker exited before completing the job"))
        }
        worker.CleanupProcess()
        if !this.Stopping {
            worker.State := "dead"
            worker.RestartCount += 1
            worker.RestartAt := A_TickCount + Min(30000, 500 * (2 ** Min(worker.RestartCount, 6)))
            this.Logger.Warn("Worker exited and will be restarted", Map("role", worker.Role, "workerId", worker.WorkerId, "exitCode", exitCode))
        }
    }

    FinishQueued(queued, response) {
        jobId := queued["job"]["jobId"]
        if this.Jobs.Has(jobId)
            this.Jobs.Delete(jobId)
        callback := queued["callback"]
        if IsObject(callback)
            try callback.Call(response)
    }

    Status() {
        result := Map()
        for role, workers in this.Pools {
            ready := 0, busy := 0
            for worker in workers {
                if worker.State == "ready"
                    ready += 1
                else if worker.State == "busy"
                    busy += 1
            }
            result[role] := Map("ready", ready, "busy", busy, "total", workers.Length, "queued", this.Queues[role].Length)
        }
        return result
    }

    Stop() {
        if this.Stopping
            return
        this.Stopping := true
        SetTimer(this.PollCallback, 0)
        for role, workers in this.Pools {
            for worker in workers
                worker.Stop()
        }
        this.JobObject.Close()
        this.Jobs.Clear()
        for role, queue in this.Queues
            queue.Length := 0
    }

    __Delete() => this.Stop()
}

class PersistentWorker {
    __New(supervisor, role, workerId, executable, workerScript) {
        this.Supervisor := supervisor
        this.Role := role
        this.WorkerId := workerId
        this.Executable := executable
        this.WorkerScript := workerScript
        this.State := "new"
        this.Current := ""
        this.ProcessHandle := 0
        this.ProcessId := 0
        this.RequestWrite := 0
        this.ResponseRead := 0
        this.ResponseReader := ""
        this.StartedAt := 0
        this.RestartAt := 0
        this.RestartCount := 0
        this.AssignedToJob := false
    }

    TryLaunch() {
        try this.Launch()
        catch as launchError {
            this.State := "dead"
            this.RestartCount += 1
            this.RestartAt := A_TickCount + Min(30000, 500 * (2 ** Min(this.RestartCount, 6)))
            this.Supervisor.Logger.Error("Worker launch failed", Map("role", this.Role, "workerId", this.WorkerId, "error", SafeErrorMessage(launchError)))
        }
    }

    Launch() {
        requestRead := 0, requestWrite := 0, responseRead := 0, responseWrite := 0
        attributesSize := A_PtrSize == 8 ? 24 : 12
        attributes := Buffer(attributesSize, 0)
        NumPut("UInt", attributesSize, attributes, 0)
        NumPut("Int", true, attributes, A_PtrSize == 8 ? 16 : 8)
        if !DllCall("CreatePipe", "Ptr*", &requestRead, "Ptr*", &requestWrite, "Ptr", attributes.Ptr, "UInt", 0)
            throw OSError(A_LastError, -1, "CreatePipe(request) failed")
        if !DllCall("CreatePipe", "Ptr*", &responseRead, "Ptr*", &responseWrite, "Ptr", attributes.Ptr, "UInt", 0) {
            DllCall("CloseHandle", "Ptr", requestRead), DllCall("CloseHandle", "Ptr", requestWrite)
            throw OSError(A_LastError, -1, "CreatePipe(response) failed")
        }
        DllCall("SetHandleInformation", "Ptr", requestWrite, "UInt", 1, "UInt", 0)
        DllCall("SetHandleInformation", "Ptr", responseRead, "UInt", 1, "UInt", 0)
        startupSize := A_PtrSize == 8 ? 104 : 68
        startup := Buffer(startupSize, 0)
        NumPut("UInt", startupSize, startup, 0)
        flagsOffset := A_PtrSize == 8 ? 60 : 44
        stdinOffset := A_PtrSize == 8 ? 80 : 56
        NumPut("UInt", 0x100, startup, flagsOffset)
        NumPut("Ptr", requestRead, startup, stdinOffset)
        NumPut("Ptr", responseWrite, startup, stdinOffset + A_PtrSize)
        NumPut("Ptr", responseWrite, startup, stdinOffset + A_PtrSize * 2)
        processInfo := Buffer(A_PtrSize == 8 ? 24 : 16, 0)
        command := QuoteArgument(this.Executable) " /ErrorStdOut"
        if this.WorkerScript != ""
            command .= " " QuoteArgument(this.WorkerScript)
        command .= " --persistent-worker --role " this.Role " --worker-id " this.WorkerId
        commandBuffer := Buffer(StrPut(command, "UTF-16") * 2, 0)
        StrPut(command, commandBuffer, "UTF-16")
        try {
            if !DllCall("CreateProcessW"
                , "Ptr", 0, "Ptr", commandBuffer.Ptr
                , "Ptr", 0, "Ptr", 0, "Int", true
                , "UInt", 0x08000004
                , "Ptr", 0, "Str", A_ScriptDir
                , "Ptr", startup.Ptr, "Ptr", processInfo.Ptr)
                throw OSError(A_LastError, -1, "CreateProcessW failed")
            this.ProcessHandle := NumGet(processInfo, 0, "Ptr")
            threadHandle := NumGet(processInfo, A_PtrSize, "Ptr")
            this.ProcessId := NumGet(processInfo, A_PtrSize * 2, "UInt")
            this.AssignedToJob := this.Supervisor.JobObject.Assign(this.ProcessHandle)
            DllCall("CloseHandle", "Ptr", requestRead), requestRead := 0
            DllCall("CloseHandle", "Ptr", responseWrite), responseWrite := 0
            this.RequestWrite := FileOpen(requestWrite, "h"), requestWrite := 0
            this.ResponseRead := FileOpen(responseRead, "h"), responseRead := 0
            this.ResponseReader := PipeFrameReader(this.ResponseRead)
            this.State := "starting"
            this.StartedAt := A_TickCount
            DllCall("ResumeThread", "Ptr", threadHandle)
            DllCall("CloseHandle", "Ptr", threadHandle)
        } catch {
            if IsSet(threadHandle) && threadHandle
                DllCall("CloseHandle", "Ptr", threadHandle)
            this.CleanupProcess()
            throw
        } finally {
            for handle in [requestRead, requestWrite, responseRead, responseWrite]
                if handle
                    DllCall("CloseHandle", "Ptr", handle)
        }
    }

    Assign(queued) {
        this.Current := queued
        this.State := "busy"
        queued["startedAt"] := A_TickCount
        try PipeProtocol.Write(this.RequestWrite, queued["job"])
        catch as writeError {
            this.Supervisor.Logger.Error("Worker request write failed", Map("role", this.Role, "workerId", this.WorkerId, "error", SafeErrorMessage(writeError)))
            failedJob := this.Current
            this.Current := ""
            this.Supervisor.FinishQueued(failedJob, WorkerReply(failedJob["job"], false, "IPC_WRITE_FAILED", "Worker request could not be written"))
            this.Terminate(128)
        }
    }

    Poll() {
        if this.State == "dead" {
            if !this.Supervisor.Stopping && A_TickCount >= this.RestartAt
                this.TryLaunch()
            return
        }
        if !this.ProcessHandle
            return
        waitResult := DllCall("WaitForSingleObject", "Ptr", this.ProcessHandle, "UInt", 0, "UInt")
        if waitResult == 0 {
            exitCode := 0
            DllCall("GetExitCodeProcess", "Ptr", this.ProcessHandle, "UInt*", &exitCode)
            this.Supervisor.HandleWorkerExit(this, exitCode)
            return
        }
        try readResult := this.ResponseReader.ReadAvailable()
        catch as channelError {
            this.Supervisor.Logger.Error("Worker response channel failed", Map("role", this.Role, "workerId", this.WorkerId, "error", SafeErrorMessage(channelError)))
            this.Terminate(129)
            return
        }
        for message in readResult["messages"] {
            kind := MapGet(message, "kind")
            if kind == "ready"
                this.Supervisor.HandleReady(this, message)
            else if kind == "response"
                this.Supervisor.HandleResponse(this, message)
            else
                this.Supervisor.Logger.Warn("Worker sent an unknown message kind", Map("role", this.Role, "workerId", this.WorkerId))
        }
        if readResult["closed"] {
            this.Terminate(130)
            return
        }
        if this.State == "starting" && A_TickCount - this.StartedAt > 10000 {
            this.Supervisor.Logger.Error("Worker startup handshake timed out", Map("role", this.Role, "workerId", this.WorkerId))
            this.Terminate(124)
            return
        }
        if this.Current is Map && A_TickCount - this.Current["startedAt"] > this.Current["timeoutMs"] {
            queued := this.Current
            this.Current := ""
            this.Supervisor.FinishQueued(queued, WorkerReply(queued["job"], false, "WORKER_TIMEOUT", "Worker timed out"))
            this.Terminate(124)
        }
    }

    Terminate(exitCode := 1) {
        if this.ProcessHandle
            DllCall("TerminateProcess", "Ptr", this.ProcessHandle, "UInt", exitCode)
        this.Supervisor.HandleWorkerExit(this, exitCode)
    }

    Stop() {
        if this.State == "ready" && this.RequestWrite {
            try PipeProtocol.Write(this.RequestWrite, Map("protocolVersion", AppInfo.ProtocolVersion, "kind", "shutdown"))
        }
        if this.ProcessHandle
            DllCall("TerminateProcess", "Ptr", this.ProcessHandle, "UInt", 0)
        this.CleanupProcess()
        this.State := "stopped"
    }

    CleanupProcess() {
        if this.RequestWrite {
            try this.RequestWrite.Close()
            this.RequestWrite := 0
        }
        if this.ResponseRead {
            try this.ResponseRead.Close()
            this.ResponseRead := 0
        }
        this.ResponseReader := ""
        if this.ProcessHandle {
            DllCall("CloseHandle", "Ptr", this.ProcessHandle)
            this.ProcessHandle := 0
        }
        this.ProcessId := 0
        this.AssignedToJob := false
    }
}

class PersistentWorkerHost {
    __New(role, handler, logger := unset) {
        this.Role := role
        this.Handler := handler
        this.Logger := IsSet(logger) ? logger : AppLogger(role "-worker")
    }

    Run() {
        input := FileOpen("*", "r")
        output := FileOpen("*", "w")
        if !input || !output
            ExitApp(65)
        PipeProtocol.Write(output, Map(
            "protocolVersion", AppInfo.ProtocolVersion,
            "kind", "ready",
            "role", this.Role,
            "pid", ProcessExist(),
            "workerId", GetOption(A_Args, "--worker-id")
        ))
        loop {
            try message := PipeProtocol.Read(input)
            catch
                break
            if MapGet(message, "kind") == "shutdown"
                break
            try {
                PipeProtocol.ValidateJob(message)
                response := this.Handler.Call(message)
                if !(response is Map)
                    response := WorkerReply(message, true)
            } catch as jobError {
                this.Logger.Error("Worker job failed", Map("role", this.Role, "code", jobError is AppError ? jobError.Code : Type(jobError), "message", SafeErrorMessage(jobError)))
                response := WorkerReply(message, false, jobError is AppError ? jobError.Code : "UNEXPECTED", SafeErrorMessage(jobError))
            }
            try PipeProtocol.Write(output, response)
            catch
                break
        }
    }
}

WorkerReply(job, ok, code := "OK", message := "") {
    return Map(
        "protocolVersion", AppInfo.ProtocolVersion,
        "kind", "response",
        "jobId", MapGet(job, "jobId"),
        "ok", ok ? 1 : 0,
        "code", code,
        "message", message
    )
}
