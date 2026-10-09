/*
 * build.js: pack src/ into patch-W.mpq, the patch a client installs.
 *
 *   node build.js [-o <out.mpq>]
 *   node build.js --zip
 *
 * --zip also writes comfylogin.zip, the release download. It holds
 * comfylogin.dll and Data\patch-W.mpq, so it extracts into a client folder as
 * it is. Build comfylogin.dll with CMake first.
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
const zip = args.includes('--zip');

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

if (zip) {
    const dll = path.join(__dirname, 'comfylogin.dll');
    if (!fs.existsSync(dll)) {
        console.error('no comfylogin.dll: build it with CMake first');
        process.exit(1);
    }
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'comfylogin-zip-'));
    fs.mkdirSync(path.join(root, 'Data'));
    fs.copyFileSync(dll, path.join(root, 'comfylogin.dll'));
    fs.copyFileSync(out, path.join(root, 'Data', 'patch-W.mpq'));
    const target = path.join(__dirname, 'comfylogin.zip');
    fs.rmSync(target, { force: true });
    // Windows' own tar is bsdtar, which writes zip. Git's tar is GNU tar, which does not.
    // Stored, not compressed: the ComfyCraft launcher fetches patch-W.mpq from this zip as a byte
    // range (launcher/lists/packages.json). An MPQ is compressed already, so storing costs little.
    const tar = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'tar.exe');
    execFileSync(tar, ['-a', '-c', '-f', target, '--options', 'zip:compression=store', '-C', root,
        'comfylogin.dll', 'Data/patch-W.mpq'], { stdio: 'inherit' });
    fs.rmSync(root, { recursive: true, force: true });
    console.log('wrote ' + target);
}
