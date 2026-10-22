// Build the custom 64x64 TGA addon icon and package QuillAndHearth into a release zip.
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const ROOT = path.resolve(import.meta.dirname, "..");
const ADDON_DIR = path.join(ROOT, "addon", "QuillAndHearth");
const ICON_PATH = path.join(ADDON_DIR, "Media", "Icon.tga");
const DIST_DIR = path.join(ROOT, "dist");

// ---------------------------------------------------------------------------
// 1. Generate 64x64 32-bit uncompressed TGA icon (Quill & Hearth emblem)
// ---------------------------------------------------------------------------
function clamp(v, lo = 0, hi = 255) {
    return Math.max(lo, Math.min(hi, Math.round(v)));
}

function mix(a, b, t) {
    return a + (b - a) * Math.max(0, Math.min(1, t));
}

function generateIconTga(filePath) {
    const W = 64, H = 64;
    const header = Buffer.alloc(18, 0);
    header[2] = 2;             // uncompressed true-color image
    header.writeUInt16LE(W, 12);
    header.writeUInt16LE(H, 14);
    header[16] = 32;           // 32 bits per pixel (BGRA)
    header[17] = 0x28;         // top-left origin + 8-bit alpha

    const pixels = Buffer.alloc(W * H * 4);

    for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
            const nx = (x + 0.5) / W; // 0..1 left to right
            const ny = (y + 0.5) / H; // 0..1 top to bottom

            // Background: deep warm leather/mahogany with hearthfire glow from bottom center
            const fireDist = Math.hypot(nx - 0.48, (ny - 0.78) * 1.15);
            const fireGlow = Math.max(0, 1 - fireDist * 1.75);
            let r = mix(28, 225, Math.pow(fireGlow, 1.35));
            let g = mix(16, 105, Math.pow(fireGlow, 1.8));
            let b = mix(12, 28, Math.pow(fireGlow, 2.4));

            // Subtle hearth flame tongues near bottom-left/center
            const flameWave = Math.sin(nx * 22) * 0.03 + Math.cos(nx * 35) * 0.02;
            const flameDist = Math.hypot((nx - 0.44) * 1.3, ny - (0.76 + flameWave));
            if (flameDist < 0.22) {
                const ft = Math.pow(1 - flameDist / 0.22, 1.5);
                r = mix(r, 255, ft * 0.85);
                g = mix(g, 195, ft * 0.75);
                b = mix(b, 65, ft * 0.55);
            }

            // Open journal pages silhouette at the bottom (y: 0.66..0.86, x: 0.16..0.84)
            const bx = nx - 0.5;
            const pageArch = 0.77 + Math.abs(bx) * 0.08 - Math.pow(bx * 2.2, 2) * 0.06;
            const inBook = Math.abs(bx) < 0.33 && ny > pageArch - 0.09 && ny < pageArch + 0.05;
            if (inBook) {
                const spine = Math.exp(-Math.pow(bx / 0.03, 2));
                r = mix(232, 120, spine * 0.65);
                g = mix(205, 82, spine * 0.65);
                b = mix(152, 42, spine * 0.65);
            }

            // Diagonal quill feather from bottom-left (0.24, 0.78) to top-right (0.80, 0.16)
            // Coordinate along shaft u (0=tip, 1=top feather) and perpendicular v
            const dx = nx - 0.24;
            const dy = 0.78 - ny;
            const len = Math.hypot(0.56, 0.62);
            const u = (dx * 0.56 + dy * 0.62) / (len * len);
            const v = (dx * -0.62 + dy * 0.56) / len;

            // Quill shaft (bright gold/ivory line)
            if (u >= 0 && u <= 1.0) {
                const shaftHalf = 0.014 + (1 - u) * 0.004;
                const dShaft = Math.abs(v);
                if (dShaft < shaftHalf + 0.012) {
                    const st = 1 - Math.max(0, (dShaft - shaftHalf) / 0.012);
                    r = mix(r, 252, st);
                    g = mix(g, 232, st);
                    b = mix(b, 175, st);
                }

                // Feather barbs (u in 0.25..0.98)
                if (u > 0.24 && u < 0.98) {
                    const t = (u - 0.24) / 0.74; // 0..1 along the vane
                    const widthL = Math.sin(Math.pow(t, 0.75) * Math.PI) * 0.145;
                    const widthR = Math.sin(Math.pow(t, 0.8) * Math.PI) * 0.095;
                    const maxW = v >= 0 ? widthL : widthR;
                    const av = Math.abs(v);
                    // Small notch splits in the vane for a real feather look
                    const notch = (Math.abs(u - 0.52) < 0.018 && v > 0.04) || (Math.abs(u - 0.71) < 0.015 && v < -0.03);
                    if (!notch && av < maxW) {
                        const edge = 1 - Math.pow(av / Math.max(0.001, maxW), 2.2);
                        const barb = 0.9 + 0.1 * Math.sin((u * 90 - av * 45));
                        const goldShade = mix(0.78, 1.0, t);
                        r = mix(r, 248 * barb * goldShade, edge * 0.92);
                        g = mix(g, 214 * barb * goldShade, edge * 0.92);
                        b = mix(b, 138 * barb * goldShade, edge * 0.92);
                    }
                }
            }

            // Classic WoW icon border (outer dark rim + beveled gold frame)
            const edgeDist = Math.min(x, y, W - 1 - x, H - 1 - y);
            if (edgeDist === 0 || edgeDist === 1) {
                r = 18; g = 14; b = 10;
            } else if (edgeDist >= 2 && edgeDist <= 4) {
                const light = (x + y < W) ? 1.22 : 0.72;
                const bevel = edgeDist === 3 ? 1.0 : 0.82;
                r = 168 * light * bevel;
                g = 132 * light * bevel;
                b = 64 * light * bevel;
            } else if (edgeDist === 5) {
                r *= 0.55; g *= 0.55; b *= 0.55;
            }

            const idx = (y * W + x) * 4;
            pixels[idx] = clamp(b);
            pixels[idx + 1] = clamp(g);
            pixels[idx + 2] = clamp(r);
            pixels[idx + 3] = 255;
        }
    }

    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, Buffer.concat([header, pixels]));
}

