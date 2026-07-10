import Foundation
import SignalLightShared

private let codexEventToSignal: [String: String] = [
    "SessionStart": "session_start",
    "UserPromptSubmit": "thinking",
    "PreToolUse": "working",
    "PostToolUse": "tool_done",
    "PermissionRequest": "permission",
    "Stop": "done",
    "SessionEnd": "session_end",
]

private let claudeEventToSignal: [String: String] = [
    "SessionStart": "session_start",
    "UserPromptSubmit": "thinking",
    "PreToolUse": "working",
    "PostToolUse": "tool_done",
    "PostToolUseFailure": "blocked",
    "PostToolBatch": "working",
    "PermissionDenied": "blocked",
    "PreCompact": "working",
    "PostCompact": "tool_done",
    "SubagentStart": "working",
    "SubagentStop": "tool_done",
    "TaskCreated": "working",
    "TaskCompleted": "tool_done",
    "Stop": "done",
    "StopFailure": "blocked",
    "Notification": "attention",
    "PermissionRequest": "permission",
    "SessionEnd": "session_end",
]

private let cursorEventToSignal: [String: String] = [
    "sessionStart": "session_start",
    "beforeSubmitPrompt": "thinking",
    "preToolUse": "working",
    "postToolUse": "tool_done",
    "postToolUseFailure": "blocked",
    "subagentStart": "working",
    "subagentStop": "tool_done",
    "beforeShellExecution": "working",
    "afterShellExecution": "tool_done",
    "beforeMCPExecution": "working",
    "afterMCPExecution": "tool_done",
    "beforeReadFile": "working",
    "afterFileEdit": "tool_done",
    "preCompact": "working",
    "afterAgentResponse": "tool_done",
    "afterAgentThought": "tool_done",
    "stop": "done",
    "sessionEnd": "session_end",
]

private let failureSignals: [String: String] = [
    "error": "blocked",
    "failed": "blocked",
    "failure": "blocked",
    "exception": "blocked",
]

private let modelPayloadKeys = [
    "model",
    "model_name",
    "ai_model",
    "llm_model",
    "selected_model",
    "provider_model",
]

private let modelEnvironmentKeys = [
    "SIGNAL_LIGHT_MODEL",
    "CODEX_MODEL",
    "OPENAI_MODEL",
    "ANTHROPIC_MODEL",
    "CLAUDE_MODEL",
]

func readPayload(stdinText: String) -> [String: Any] {
    guard let data = stdinText.data(using: .utf8),
          let parsed = try? JSONSerialization.jsonObject(with: data),
          let payload = parsed as? [String: Any]
    else {
        return stdinText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [:] : ["raw": stdinText]
    }
    return payload
}

private let codexCamelCaseEventToSignal: [String: String] = [
    "sessionStart": "session_start",
    "userPromptSubmit": "thinking",
    "preToolUse": "working",
    "postToolUse": "tool_done",
    "permissionRequest": "permission",
    "stop": "done",
    "sessionEnd": "session_end",
]

func resolvedCodexEventSignal(eventName: String) -> String? {
    let trimmed = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    if let signal = codexEventToSignal[trimmed] {
        return signal
    }
    if let signal = codexCamelCaseEventToSignal[trimmed] {
        return signal
    }
    if let signal = cursorEventToSignal[trimmed] {
        return signal
    }

    if let first = trimmed.first, first.isLowercase {
        let pascalCase = String(first).uppercased() + trimmed.dropFirst()
        if let signal = codexEventToSignal[pascalCase] {
            return signal
        }
    }

    return nil
}

func chooseCodexSignal(eventName: String, payload: [String: Any]) -> String {
    if let explicit = firstString(payload, keys: ["signal", "signal_name", "lamp_signal"])?.lowercased(),
       validSignals.contains(explicit) {
        return explicit
    }

    if let status = firstString(payload, keys: ["status", "state"])?.lowercased() {
        if validSignals.contains(status) {
            return status
        }
        if let failureSignal = failureSignals[status] {
            return failureSignal
        }
    }

    if hasStructuredFailure(payload) {
        return "blocked"
    }

    return resolvedCodexEventSignal(eventName: eventName) ?? "attention"
}

func chooseClaudeSignal(eventName: String, payload: [String: Any]) -> String {
    if let explicit = firstString(payload, keys: ["signal", "signal_name"])?.lowercased(),
       validSignals.contains(explicit) {
        return explicit
    }

    if eventName == "Stop",
       let stopReason = payload["stop_reason"] as? String,
       ["max_tokens", "error"].contains(stopReason) {
        return "blocked"
    }

    return claudeEventToSignal[eventName] ?? "attention"
}

