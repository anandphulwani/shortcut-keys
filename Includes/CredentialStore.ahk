class CredentialStore {
    __New(path := "", logger := unset, registryEnabled := true) {
        this.Path := path == "" ? AppInfo.CredentialPath : path
        this.Logger := IsSet(logger) ? logger : AppLogger("credentials")
        this.RegistryEnabled := registryEnabled
        this.Password := ""
        this.Config := ""
        this.LastBackupPath := ""
    }

    Unlock(interactive := true) {
        if !FileExist(this.Path)
            throw AppError("Credential file not found: " this.Path, "CREDENTIAL_FILE_MISSING")
        candidates := []
        if this.RegistryEnabled {
            if cached := this.ReadDpapiCache()
                candidates.Push(Map("password", cached, "source", "dpapi"))
            if legacyCached := this.ReadLegacyRegistryCache()
                candidates.Push(Map("password", legacyCached, "source", "legacy-registry"))
        }
        for candidate in candidates {
            try {
                result := this.TryUnlock(candidate["password"])
                this.Password := candidate["password"]
                this.Config := result["config"]
                if candidate["source"] == "legacy-registry" {
                    this.WriteDpapiCache(this.Password)
                    this.RemoveLegacyRegistryValue()
                }
                this.FinalizeMigration(result)
                return this.Config
            } catch as caughtError {
                this.Logger.Warn("Cached credential key did not unlock the credential file", Map("source", candidate["source"], "code", caughtError is AppError ? caughtError.Code : Type(caughtError)))
            }
        }
        if !interactive
            throw AppError("No cached credential key could unlock the file", "UNLOCK_REQUIRED")

        response := InputBox("Enter the master password for credentials.json.enc.", "Unlock ShortcutKeys", "Password w420 h150")
        if response.Result != "OK"
            throw AppError("Credential unlock was canceled", "UNLOCK_CANCELED")
        result := this.TryUnlock(response.Value)
        this.Password := response.Value
        this.Config := result["config"]
        if this.RegistryEnabled
            this.WriteDpapiCache(this.Password)
        this.FinalizeMigration(result)
        return this.Config
    }

    TryUnlock(password) {
        raw := FileRead(this.Path, "UTF-8")
        trimmed := LTrim(raw, " `t`r`n")
        legacyEnvelope := SubStr(trimmed, 1, 1) != "{"
        if legacyEnvelope {
            plaintext := LegacyCrypto.DecryptHex(trimmed, password)
        } else {
            envelope := JsonLoad(trimmed)
            if !envelope.Has("formatVersion") && (envelope.Has("schemaVersion") || envelope.Has("passwords"))
                throw AppError("Plaintext credential JSON cannot be used as credentials.json.enc. Use Import and Encrypt JSON.", "PLAINTEXT_CREDENTIAL_FILE")
            plaintext := CngCrypto.DecryptEnvelope(envelope, password)
        }
        try config := JsonLoad(plaintext)
        catch
            throw AppError("The password is incorrect or the credential JSON is invalid", "DECRYPT_FAILED")
        normalized := CredentialConfig.Normalize(config)
        return Map(
            "config", normalized["config"],
            "legacyEnvelope", legacyEnvelope,
            "schemaMigrated", normalized["migrated"]
        )
    }

    FinalizeMigration(result) {
        if !result["legacyEnvelope"] && !result["schemaMigrated"]
            return
        if result["legacyEnvelope"] {
            backup := this.Path ".legacy.bak"
            if !FileExist(backup)
                FileCopy(this.Path, backup)
        }
        this.SaveConfig(result["config"], this.Password)
        this.Logger.Info("Credential file migrated", Map("legacyEnvelope", result["legacyEnvelope"], "schemaMigrated", result["schemaMigrated"]))
        if this.RegistryEnabled
            this.RemoveLegacyRegistryValue()
    }

    SaveConfig(config, password := "") {
        if password == ""
            password := this.Password
        if password == ""
            throw AppError("A master password is required", "UNLOCK_REQUIRED")
        CredentialConfig.Validate(config)
        plaintext := JsonDump(config, 2)
        envelope := CngCrypto.EncryptText(plaintext, password)
        serialized := JsonDump(envelope, 2)
        this.AtomicWrite(serialized, password)
        this.Config := config
    }

    AtomicWrite(serializedEnvelope, password) {
        tempPath := this.Path "." ProcessExist() ".tmp"
        try {
            outputStream := FileOpen(tempPath, "w", "UTF-8-RAW")
            if !outputStream
                throw AppError("Unable to open temporary credential file", "WRITE_FAILED")
            outputStream.Write(serializedEnvelope), outputStream.Close()
            verificationText := FileRead(tempPath, "UTF-8")
            verificationEnvelope := JsonLoad(verificationText)
            verificationPlaintext := CngCrypto.DecryptEnvelope(verificationEnvelope, password)
            JsonLoad(verificationPlaintext)
            FileMove(tempPath, this.Path, true)
        } catch as caughtError {
            if FileExist(tempPath)
                try FileDelete(tempPath)
            throw AppError("Credential update failed; the original file was preserved. " SafeErrorMessage(caughtError), "WRITE_FAILED")
        }
    }

    ImportJson(sourcePath, password := "", backupExisting := false) {
        config := JsonLoad(FileRead(sourcePath, "UTF-8"))
        normalized := CredentialConfig.Normalize(config)
        CredentialConfig.Validate(normalized["config"])
        effectivePassword := password != "" ? password : this.Password
        if effectivePassword == ""
            throw AppError("A new master password is required to encrypt the imported JSON", "UNLOCK_REQUIRED")
        this.LastBackupPath := backupExisting ? this.BackupExistingFile() : ""
        this.SaveConfig(normalized["config"], effectivePassword)
        this.Password := effectivePassword
        if this.RegistryEnabled
            this.WriteDpapiCache(effectivePassword)
        return normalized["config"]
    }

    BackupExistingFile() {
        if !FileExist(this.Path)
            return ""
        timestamp := FormatTime(, "yyyyMMdd-HHmmss")
        backupPath := this.Path ".before-import-" timestamp "-" ProcessExist() ".bak"
        FileCopy(this.Path, backupPath)
        return backupPath
    }

    ExportJson(destinationPath) {
        if !(this.Config is Map)
            throw AppError("Credentials are locked", "UNLOCK_REQUIRED")
        if FileExist(destinationPath)
            throw AppError("The export destination already exists", "EXPORT_EXISTS")
        FileAppend(JsonDump(this.Config, 2), destinationPath, "UTF-8-RAW")
    }

    ReadDpapiCache() {
        try return Dpapi.Unprotect(RegRead(AppInfo.RegistryPath, AppInfo.RegistryValue))
        catch
            return ""
    }

    WriteDpapiCache(password) {
        try RegWrite(Dpapi.Protect(password), "REG_SZ", AppInfo.RegistryPath, AppInfo.RegistryValue)
        catch as caughtError
            this.Logger.Warn("Unable to store the DPAPI-protected unlock key", Map("error", SafeErrorMessage(caughtError)))
    }

    ReadLegacyRegistryCache() {
        for view in (A_Is64bitOS ? [64, 32] : [32]) {
            try {
                SetRegView(view)
                encrypted := RegRead(AppInfo.LegacyRegistryPath, AppInfo.LegacyRegistryValue)
                decrypted := LegacyCrypto.DecryptHex(encrypted, AppInfo.LegacyRegistryPassword)
                if decrypted != ""
                    return decrypted
            } catch {
            } finally {
                SetRegView("Default")
            }
        }
        return ""
    }

    RemoveLegacyRegistryValue() {
        for view in (A_Is64bitOS ? [64, 32] : [32]) {
            found := false
            try {
                SetRegView(view)
                RegRead(AppInfo.LegacyRegistryPath, AppInfo.LegacyRegistryValue)
                found := true
                RegDelete(AppInfo.LegacyRegistryPath, AppInfo.LegacyRegistryValue)
            } catch as caughtError {
                if found
                    this.Logger.Warn("The legacy HKLM unlock value could not be removed", Map("registryView", view, "error", SafeErrorMessage(caughtError)))
            } finally {
                SetRegView("Default")
            }
        }
    }

    ClearMemory() {
        this.Password := ""
        this.Config := ""
    }
}
