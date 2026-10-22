const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {execFileSync} = require('node:child_process');
const path = require('node:path');
const formatter = path.resolve(__dirname, '../scripts/moris-task-url.js');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(formatter, 'utf8'), context);
const payload = {id: 'fixture-123', title: 'Build & test 🐈', status: 'running', source: 'command'};
const parsed = new URL(context.makeMorisTaskURL(payload, 'fixture-token', 1000));
assert.equal(parsed.searchParams.get('title'), payload.title);
assert.equal(parsed.searchParams.get('token'), 'fixture-token');
assert.throws(() => context.makeMorisTaskURL({...payload, id: '../bad'}, 'fixture', 1000));
assert.throws(() => context.makeMorisTaskURL(payload, '', 1000));
for (const [hook, status] of [['UserPromptSubmit', 'running'], ['Stop', 'completed'], ['StopFailure', 'failed'], ['PermissionRequest', 'waiting']]) {
    const event = context.morisClaudeEvent({session_id: 'fixture-session', hook_event_name: hook});
    assert.equal(event.status, status);
    assert.equal(event.source, 'claude');
}
assert.equal(context.morisClaudeEvent({hook_event_name:'Notification', notification_type:'idle_prompt'}), null);
assert.equal(context.morisClaudeEvent({hook_event_name:'Notification', notification_type:'permission_prompt', session_id:'fixture'}).status, 'waiting');
assert.equal(context.morisClaudeEvent({hook_event_name:'SessionEnd'}), null);
// Execute only the JXA formatter, NOT the delivery script or any URL handler.
const env = {...process.env, MORIS_TASK_TOKEN: 'fixture-test-token'};
const direct = execFileSync('/usr/bin/osascript', ['-l', 'JavaScript', formatter, 'event', 'fixture', 'completed', 'Fixture only', 'command'], {env, encoding:'utf8'});
assert.equal(new URL(direct.trim()).searchParams.get('status'), 'completed');
const hookURL = execFileSync('/usr/bin/osascript', ['-l', 'JavaScript', formatter, 'hook'], {
    env, encoding:'utf8', input: JSON.stringify({session_id:'fixture', hook_event_name:'Stop', transcript_path:'/not/read', last_assistant_message:'not forwarded'})
});
assert.equal(new URL(hookURL.trim()).searchParams.get('title'), 'Claude Code turn');
assert(!hookURL.includes('not%20forwarded') && !hookURL.includes('transcript'));
console.log('PASS: task URL encoding, hook mappings, idle filtering, native JXA formatter; no task delivered, commands run, or transcripts read');
