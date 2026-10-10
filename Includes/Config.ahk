class CredentialConfig {
    static Normalize(config) {
        RequireMap(config, "credentials")
        if MapGet(config, "schemaVersion", 0) == AppInfo.CredentialSchemaVersion && config.Has("autofillRules") {
            migrated := CredentialConfig.UpgradeKnownRules(config)
            CredentialConfig.Validate(config)
            return Map("config", config, "migrated", migrated)
        }
        migrated := CredentialConfig.FromLegacy(config)
        CredentialConfig.Validate(migrated)
        return Map("config", migrated, "migrated", true)
    }

    static FromLegacy(legacy) {
        passwords := legacy.Has("passwords") && legacy["passwords"] is Map ? legacy["passwords"] : Map()
        rules := []
        if legacy.Has("autofill") && legacy["autofill"] is Map {
            for windowType, windows in legacy["autofill"] {
                if !(windows is Map)
                    continue
                for titlePattern, properties in windows {
                    if !(properties is Map) || !properties.Has("Components") || !(properties["Components"] is Map)
                        continue
                    match := Map("titleRegex", "^(?:" titlePattern ")$")
                    if StrLower(windowType) == "radmin security"
                        match["class"] := "#32770"
                    steps := []
                    for control, component in properties["Components"] {
                        if !(component is Map)
                            continue
                        componentType := StrLower(MapGet(component, "Type"))
                        action := componentType == "checkbox" ? "setChecked" : componentType == "button" ? "click" : "setText"
                        step := Map("id", String(control), "control", String(control), "action", action)
                        if component.Has("Label")
                            step["label"] := component["Label"]
                        if component.Has("Value")
                            step["value"] := component["Value"]
                        if component.Has("IfExecuted")
                            step["dependsOn"] := component["IfExecuted"]
                        if action == "setText"
                            step["verify"] := componentType == "passwordbox" ? "controlExists" : "textEquals"
                        else if action == "setChecked"
                            step["verify"] := "checkedEquals"
                        else if MapGet(component, "WaitForWindowClose", false)
                            step["verify"] := "windowClosed"
                        steps.Push(step)
                    }
                    rule := Map(
                        "id", CredentialConfig.MakeRuleId(windowType, titlePattern),
                        "enabled", 1,
                        "target", "native",
                        "match", match,
                        "steps", steps
                    )
                    if properties.Has("WinMove") {
                        parts := StrSplit(String(properties["WinMove"]), ",")
                        if parts.Length >= 2
                            rule["move"] := Map("x", Integer(Trim(parts[1])), "y", Integer(Trim(parts[2])))
                    }
                    rules.Push(rule)
                }
            }
        }
        return Map("schemaVersion", AppInfo.CredentialSchemaVersion, "passwords", passwords, "autofillRules", rules)
    }

    static UpgradeKnownRules(config) {
        migrated := false
        rules := MapGet(config, "autofillRules", [])
        if !(rules is Array)
            return false
        for index, rule in rules {
            if !(rule is Map) || MapGet(rule, "id") != "radmin-security"
                continue
            match := MapGet(rule, "match", 0)
            steps := MapGet(rule, "steps", 0)
            obsoleteSample := match is Map && MapGet(match, "process") == "Radmin.exe"
                && MapGet(match, "titleRegex") == "^Radmin Security.*$"
                && steps is Array && steps.Length == 3
                && MapGet(steps[3], "control") == "Button1" && MapGet(steps[3], "action") == "click"
            if !obsoleteSample
                continue
            match.Delete("process")
            match["titleRegex"] := "i)^Radmin security:"
            steps[1]["value"] := "User"
            steps[3] := Map(
                "id", "save-user", "control", "Button1", "action", "setChecked",
                "value", 1, "dependsOn", "password", "verify", "checkedEquals"
            )
            steps.Push(Map(
                "id", "submit", "control", "Button2", "action", "click",
                "dependsOn", "save-user", "verify", "windowClosed", "timeoutMs", 5000
            ))
            migrated := true
        }
        return migrated
    }

    static MakeRuleId(windowType, titlePattern) {
        value := StrLower(windowType "-" titlePattern)
        value := RegExReplace(value, "[^a-z0-9]+", "-")
        value := Trim(value, "-")
        return value == "" ? "autofill-rule" : value
    }

    static Validate(config) {
        if MapGet(config, "schemaVersion", 0) != AppInfo.CredentialSchemaVersion
            throw AppError("Unsupported credential schema version", "INVALID_CONFIG")
        passwords := RequireMap(MapGet(config, "passwords", 0), "passwords")
        if !passwords.Has("password")
            throw AppError("passwords.password is required", "INVALID_CONFIG")
        if config.Has("siteCredentials")
            RequireMap(config["siteCredentials"], "siteCredentials")
        rules := RequireArray(MapGet(config, "autofillRules", 0), "autofillRules")
        ids := Map()
        for index, rule in rules {
            RequireMap(rule, "autofillRules[" index "]")
            id := String(MapGet(rule, "id"))
            if id == "" || ids.Has(id)
                throw AppError("Every autofill rule needs a unique non-empty id", "INVALID_CONFIG")
            ids[id] := true
            target := StrLower(String(MapGet(rule, "target", "native")))
            if target != "native" && target != "browser"
                throw AppError("Rule " id " has an unsupported target", "INVALID_CONFIG")
            match := RequireMap(MapGet(rule, "match", 0), "autofill rule match")
            if target == "native" && !match.Has("class") && !match.Has("titleRegex") && !match.Has("process")
                throw AppError("Autofill rule " id " has no match criteria", "INVALID_CONFIG")
            if match.Has("titleRegex") {
                try RegExMatch("", match["titleRegex"])
                catch
                    throw AppError("Autofill rule " id " has an invalid titleRegex", "INVALID_CONFIG")
            }
            if target == "browser" {
                origin := String(MapGet(match, "origin"))
                if !RegExMatch(origin, "i)^https?://[a-z0-9.-]+(?::\d+)?$")
                    throw AppError("Browser rule " id " requires an exact HTTP or HTTPS origin", "INVALID_CONFIG")
                if match.Has("frameOrigin") && !RegExMatch(String(match["frameOrigin"]), "i)^https?://[a-z0-9.-]+(?::\d+)?$")
                    throw AppError("Browser rule " id " requires an exact HTTP or HTTPS frameOrigin", "INVALID_CONFIG")
                if match.Has("pathRegex") {
                    try RegExMatch("", match["pathRegex"])
                    catch
                        throw AppError("Browser rule " id " has an invalid pathRegex", "INVALID_CONFIG")
                }
                if match.Has("framePathRegex") {
                    if !match.Has("frameOrigin")
                        throw AppError("Browser rule " id " needs frameOrigin with framePathRegex", "INVALID_CONFIG")
                    try RegExMatch("", match["framePathRegex"])
                    catch
                        throw AppError("Browser rule " id " has an invalid framePathRegex", "INVALID_CONFIG")
                }
            }
            if rule.Has("presentation") {
                if target != "native"
                    throw AppError("Only native rules may define presentation", "INVALID_CONFIG")
                presentation := RequireMap(rule["presentation"], "presentation")
                mode := StrLower(String(MapGet(presentation, "mode", "normal")))
                if mode != "normal" && mode != "offscreen"
                    throw AppError("Rule " id " has an unsupported presentation mode", "INVALID_CONFIG")
                if mode == "offscreen" && presentation.Has("restore") && !presentation["restore"]
                    throw AppError("Offscreen presentation must restore the target window", "INVALID_CONFIG")
                edge := StrLower(String(MapGet(presentation, "edge", "top")))
                if edge != "top" && edge != "bottom" && edge != "left" && edge != "right"
                    throw AppError("Rule " id " has an unsupported offscreen edge", "INVALID_CONFIG")
            }
            steps := RequireArray(MapGet(rule, "steps", 0), "autofill rule steps")
            stepIds := Map()
            browserClicks := 0
            for stepIndex, step in steps {
                RequireMap(step, "step " stepIndex)
                stepId := String(MapGet(step, "id"))
                if stepId == "" || stepIds.Has(stepId)
                    throw AppError("Rule " id " has a missing or duplicate step id", "INVALID_CONFIG")
                action := MapGet(step, "action")
                if action != "setText" && action != "setChecked" && action != "click"
                    throw AppError("Rule " id " uses an unsupported action", "INVALID_CONFIG")
                if target == "browser" && action == "click" {
                    browserClicks += 1
                    if stepIndex != steps.Length
                        throw AppError("Browser rule " id " must put submit last", "INVALID_CONFIG")
                }
                if step.Has("submitMethod") {
                    if target != "browser" || action != "click"
                        throw AppError("Rule " id " may use submitMethod only on a browser click step", "INVALID_CONFIG")
                    if String(step["submitMethod"]) != "dom" && String(step["submitMethod"]) != "extjs"
                        throw AppError("Rule " id " has an unsupported submitMethod", "INVALID_CONFIG")
                }
                targetField := target == "browser" ? "selector" : "control"
                if String(MapGet(step, targetField)) == ""
                    throw AppError("Rule " id " has a step without a " targetField, "INVALID_CONFIG")
                if step.Has("value") && step.Has("valueFrom")
                    throw AppError("A step cannot define both value and valueFrom", "INVALID_CONFIG")
                if target == "browser" && action != "click" && !step.Has("value") && !step.Has("valueFrom")
                    throw AppError("Browser rule " id " has a value-less input step", "INVALID_CONFIG")
                if step.Has("dependsOn") && !stepIds.Has(String(step["dependsOn"]))
                    throw AppError("Rule " id " has a dependency that does not name an earlier step", "INVALID_CONFIG")
                if step.Has("inputMethod") {
                    if target != "native" || action != "setText"
                        throw AppError("Rule " id " may use inputMethod only on native setText steps", "INVALID_CONFIG")
                    inputMethod := StrLower(String(step["inputMethod"]))
                    if inputMethod != "direct" && inputMethod != "paste" && inputMethod != "type"
                        throw AppError("Rule " id " uses an unsupported inputMethod", "INVALID_CONFIG")
                }
                if step.Has("keyDelayMs") {
                    if target != "native" || action != "setText" || StrLower(String(MapGet(step, "inputMethod", "direct"))) != "type"
                        throw AppError("Rule " id " may use keyDelayMs only with inputMethod type", "INVALID_CONFIG")
                    try keyDelayMs := Integer(step["keyDelayMs"])
                    catch
                        throw AppError("Rule " id " has an invalid keyDelayMs", "INVALID_CONFIG")
                    if keyDelayMs < 0 || keyDelayMs > 1000
                        throw AppError("Rule " id " keyDelayMs must be between 0 and 1000", "INVALID_CONFIG")
                }
                verification := String(MapGet(step, "verify", action == "setText" ? "controlExists" : action == "setChecked" ? "checkedEquals" : "none"))
                allowedVerification := action == "setText" ? Map("controlExists", true, "textEquals", true, "none", true)
                    : action == "setChecked" ? Map("checkedEquals", true, "controlExists", true, "none", true)
                    : Map("windowClosed", true, "controlExists", true, "none", true)
                if !allowedVerification.Has(verification)
                    throw AppError("Rule " id " uses an unsupported verification mode for " action, "INVALID_CONFIG")
                stepIds[stepId] := true
            }
            if target == "browser" && (browserClicks != (MapGet(rule, "autoSubmit", false) ? 1 : 0))
                throw AppError("Browser rule " id " needs one final click only when autoSubmit is enabled", "INVALID_CONFIG")
        }
        return true
    }

    static ResolvePath(config, path) {
        current := config
        for segment in StrSplit(path, ".") {
            if !(current is Map) || !current.Has(segment)
                throw AppError("Credential reference was not found: " path, "INVALID_CONFIG")
            current := current[segment]
        }
        if IsObject(current)
            throw AppError("Credential reference does not identify a scalar value: " path, "INVALID_CONFIG")
        return current
    }

    static ResolveStep(rule, config) {
        clone := Map()
        for key, value in rule
            clone[key] := value
        if clone.Has("valueFrom") {
            clone["value"] := CredentialConfig.ResolvePath(config, clone["valueFrom"])
            clone.Delete("valueFrom")
        }
        return clone
    }
}
