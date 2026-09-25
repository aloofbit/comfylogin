/*
 * mpq.js -- read one MPQ archive.
 *
 * Enough of the format to pull named files out of a 1.12 client: header, the
 * two encrypted tables, and sector decompression. Not a general MPQ library --
 * no listfile enumeration, no encrypted files. Writing is ../pack.js, which
 * uses encrypt() from here.
 *
 * Enumeration is not needed here because every asset we want is named by a DBC
 * (GameObjectDisplayInfo gives the model path), so lookups are always by exact
 * name. That is what makes a ~200 line reader sufficient.
 *
 * Verified against ground truth: extracting DBFilesClient/Map.dbc and diffing
 * against server/dbc/Map.dbc -- which the core's own C++ extractor produced --
 * gives identical headers and 6 differing bytes in 24,700, one field of one
 * record, i.e. real content drift since that extraction rather than a decode
 * fault.
 */
const fs = require('fs');
const zlib = require('zlib');
const { explode } = require('./blast.js');

const BACKSLASH = String.fromCharCode(92);

// MPQ's key schedule. Every table and filename hash comes out of this.
const cryptTable = new Uint32Array(0x500);
(function () {
    let seed = 0x00100001;
    for (let i1 = 0; i1 < 0x100; i1++) {
        for (let i2 = i1, i = 0; i < 5; i++, i2 += 0x100) {
            seed = (seed * 125 + 3) % 0x2AAAAB;
            const t1 = (seed & 0xFFFF) << 16;
            seed = (seed * 125 + 3) % 0x2AAAAB;
            cryptTable[i2] = ((t1 | (seed & 0xFFFF)) >>> 0);
        }
    }
})();

// type 0 = table offset, 1 = name A, 2 = name B, 3 = file key.
function hashString(str, type) {
    let s1 = 0x7FED7FED, s2 = 0xEEEEEEEE;
    str = str.toUpperCase();
    for (let i = 0; i < str.length; i++) {
        const ch = str.charCodeAt(i);
        s1 = (cryptTable[(type << 8) + ch] ^ ((s1 + s2) >>> 0)) >>> 0;
        s2 = (ch + s1 + s2 + ((s2 << 5) >>> 0) + 3) >>> 0;
    }
    return s1 >>> 0;
}

function decrypt(buf, key) {
    let s1 = key >>> 0, s2 = 0xEEEEEEEE;
    for (let i = 0; i + 4 <= buf.length; i += 4) {
        s2 = (s2 + cryptTable[0x400 + (s1 & 0xFF)]) >>> 0;
        const ch = (buf.readUInt32LE(i) ^ ((s1 + s2) >>> 0)) >>> 0;
        buf.writeUInt32LE(ch, i);
        s1 = ((((~s1) << 0x15) + 0x11111111) | (s1 >>> 0x0B)) >>> 0;
        s2 = (ch + s2 + ((s2 << 5) >>> 0) + 3) >>> 0;
    }
}

// The inverse of decrypt, for pack.js. Same key schedule, but the plaintext
// word feeds the next key rather than the ciphertext.
function encrypt(buf, key) {
    let s1 = key >>> 0, s2 = 0xEEEEEEEE;
    for (let i = 0; i + 4 <= buf.length; i += 4) {
        s2 = (s2 + cryptTable[0x400 + (s1 & 0xFF)]) >>> 0;
        const ch = buf.readUInt32LE(i);
        buf.writeUInt32LE((ch ^ ((s1 + s2) >>> 0)) >>> 0, i);
        s1 = ((((~s1) << 0x15) + 0x11111111) | (s1 >>> 0x0B)) >>> 0;
        s2 = (ch + s2 + ((s2 << 5) >>> 0) + 3) >>> 0;
    }
}

const FLAG_EXISTS = 0x80000000;
const FLAG_COMPRESS = 0x00000100;
const FLAG_IMPLODE = 0x00000200;
const FLAG_ENCRYPTED = 0x00010000;
const FLAG_SINGLE_UNIT = 0x01000000;
const FLAG_DELETED = 0x02000000;

