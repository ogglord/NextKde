import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// The desktop context menu builds its entries with _ctxAct/_ctxCheck and
// dispatches every click through runContextCmd's switch. A command without a
// case there is silently dropped: the "Power Off or Log Out" entries shipped
// that way, so Lock, Sleep, Switch User, Log Out, Restart and Power Off did
// nothing from the desktop while the same entries worked from the top bar.

const source = readFileSync(
    new URL("../../shell/desktop/modules/deskcenter/DeskCenterWindow.qml", import.meta.url), "utf8");

function runContextCmdBody() {
    const at = source.indexOf("function runContextCmd(");
    assert.ok(at > 0, "runContextCmd moved; update this test");
    const end = source.indexOf("\n        function ", at + 1);
    assert.ok(end > at, "could not find the end of runContextCmd");
    return source.slice(at, end);
}

test("every desktop context-menu command has a runContextCmd case", () => {
    const menuCommands = new Set(
        [...source.matchAll(/_ctx(?:Act|Check)\([^,]+,\s*"([A-Za-z]+)"/g)].map(m => m[1]));
    assert.ok(menuCommands.size > 0, "no _ctxAct/_ctxCheck entries found; update this test");
    const handled = new Set(
        [...runContextCmdBody().matchAll(/case\s+"([A-Za-z]+)"\s*:/g)].map(m => m[1]));
    const missing = [...menuCommands].filter(cmd => !handled.has(cmd));
    assert.deepEqual(missing, [], `menu commands without a runContextCmd case: ${missing.join(", ")}`);
});

test("session entries reach the control center after the menu click", () => {
    const body = runContextCmdBody();
    for (const cmd of ["lock", "suspend", "switch", "logout", "reboot", "poweroff"])
        assert.match(body, new RegExp(`case\\s+"${cmd}"\\s*:`), `${cmd} has no case`);
    assert.match(body, /Qt\.callLater\(triggerContextAction,\s*cmd\)/);
    const trigger = source.slice(source.indexOf("function triggerContextAction("),
        source.indexOf("function _ctxSub("));
    assert.match(trigger, /ControlCenterService\.requestSessionAction\(kind\)/);
});
