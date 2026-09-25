/*
 * build.js: pack src/ into patch-W.mpq, the patch a client installs.
 *
 *   node build.js [-o <out.mpq>]
 *
 * Four files go in, all under Interface\GlueXML:
 *
 *   MovieFrame.xml        Blizzard's own, from the 1.12.1 patch.MPQ, with one
 *                         Include line added at the end. This is what loads us
 *   ComfyLoginPanel.xml   the frames, and a <Script> line that loads the Lua
 *   ComfyLogin.lua        the code
 *   ComfyLogin.xml        empty, for the Include line in older patch-V copies
 *
 * src/README.md has why.
 *
 * tools/pack.js writes the archive and reads every file back before it exits.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const args = process.argv.slice(2);
const i = args.indexOf('-o');
const out = path.resolve(i < 0 ? path.join(__dirname, 'patch-W.mpq') : args[i + 1]);

// The client reads glue files as they are, so each one goes in with CRLF
// endings, the way Blizzard's own are.
const stage = fs.mkdtempSync(path.join(os.tmpdir(), 'comfylogin-'));
const packArgs = [path.join(__dirname, 'tools', 'pack.js'), out];
for (const name of ['MovieFrame.xml', 'ComfyLoginPanel.xml', 'ComfyLogin.lua', 'ComfyLogin.xml']) {
    const text = fs.readFileSync(path.join(__dirname, 'src', name), 'latin1').replace(/\r\n/g, '\n');
    const local = path.join(stage, name);
    fs.writeFileSync(local, Buffer.from(text.split('\n').join('\r\n'), 'latin1'));
    packArgs.push('Interface/GlueXML/' + name + '=' + local);
}
execFileSync(process.execPath, packArgs, { stdio: 'inherit' });
fs.rmSync(stage, { recursive: true, force: true });