class Archive {
    constructor(filePath) {
        this.path = filePath;
        this.fd = fs.openSync(filePath, 'r');
        const size = fs.fstatSync(this.fd).size;

        // The header is 512-byte aligned but not always at offset 0 -- some
        // archives carry an executable stub in front.
        let off = 0;
        const hdr = Buffer.alloc(32);
        for (; off < size; off += 512) {
            fs.readSync(this.fd, hdr, 0, 32, off);
            if (hdr.readUInt32LE(0) === 0x1A51504D) break;
        }
        if (off >= size) throw new Error('no MPQ header in ' + filePath);

        this.base = off;
        this.formatVersion = hdr.readUInt16LE(0x0C);
        this.sectorSize = 512 << hdr.readUInt16LE(0x0E);
        const hashPos = hdr.readUInt32LE(0x10), blockPos = hdr.readUInt32LE(0x14);
        this.hashCount = hdr.readUInt32LE(0x18);
        this.blockCount = hdr.readUInt32LE(0x1C);

        this.hash = Buffer.alloc(this.hashCount * 16);
        fs.readSync(this.fd, this.hash, 0, this.hash.length, this.base + hashPos);
        decrypt(this.hash, hashString('(hash table)', 3));

        this.block = Buffer.alloc(this.blockCount * 16);
        fs.readSync(this.fd, this.block, 0, this.block.length, this.base + blockPos);
        decrypt(this.block, hashString('(block table)', 3));
    }

    // Block index for a name, or -1. Names are case-insensitive; forward
    // slashes are accepted and converted, since every caller here has paths
    // out of a DBC and those use backslashes.
    find(name) {
        name = name.split('/').join(BACKSLASH);
        const start = hashString(name, 0) % this.hashCount;
        const a = hashString(name, 1), b = hashString(name, 2);
        for (let i = 0; i < this.hashCount; i++) {
            const e = ((start + i) % this.hashCount) * 16;
            const blockIndex = this.hash.readUInt32LE(e + 12);
            if (blockIndex === 0xFFFFFFFF) return -1;       // never used: stop probing
            if (this.hash.readUInt32LE(e) === a && this.hash.readUInt32LE(e + 4) === b)
                return blockIndex;
        }
        return -1;
    }

    has(name) { return this.find(name) >= 0; }

    // Buffer, or null when absent. Throws on a file this reader cannot handle,
    // so a caller that wants to skip those must catch.
    read(name, stats) {
        const bi = this.find(name);
        if (bi < 0 || bi >= this.blockCount) return null;

        const o = bi * 16;
        const filePos = this.block.readUInt32LE(o);
        const cSize = this.block.readUInt32LE(o + 4);
        const fSize = this.block.readUInt32LE(o + 8);
        const flags = this.block.readUInt32LE(o + 12);

        if (!(flags & FLAG_EXISTS)) return null;
        if (flags & FLAG_DELETED) return null;
        if (flags & FLAG_ENCRYPTED) throw new Error('encrypted file not supported: ' + name);
        if (stats) stats.flags = '0x' + flags.toString(16);

        const compressed = !!(flags & FLAG_COMPRESS);
        const imploded = !!(flags & FLAG_IMPLODE);

        const raw = Buffer.alloc(cSize);
        fs.readSync(this.fd, raw, 0, cSize, this.base + filePos);

        if (flags & FLAG_SINGLE_UNIT) return this.sector(raw, fSize, imploded, stats);
        if (!compressed && !imploded) return raw.subarray(0, fSize);

        // Compressed files open with a table of n+1 offsets delimiting each sector.
        const nSectors = Math.ceil(fSize / this.sectorSize);
        const table = [];
        for (let i = 0; i <= nSectors; i++) table.push(raw.readUInt32LE(i * 4));

        const out = Buffer.alloc(fSize);
        let w = 0;
        for (let i = 0; i < nSectors; i++) {
            const want = Math.min(this.sectorSize, fSize - w);
            const dec = this.sector(raw.subarray(table[i], table[i + 1]), want, imploded, stats);
            dec.copy(out, w);
            w += dec.length;
        }
        return out;
    }

    sector(chunk, want, imploded, stats) {
        // A sector that did not get smaller is stored verbatim, with no mask byte.
        if (chunk.length >= want) return chunk.subarray(0, want);

        const mask = chunk[0];
        if (stats) stats.masks.add('0x' + mask.toString(16));
        const body = chunk.subarray(1);
        if (mask === 0x02) return zlib.inflateSync(body);
        if (mask === 0x08) return explode(body);
        if (mask === 0x10) throw new Error('bzip2 sector not supported');
        if (mask === 0x12) throw new Error('lzma sector not supported');

        // The IMPLODE flag is not trustworthy on its own: dbc.MPQ here sets it
        // on files whose sectors are ordinary mask-prefixed zlib. So the mask
        // byte wins, and a raw DCL stream (no mask byte) is only the fallback.
        if (imploded) {
            if (stats) stats.masks.add('raw-implode');
            return explode(chunk);
        }
        throw new Error('unknown compression mask 0x' + mask.toString(16));
    }
}

module.exports = { Archive, hashString, encrypt };
