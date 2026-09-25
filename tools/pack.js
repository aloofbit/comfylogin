/*
 * pack.js: write a small MPQ patch archive. A copy of ComfyCraft's
 * tools/model-browser/pack.js, with lib/mpq.js and lib/blast.js, so this repo
 * builds on its own. build.js calls it.
 *
 *   node tools/pack.js <out.mpq> <archive path>=<local file> ...
 *
 * Format version 0, the one a 1.12 client reads. Files are stored whole and
 * uncompressed, so there is no sector table and nothing to get wrong in one.
 * A (listfile) is added, so any MPQ tool can list what is inside.
 *
 * The archive is read back with lib/mpq.js before this exits, and every file
 * is compared byte for byte. That is the only check there is short of the
 * client itself.
 */
const fs = require('fs');
const path = require('path');
const { Archive, hashString, encrypt } = require('./lib/mpq.js');

const BACKSLASH = String.fromCharCode(92);
const FLAG_EXISTS = 0x80000000;
const HEADER_SIZE = 32;

const args = process.argv.slice(2);
if (args.length < 2) {
    console.error(fs.readFileSync(__filename, 'utf8').split('*/')[0].replace(/^\/\*\n?/, '').replace(/^ \* ?/gm, ''));
    process.exit(1);
}

const out = args[0];
const files = args.slice(1).map(a => {
    const eq = a.indexOf('=');
    if (eq < 1) throw new Error('expected <archive path>=<local file>, got ' + a);
    return { name: a.slice(0, eq).split('/').join(BACKSLASH), data: fs.readFileSync(a.slice(eq + 1)) };
});
files.push({ name: '(listfile)', data: Buffer.from(files.map(f => f.name).join('\r\n') + '\r\n') });

// A power of two with room to spare, since a probe chain ends at the first
// empty slot.
let hashCount = 16;
while (hashCount < files.length * 2) hashCount *= 2;

// Layout: header, file data, hash table, block table.
let pos = HEADER_SIZE;
const block = Buffer.alloc(files.length * 16);
files.forEach((f, i) => {
    block.writeUInt32LE(pos, i * 16);
    block.writeUInt32LE(f.data.length, i * 16 + 4);
    block.writeUInt32LE(f.data.length, i * 16 + 8);
    block.writeUInt32LE(FLAG_EXISTS, i * 16 + 12);
    f.pos = pos;
    pos += f.data.length;
});

const hash = Buffer.alloc(hashCount * 16, 0xFF);
files.forEach((f, i) => {
    let slot = hashString(f.name, 0) % hashCount;
    while (hash.readUInt32LE(slot * 16 + 12) !== 0xFFFFFFFF) slot = (slot + 1) % hashCount;
    const e = slot * 16;
    hash.writeUInt32LE(hashString(f.name, 1), e);
    hash.writeUInt32LE(hashString(f.name, 2), e + 4);
    hash.writeUInt16LE(0, e + 8);               // locale: neutral
    hash.writeUInt16LE(0, e + 10);              // platform
    hash.writeUInt32LE(i, e + 12);
});

const hashPos = pos;
const blockPos = hashPos + hash.length;
const size = blockPos + block.length;

encrypt(hash, hashString('(hash table)', 3));
encrypt(block, hashString('(block table)', 3));

const header = Buffer.alloc(HEADER_SIZE);
header.writeUInt32LE(0x1A51504D, 0);            // 'MPQ\x1A'
header.writeUInt32LE(HEADER_SIZE, 4);
header.writeUInt32LE(size, 8);
header.writeUInt16LE(0, 0x0C);                  // format version 0
header.writeUInt16LE(3, 0x0E);                  // sector size 512 << 3
header.writeUInt32LE(hashPos, 0x10);
header.writeUInt32LE(blockPos, 0x14);
header.writeUInt32LE(hashCount, 0x18);
header.writeUInt32LE(files.length, 0x1C);

fs.writeFileSync(out, Buffer.concat([header, ...files.map(f => f.data), hash, block]));

const check = new Archive(out);
for (const f of files) {
    const got = check.read(f.name);
    if (!got || !got.equals(f.data)) {
        console.error('READ BACK FAILED: ' + f.name);
        process.exit(1);
    }
}
fs.closeSync(check.fd);
console.log('wrote ' + path.resolve(out) + '  ' + size + ' bytes, ' + files.length + ' files, read back ok');