// ---------------------------------------------------------------------------
// 2. Minimal pure-Node ZIP writer (no external CLI dependency)
// ---------------------------------------------------------------------------
const CRC_TABLE = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    CRC_TABLE[n] = c >>> 0;
}

function crc32(buf) {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
}

function walkFiles(dir, prefix = "") {
    const out = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
        if (entry.isDirectory()) {
            out.push(...walkFiles(full, rel));
        } else {
            out.push({ full, rel });
        }
    }
    return out;
}

function buildZip(entries) {
    const localParts = [];
    const centralParts = [];
    let offset = 0;

    for (const { name, data } of entries) {
        const nameBuf = Buffer.from(name, "utf8");
        const crc = crc32(data);
        const compressed = zlib.deflateRawSync(data, { level: 9 });
        const useDeflate = compressed.length < data.length;
        const body = useDeflate ? compressed : data;
        const method = useDeflate ? 8 : 0;

        const local = Buffer.alloc(30 + nameBuf.length);
        local.writeUInt32LE(0x04034b50, 0);
        local.writeUInt16LE(20, 4);
        local.writeUInt16LE(0x0800, 6); // UTF-8 filename flag
        local.writeUInt16LE(method, 8);
        local.writeUInt16LE(0, 10);
        local.writeUInt16LE(0x554b, 12);
        local.writeUInt32LE(crc, 14);
        local.writeUInt32LE(body.length, 18);
        local.writeUInt32LE(data.length, 22);
        local.writeUInt16LE(nameBuf.length, 26);
        local.writeUInt16LE(0, 28);
        nameBuf.copy(local, 30);

        const central = Buffer.alloc(46 + nameBuf.length);
        central.writeUInt32LE(0x02014b50, 0);
        central.writeUInt16LE(20, 4);
        central.writeUInt16LE(20, 6);
        central.writeUInt16LE(0x0800, 8);
        central.writeUInt16LE(method, 10);
        central.writeUInt16LE(0, 12);
        central.writeUInt16LE(0x554b, 14);
        central.writeUInt32LE(crc, 16);
        central.writeUInt32LE(body.length, 20);
        central.writeUInt32LE(data.length, 24);
        central.writeUInt16LE(nameBuf.length, 28);
        central.writeUInt16LE(0, 30);
        central.writeUInt16LE(0, 32);
        central.writeUInt16LE(0, 34);
        central.writeUInt16LE(0, 36);
        central.writeUInt32LE(0, 38);
        central.writeUInt32LE(offset, 42);
        nameBuf.copy(central, 46);

        localParts.push(local, body);
        centralParts.push(central);
        offset += local.length + body.length;
    }

    const centralBuf = Buffer.concat(centralParts);
    const eocd = Buffer.alloc(22);
    eocd.writeUInt32LE(0x06054b50, 0);
    eocd.writeUInt16LE(0, 4);
    eocd.writeUInt16LE(0, 6);
    eocd.writeUInt16LE(entries.length, 8);
    eocd.writeUInt16LE(entries.length, 10);
    eocd.writeUInt32LE(centralBuf.length, 12);
    eocd.writeUInt32LE(offset, 16);
    eocd.writeUInt16LE(0, 20);

    return Buffer.concat([...localParts, centralBuf, eocd]);
}

generateIconTga(ICON_PATH);
console.log(`ok    generated ${path.relative(ROOT, ICON_PATH)}`);

const toc = fs.readFileSync(path.join(ADDON_DIR, "QuillAndHearth.toc"), "utf8");
const version = (toc.match(/^##\s*Version:\s*(.+)$/m)?.[1] || "dev").trim();

const files = walkFiles(ADDON_DIR, "QuillAndHearth");
const zipEntries = files.map((f) => ({ name: f.rel, data: fs.readFileSync(f.full) }));
fs.mkdirSync(DIST_DIR, { recursive: true });
const zipPath = path.join(DIST_DIR, `QuillAndHearth-v${version}.zip`);
fs.writeFileSync(zipPath, buildZip(zipEntries));
console.log(`ok    packaged ${files.length} files -> ${path.relative(ROOT, zipPath)}`);
