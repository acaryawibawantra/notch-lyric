// Pure formatter is also exercised offline by tests. Never executes supplied text.
function makeMorisTaskURL(event, token, now) {
    if (!token || token.length > 128) throw new Error("Missing pairing token");
    if (!/^[A-Za-z0-9._:-]{1,80}$/.test(event.id || "")) throw new Error("Invalid task id");
    if (["running", "waiting", "completed", "failed"].indexOf(event.status) < 0) throw new Error("Invalid state");
    if (["command", "claude"].indexOf(event.source) < 0) throw new Error("Invalid source");
    var title = String(event.title || "");
    if (!title.trim() || Array.from(title).length > 160 || /[\x00-\x1f\x7f]/.test(title)) throw new Error("Invalid title");
    var fields = { id: event.id, status: event.status, title: title, source: event.source, sentAt: String(now), token: token };
    return "moris://task?" + Object.keys(fields).map(function (key) {
        return encodeURIComponent(key) + "=" + encodeURIComponent(fields[key]);
    }).join("&");
}

function morisClaudeEvent(input) {
    var state;
    switch (input.hook_event_name) {
        case "UserPromptSubmit": case "PostToolUse": state = "running"; break;
        case "Stop": state = "completed"; break;
        case "StopFailure": state = "failed"; break;
        case "PermissionRequest": state = "waiting"; break;
        case "Notification":
            if (["permission_prompt", "elicitation_dialog"].indexOf(input.notification_type) < 0) return null;
            state = "waiting"; break;
        default: return null;
    }
    return { id: input.session_id, status: state, title: "Claude Code turn", source: "claude" };
}

// macOS JavaScript for Automation. No application scripting/Automation permission.
function run(argv) {
    ObjC.import("Foundation");
    var token = String(ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey("MORIS_TASK_TOKEN")) || "");
    var event;
    if (argv[0] === "hook") {
        var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
        if (Number(data.length) > 1048576) throw new Error("Hook payload too large");
        var text = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
        event = morisClaudeEvent(JSON.parse(text));
        if (!event) return "";
    } else if (argv[0] === "event") {
        event = { id: argv[1], status: argv[2], title: argv[3], source: argv[4] || "command" };
    } else { throw new Error("Unknown event mode"); }
    return makeMorisTaskURL(event, token, Date.now());
}
