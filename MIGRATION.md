# Migrating from the AutoHotkey v1 release

The v2 application upgrades legacy data only after it has successfully decrypted and validated it.

1. Keep the existing `credentials.json.enc` beside the four new executables.
2. Start `shortcut-keys.exe` and enter the existing master password if automatic unlock is unavailable.
3. The application saves the old ciphertext as `credentials.json.enc.legacy.bak`, converts the credential schema, writes an authenticated v2 envelope to a temporary file, verifies it, and then replaces the original.
4. The existing HKLM cached key is copied into a current-user DPAPI-protected HKCU value after it proves able to decrypt the file. Removal of the old HKLM value is attempted afterward and may require manual administrator cleanup.

The backup is ignored by Git. Do not delete it until the new application has been tested against the required windows.

The v2 migration deliberately stops reading `Winlogon\DefaultPassword`. It never sends a credential on a process command line and never includes credential values in logs or tooltips.

To change configuration, use the tray menu to export JSON, edit the exported file, and then select **Import and Encrypt JSON**. The plaintext export is not deleted automatically.