func codexSessionKey(payload: [String: Any], environment: [String: String]) -> String {
    if let explicit = firstString(
        payload,
        keys: ["session_id", "conversation_id", "thread_id", "chat_id", "codex_session_id"]
    ) {
        return explicit
    }

    if let nested = findNestedString(
        payload,
        keys: ["session_id", "conversation_id", "thread_id", "codex_session_id"]
    ) {
        return nested
    }

    for key in ["CODEX_SESSION_ID", "CODEX_CONVERSATION_ID", "CODEX_THREAD_ID"] {
        if let value = environment[key], !value.isEmpty {
            return value
        }
    }

    if let cwd = firstString(payload, keys: ["cwd", "workspace", "workspace_dir", "project_dir"]) {
        return "cwd:\(cwd)"
    }
    return "global"
}

func claudeSessionKey(payload: [String: Any], environment: [String: String]) -> String {
    if let sid = payload["session_id"] as? String, !sid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return sid.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    for key in ["CLAUDE_CODE_SESSION_ID", "CLAUDE_SESSION_ID"] {
        if let value = environment[key], !value.isEmpty {
            return value
        }
    }

    if let cwd = payload["cwd"] as? String, !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "cwd:\(cwd.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
    return "global"
}

func chooseCursorSignal(eventName: String, payload: [String: Any]) -> String {
    if let explicit = firstString(payload, keys: ["signal", "signal_name", "lamp_signal"])?.lowercased(),
       validSignals.contains(explicit) {
        return explicit
    }

    if eventName == "stop",
       let status = payload["status"] as? String,
       ["error", "aborted"].contains(status) {
        return "blocked"
    }

    if let status = firstString(payload, keys: ["status", "state"])?.lowercased() {
        if validSignals.contains(status) {
            return status
        }
        if let failureSignal = failureSignals[status] {
            return failureSignal
        }
    }

    if hasStructuredFailure(payload) {
        return "blocked"
    }

    return cursorEventToSignal[eventName] ?? cursorEventToSignal[eventName.trimmingCharacters(in: .whitespacesAndNewlines)] ?? "attention"
}

func cursorSessionKey(payload: [String: Any], environment: [String: String]) -> String {
    if let conversationId = payload["conversation_id"] as? String,
       !conversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    for key in ["CURSOR_SESSION_ID", "CURSOR_CONVERSATION_ID"] {
        if let value = environment[key], !value.isEmpty {
            return value
        }
    }

    if let workspaceRoots = payload["workspace_roots"] as? [String],
       let firstRoot = workspaceRoots.first,
       !firstRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return firstRoot.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    if let cwd = firstString(payload, keys: ["cwd", "workspace", "workspace_dir", "project_dir"]) {
        return "cwd:\(cwd)"
    }
    return "global"
}

func eventFromArgs(_ args: [String], payload: [String: Any], keys: [String], fallback: String) -> String {
    for (index, value) in args.enumerated() {
        if ["--event", "-e"].contains(value), index + 1 < args.count {
            return args[index + 1]
        }
        if value.hasPrefix("--event=") {
            return String(value.dropFirst("--event=".count))
        }
    }
    if let first = args.first, !first.hasPrefix("-") {
        return first
    }
    for key in keys {
        if let value = payload[key] as? String, !value.isEmpty {
            return value
        }
    }
    return fallback
}

func modelName(payload: [String: Any], environment: [String: String]) -> String? {
    if let direct = firstString(payload, keys: modelPayloadKeys) {
        return direct
    }
    if let nested = findNestedString(payload, keys: modelPayloadKeys) {
        return nested
    }
    for key in modelEnvironmentKeys {
        if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
    }
    return nil
}

private func firstString(_ payload: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = payload[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
    }
    return nil
}

private func findNestedString(_ value: Any, keys: [String]) -> String? {
    if let payload = value as? [String: Any] {
        if let direct = firstString(payload, keys: keys) {
            return direct
        }
        for child in payload.values {
            if let found = findNestedString(child, keys: keys) {
                return found
            }
        }
    } else if let list = value as? [Any] {
        for child in list {
            if let found = findNestedString(child, keys: keys) {
                return found
            }
        }
    }
    return nil
}

private func hasStructuredFailure(_ value: Any) -> Bool {
    let failureKeys: Set<String> = [
        "error",
        "failure",
        "exception",
        "error_type",
        "error_message",
        "failure_reason",
        "exit_status",
        "tool_error",
    ]

    if let payload = value as? [String: Any] {
        for (key, child) in payload {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if failureSignals[normalizedKey] != nil || failureKeys.contains(normalizedKey) {
                if valueLooksFailed(child) {
                    return true
                }
            }
            if hasStructuredFailure(child) {
                return true
            }
        }
    } else if let list = value as? [Any] {
        return list.contains(where: hasStructuredFailure)
    }
    return false
}

private func valueLooksFailed(_ value: Any) -> Bool {
    if let bool = value as? Bool {
        return bool
    }
    if value is NSNull {
        return false
    }
    if let number = value as? NSNumber {
        return number.doubleValue != 0
    }
    if let text = value as? String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty || ["0", "false", "no", "none", "null", "success", "ok"].contains(normalized) {
            return false
        }
        return true
    }
    return true
}
