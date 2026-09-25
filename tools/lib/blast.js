/*
 * blast.js -- PKWARE DCL "implode" decompression, a port of zlib's contrib/blast.c.
 *
 * MPQ sectors can be zlib, PKWARE DCL, bzip2, LZMA or a couple of audio codecs.
 * Vanilla-era archives lean on DCL heavily, so without this the client archives
 * are unreadable in practice -- node has zlib built in and nothing else.
 *
 * The algorithm: a bit stream, LSB first, of literals and length/distance pairs.
 * Three fixed Huffman tables (literals, lengths, distances) are stored in a
 * compact run-length form -- each byte is (count-1) << 4 | bitLength -- which is
 * what construct() expands. Codes are read a bit at a time and INVERTED as they
 * are accumulated, which is the one part that looks wrong and is not.
 */

// The three fixed tables, verbatim from blast.c. There is nothing to derive
// here; they are part of the format.
const LITLEN = [11, 124, 8, 7, 28, 7, 188, 13, 76, 4, 10, 8, 12, 10, 12, 10, 8, 23, 8,
    9, 7, 6, 7, 8, 7, 6, 55, 8, 23, 24, 12, 11, 7, 9, 11, 12, 6, 7, 22, 5,
    7, 24, 6, 11, 9, 6, 7, 22, 7, 11, 38, 7, 9, 8, 25, 11, 8, 11, 9, 12,
    8, 12, 5, 38, 5, 38, 5, 11, 7, 5, 6, 21, 6, 10, 53, 8, 7, 24, 10, 27,
    44, 253, 253, 253, 252, 252, 252, 13, 12, 45, 12, 45, 12, 61, 12, 45, 44, 173];
const LENLEN = [2, 35, 36, 53, 38, 23];
const DISTLEN = [2, 20, 53, 230, 247, 151, 248];
const BASE = [3, 2, 4, 5, 6, 7, 8, 9, 10, 12, 16, 24, 40, 72, 136, 264];
const EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8];

function construct(rep) {
    const length = [];
    for (const r of rep) {
        const n = (r >> 4) + 1, l = r & 15;
        for (let i = 0; i < n; i++) length.push(l);
    }
    const count = new Array(17).fill(0);
    for (const l of length) count[l]++;
    const offs = new Array(17).fill(0);
    for (let len = 1; len < 16; len++) offs[len + 1] = offs[len] + count[len];
    const symbol = new Array(length.length);
    for (let s = 0; s < length.length; s++)
        if (length[s]) symbol[offs[length[s]]++] = s;
    return { count, symbol };
}

const LIT = construct(LITLEN), LEN = construct(LENLEN), DIST = construct(DISTLEN);

function explode(src) {
    let pos = 0, bitbuf = 0, bitcnt = 0;

    function bits(need) {
        let val = bitbuf;
        while (bitcnt < need) {
            if (pos >= src.length) throw new Error('blast: out of input');
            val |= src[pos++] << bitcnt;
            bitcnt += 8;
        }
        bitbuf = val >> need;
        bitcnt -= need;
        return val & ((1 << need) - 1);
    }

    function decode(h) {
        let code = 0, first = 0, index = 0;
        for (let len = 1; len <= 16; len++) {
            code |= bits(1) ^ 1;              // codes are stored inverted
            const count = h.count[len];
            if (code - first < count) return h.symbol[index + (code - first)];
            index += count;
            first = (first + count) << 1;
            code <<= 1;
        }
        throw new Error('blast: bad code');
    }

    const lit = bits(8);
    if (lit > 1) throw new Error('blast: bad literal flag ' + lit);
    const dict = bits(8);
    if (dict < 4 || dict > 6) throw new Error('blast: bad dictionary size ' + dict);

    const out = [];
    for (;;) {
        if (bits(1)) {
            const sym = decode(LEN);
            const len = BASE[sym] + bits(EXTRA[sym]);
            if (len === 519) break;                     // end of stream
            const nbits = len === 2 ? 2 : dict;
            const dist = (decode(DIST) << nbits) + bits(nbits) + 1;
            if (dist > out.length) throw new Error('blast: distance too far back');
            for (let i = 0; i < len; i++) out.push(out[out.length - dist]);
        } else {
            out.push(lit ? decode(LIT) : bits(8));
        }
    }
    return Buffer.from(out);
}

module.exports = { explode };
