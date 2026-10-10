class BinaryCodec {
    static ToBase64(dataBuffer, length := unset) {
        bytes := IsSet(length) ? length : dataBuffer.Size
        chars := 0
        flags := 0x40000001 ; CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF
        if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", dataBuffer.Ptr, "UInt", bytes, "UInt", flags, "Ptr", 0, "UInt*", &chars)
            throw OSError(A_LastError, -1, "CryptBinaryToStringW sizing failed")
        output := Buffer(chars * 2, 0)
        if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", dataBuffer.Ptr, "UInt", bytes, "UInt", flags, "Ptr", output.Ptr, "UInt*", &chars)
            throw OSError(A_LastError, -1, "CryptBinaryToStringW failed")
        return StrGet(output, "UTF-16")
    }

    static FromBase64(text) {
        bytes := 0
        if !DllCall("Crypt32\CryptStringToBinaryW", "Str", text, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &bytes, "Ptr", 0, "Ptr", 0)
            throw AppError("Invalid base64 data", "INVALID_ENVELOPE")
        output := Buffer(bytes, 0)
        if !DllCall("Crypt32\CryptStringToBinaryW", "Str", text, "UInt", 0, "UInt", 1, "Ptr", output.Ptr, "UInt*", &bytes, "Ptr", 0, "Ptr", 0)
            throw AppError("Invalid base64 data", "INVALID_ENVELOPE")
        return output
    }

    static FromHex(text) {
        text := Trim(text)
        if Mod(StrLen(text), 2) || !RegExMatch(text, "i)^[0-9a-f]+$")
            throw AppError("Legacy ciphertext is not valid hexadecimal data", "INVALID_LEGACY_DATA")
        output := Buffer(StrLen(text) // 2, 0)
        Loop output.Size
            NumPut("UChar", Integer("0x" SubStr(text, A_Index * 2 - 1, 2)), output, A_Index - 1)
        return output
    }
}

class CngCrypto {
    static Iterations := 600000

    static RandomBytes(length) {
        output := Buffer(length, 0)
        status := DllCall("Bcrypt\BCryptGenRandom", "Ptr", 0, "Ptr", output.Ptr, "UInt", output.Size, "UInt", 0x2, "UInt")
        CngCrypto.Check(status, "BCryptGenRandom")
        return output
    }

    static DeriveKey(password, salt, iterations := 600000) {
        algorithm := 0
        passwordBytes := Utf8Encode(password)
        key := Buffer(32, 0)
        try {
            status := DllCall("Bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &algorithm, "WStr", "SHA256", "Ptr", 0, "UInt", 0x8, "UInt")
            CngCrypto.Check(status, "BCryptOpenAlgorithmProvider(SHA256-HMAC)")
            status := DllCall("Bcrypt\BCryptDeriveKeyPBKDF2"
                , "Ptr", algorithm
                , "Ptr", passwordBytes["buffer"].Ptr, "UInt", passwordBytes["length"]
                , "Ptr", salt.Ptr, "UInt", salt.Size
                , "UInt64", iterations
                , "Ptr", key.Ptr, "UInt", key.Size
                , "UInt", 0, "UInt")
            CngCrypto.Check(status, "BCryptDeriveKeyPBKDF2")
            return key
        } finally {
            SecureZero(passwordBytes["buffer"])
            if algorithm
                DllCall("Bcrypt\BCryptCloseAlgorithmProvider", "Ptr", algorithm, "UInt", 0)
        }
    }

    static EncryptText(plaintext, password) {
        salt := CngCrypto.RandomBytes(16)
        nonce := CngCrypto.RandomBytes(12)
        key := CngCrypto.DeriveKey(password, salt, CngCrypto.Iterations)
        plainBytes := Utf8Encode(plaintext)
        try {
            encrypted := CngCrypto.AesGcm(true, plainBytes["buffer"], plainBytes["length"], key, nonce)
            return Map(
                "formatVersion", 2,
                "kdf", Map("name", "PBKDF2-HMAC-SHA256", "iterations", CngCrypto.Iterations, "salt", BinaryCodec.ToBase64(salt)),
                "cipher", Map("name", "AES-256-GCM", "nonce", BinaryCodec.ToBase64(nonce), "tag", BinaryCodec.ToBase64(encrypted["tag"])),
                "ciphertext", BinaryCodec.ToBase64(encrypted["data"])
            )
        } finally {
            SecureZero(key)
            SecureZero(plainBytes["buffer"])
        }
    }

    static DecryptEnvelope(envelope, password) {
        try {
            if MapGet(envelope, "formatVersion", 0) != 2
                throw AppError("Unsupported credential envelope version", "UNSUPPORTED_ENVELOPE")
            kdf := RequireMap(envelope["kdf"], "kdf")
            cipher := RequireMap(envelope["cipher"], "cipher")
            if MapGet(kdf, "name") != "PBKDF2-HMAC-SHA256" || MapGet(cipher, "name") != "AES-256-GCM"
                throw AppError("Unsupported credential encryption algorithms", "UNSUPPORTED_ENVELOPE")
            iterations := Integer(kdf["iterations"])
            if iterations < 100000 || iterations > 10000000
                throw AppError("Credential KDF iteration count is outside the accepted range", "INVALID_ENVELOPE")
            salt := BinaryCodec.FromBase64(kdf["salt"])
            nonce := BinaryCodec.FromBase64(cipher["nonce"])
            tag := BinaryCodec.FromBase64(cipher["tag"])
            ciphertext := BinaryCodec.FromBase64(envelope["ciphertext"])
            if salt.Size < 16 || nonce.Size != 12 || tag.Size != 16
                throw AppError("Credential envelope parameters are invalid", "INVALID_ENVELOPE")
            key := CngCrypto.DeriveKey(password, salt, iterations)
            try {
                decrypted := CngCrypto.AesGcm(false, ciphertext, ciphertext.Size, key, nonce, tag)
                return Utf8Decode(decrypted["data"], decrypted["data"].Size)
            } finally {
                SecureZero(key)
                if IsSet(decrypted)
                    SecureZero(decrypted["data"])
            }
        } catch as caughtError {
            if caughtError is AppError
                throw
            throw AppError("The password is incorrect or the credential file was modified", "DECRYPT_FAILED")
        }
    }

    static AesGcm(encrypt, input, inputLength, key, nonce, tag := unset) {
        algorithm := 0, keyHandle := 0
        keyObject := "", authInfo := "", output := "", tagBuffer := ""
        try {
            status := DllCall("Bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &algorithm, "WStr", "AES", "Ptr", 0, "UInt", 0, "UInt")
            CngCrypto.Check(status, "BCryptOpenAlgorithmProvider(AES)")
            mode := Buffer(StrPut("ChainingModeGCM", "UTF-16") * 2, 0)
            StrPut("ChainingModeGCM", mode, "UTF-16")
            status := DllCall("Bcrypt\BCryptSetProperty", "Ptr", algorithm, "WStr", "ChainingMode", "Ptr", mode.Ptr, "UInt", mode.Size, "UInt", 0, "UInt")
            CngCrypto.Check(status, "BCryptSetProperty(ChainingModeGCM)")

            objectLength := 0, resultLength := 0
            status := DllCall("Bcrypt\BCryptGetProperty", "Ptr", algorithm, "WStr", "ObjectLength", "UInt*", &objectLength, "UInt", 4, "UInt*", &resultLength, "UInt", 0, "UInt")
            CngCrypto.Check(status, "BCryptGetProperty(ObjectLength)")
            keyObject := Buffer(objectLength, 0)
            status := DllCall("Bcrypt\BCryptGenerateSymmetricKey", "Ptr", algorithm, "Ptr*", &keyHandle, "Ptr", keyObject.Ptr, "UInt", keyObject.Size, "Ptr", key.Ptr, "UInt", key.Size, "UInt", 0, "UInt")
            CngCrypto.Check(status, "BCryptGenerateSymmetricKey")

            tagBuffer := IsSet(tag) ? BufferClone(tag) : Buffer(16, 0)
            authInfo := CngCrypto.MakeAuthInfo(nonce, tagBuffer)
            output := Buffer(inputLength, 0)
            outputLength := 0
            functionName := encrypt ? "Bcrypt\BCryptEncrypt" : "Bcrypt\BCryptDecrypt"
            status := DllCall(functionName
                , "Ptr", keyHandle
                , "Ptr", input.Ptr, "UInt", inputLength
                , "Ptr", authInfo.Ptr
                , "Ptr", 0, "UInt", 0
                , "Ptr", output.Ptr, "UInt", output.Size
                , "UInt*", &outputLength
                , "UInt", 0, "UInt")
            if status != 0
                throw AppError(encrypt ? "Credential encryption failed" : "The password is incorrect or the credential file was modified", encrypt ? "ENCRYPT_FAILED" : "DECRYPT_FAILED")
            if outputLength != output.Size
                output := BufferClone(output, outputLength)
            return Map("data", output, "tag", tagBuffer)
        } finally {
            if keyHandle
                DllCall("Bcrypt\BCryptDestroyKey", "Ptr", keyHandle)
            if algorithm
                DllCall("Bcrypt\BCryptCloseAlgorithmProvider", "Ptr", algorithm, "UInt", 0)
            if Type(keyObject) == "Buffer"
                SecureZero(keyObject)
        }
    }

    static MakeAuthInfo(nonce, tag) {
        if A_PtrSize == 8 {
            info := Buffer(88, 0)
            NumPut("UInt", 88, info, 0)
            NumPut("UInt", 1, info, 4)
            NumPut("Ptr", nonce.Ptr, info, 8), NumPut("UInt", nonce.Size, info, 16)
            NumPut("Ptr", 0, info, 24), NumPut("UInt", 0, info, 32)
            NumPut("Ptr", tag.Ptr, info, 40), NumPut("UInt", tag.Size, info, 48)
            NumPut("Ptr", 0, info, 56), NumPut("UInt", 0, info, 64)
            NumPut("UInt", 0, info, 68), NumPut("UInt64", 0, info, 72), NumPut("UInt", 0, info, 80)
        } else {
            info := Buffer(64, 0)
            NumPut("UInt", 64, info, 0)
            NumPut("UInt", 1, info, 4)
            NumPut("Ptr", nonce.Ptr, info, 8), NumPut("UInt", nonce.Size, info, 12)
            NumPut("Ptr", 0, info, 16), NumPut("UInt", 0, info, 20)
            NumPut("Ptr", tag.Ptr, info, 24), NumPut("UInt", tag.Size, info, 28)
            NumPut("Ptr", 0, info, 32), NumPut("UInt", 0, info, 36)
            NumPut("UInt", 0, info, 40), NumPut("UInt64", 0, info, 48), NumPut("UInt", 0, info, 56)
        }
        return info
    }

    static Check(status, operation) {
        if status != 0
            throw AppError(operation " failed with NTSTATUS " Format("0x{:08X}", status), "CRYPTO_FAILURE")
    }
}

class Dpapi {
    static Protect(text) {
        input := Utf8Encode(text)
        try {
            protected := Dpapi.Transform(true, input["buffer"], input["length"])
            return BinaryCodec.ToBase64(protected)
        } finally {
            SecureZero(input["buffer"])
            if IsSet(protected)
                SecureZero(protected)
        }
    }

    static Unprotect(encoded) {
        protected := BinaryCodec.FromBase64(encoded)
        try {
            plaintext := Dpapi.Transform(false, protected, protected.Size)
            return Utf8Decode(plaintext, plaintext.Size)
        } finally {
            SecureZero(protected)
            if IsSet(plaintext)
                SecureZero(plaintext)
        }
    }

    static Transform(protect, input, length) {
        blobSize := A_PtrSize == 8 ? 16 : 8
        pointerOffset := A_PtrSize == 8 ? 8 : 4
        inputBlob := Buffer(blobSize, 0), outputBlob := Buffer(blobSize, 0)
        NumPut("UInt", length, inputBlob, 0), NumPut("Ptr", input.Ptr, inputBlob, pointerOffset)
        functionName := protect ? "Crypt32\CryptProtectData" : "Crypt32\CryptUnprotectData"
        description := 0
        if protect {
            success := DllCall(functionName, "Ptr", inputBlob.Ptr, "WStr", AppInfo.Name, "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 1, "Ptr", outputBlob.Ptr)
        } else {
            success := DllCall(functionName, "Ptr", inputBlob.Ptr, "Ptr*", &description, "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 1, "Ptr", outputBlob.Ptr)
        }
        if !success
            throw AppError("Windows could not " (protect ? "protect" : "unprotect") " the cached credential key (Win32 " A_LastError ")", "DPAPI_FAILURE")
        outputLength := NumGet(outputBlob, 0, "UInt")
        outputPointer := NumGet(outputBlob, pointerOffset, "Ptr")
        output := Buffer(outputLength, 0)
        try DllCall("RtlMoveMemory", "Ptr", output.Ptr, "Ptr", outputPointer, "UPtr", outputLength)
        finally {
            if outputPointer
                DllCall("LocalFree", "Ptr", outputPointer)
            if description
                DllCall("LocalFree", "Ptr", description)
        }
        return output
    }
}

class LegacyCrypto {
    static DecryptHex(ciphertextHex, password) {
        data := BinaryCodec.FromHex(ciphertextHex)
        provider := 0, hash := 0, key := 0
        passwordBuffer := Buffer(StrPut(password, "UTF-16") * 2, 0)
        StrPut(password, passwordBuffer, "UTF-16")
        try {
            if !DllCall("Advapi32\CryptAcquireContextW", "Ptr*", &provider, "Ptr", 0, "Ptr", 0, "UInt", 24, "UInt", 0xF0000000)
                throw OSError(A_LastError, -1, "CryptAcquireContextW failed")
            if !DllCall("Advapi32\CryptCreateHash", "Ptr", provider, "UInt", 0x800C, "Ptr", 0, "UInt", 0, "Ptr*", &hash)
                throw OSError(A_LastError, -1, "CryptCreateHash failed")
            if !DllCall("Advapi32\CryptHashData", "Ptr", hash, "Ptr", passwordBuffer.Ptr, "UInt", passwordBuffer.Size - 2, "UInt", 0)
                throw OSError(A_LastError, -1, "CryptHashData failed")
            if !DllCall("Advapi32\CryptDeriveKey", "Ptr", provider, "UInt", 0x6801, "Ptr", hash, "UInt", 0x00800000, "Ptr*", &key)
                throw OSError(A_LastError, -1, "CryptDeriveKey failed")
            length := data.Size
            if !DllCall("Advapi32\CryptDecrypt", "Ptr", key, "Ptr", 0, "Int", true, "UInt", 0, "Ptr", data.Ptr, "UInt*", &length)
                throw AppError("Legacy credential decryption failed", "LEGACY_DECRYPT_FAILED")
            return StrGet(data.Ptr, length // 2, "UTF-16")
        } finally {
            SecureZero(passwordBuffer), SecureZero(data)
            if key
                DllCall("Advapi32\CryptDestroyKey", "Ptr", key)
            if hash
                DllCall("Advapi32\CryptDestroyHash", "Ptr", hash)
            if provider
                DllCall("Advapi32\CryptReleaseContext", "Ptr", provider, "UInt", 0)
        }
    }
}
