// Checks that docs/cpu.html matches the RTL. Plain Node (>= 12), no packages.
//
//   node check_docs.js <cpu.html> <rtl dir> [controlunit dump]
//
// 1. Every entity in the page model has exactly the ports of rtl/<entity>.vhd (name, direction, width).
// 2. Every view's drawing is the real netlist: the RTL is flattened down to the blocks drawn in the view,
//    every drawn wire must connect pins that are on one RTL net, and every RTL connection must be drawn.
// 3. (with a dump) the page's JS copy of ControlUnit gives the same outputs as ControlUnit.vhd for every
//    opcode / funct3 / funct7 (and rs1 = 0 / 1 for SYSTEM).
'use strict';
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------- VHDL parsing (enough for this repo)
function stripComments(s) { return s.replace(/--.*$/gm, ''); }

function splitTop(s, sep) {
    const out = []; let depth = 0, cur = '';
    for (const c of s) {
        if (c === '(') depth++;
        if (c === ')') depth--;
        if (c === sep && depth === 0) { out.push(cur); cur = ''; } else cur += c;
    }
    if (cur.trim()) out.push(cur);
    return out;
}

function parseEntity(src) {
    const m = /entity\s+(\w+)\s+is\s*(?:generic\s*\(((?:[^()]|\([^()]*\))*)\)\s*;\s*)?port\s*\(([\s\S]*?)\)\s*;\s*end/i.exec(src);
    if (!m) return null;
    const ports = [];
    for (const decl of splitTop(m[3], ';')) {
        const d = /^\s*([\w\s,]+?)\s*:\s*(in|out|inout)?\s*([\s\S]*)$/i.exec(decl);
        if (!d) continue;
        const v = /vector\s*\(\s*(\d+)\s+downto\s+(\d+)\s*\)/i.exec(d[3]);
        const width = v ? Number(v[1]) - Number(v[2]) + 1 : 1;
        for (const n of d[1].split(',')) ports.push({ name: n.trim(), dir: (d[2] || 'in').toLowerCase(), width });
    }
    return { name: m[1], ports };
}

function parseArch(src) {
    const m = /architecture\s+\w+\s+of\s+(\w+)\s+is([\s\S]*?)\bbegin\b([\s\S]*)end\s+architecture/i.exec(src);
    if (!m) return { instances: [], assigns: [] };
    let body = m[3].replace(/\b\w+\s*:\s*process\b[\s\S]*?end\s+process[^;]*;/gi, '')
                   .replace(/\bprocess\b[\s\S]*?end\s+process[^;]*;/gi, '');
    const instances = [];
    const re = /(\w+)\s*:\s*entity\s+work\.(\w+)\s*(?:generic\s+map\s*\((?:[^()]|\([^()]*\))*\)\s*)?port\s+map\s*\(([\s\S]*?)\)\s*;/gi;
    let im;
    while ((im = re.exec(body))) {
        const assoc = {};
        for (const a of splitTop(im[3], ',')) {
            const p = /^\s*(\w+)\s*=>\s*([\s\S]+?)\s*$/.exec(a);
            if (p) assoc[p[1].toLowerCase()] = p[2];
        }
        instances.push({ label: im[1], entity: im[2], assoc });
    }
    body = body.replace(re, '');
    const assigns = [];
    const ar = /(\w+)\s*<=\s*([\s\S]*?);/g;
    let am;
    while ((am = ar.exec(body))) assigns.push({ lhs: am[1].toLowerCase(), rhs: am[2].trim() });
    return { instances, assigns };
}

// actual of a port map -> {sig} | {konst} | {open}
function actual(a) {
    const s = a.trim();
    if (/^open$/i.test(s)) return { open: true };
    const m = /^(\w+)\s*(\(.*\))?$/.exec(s);
    if (m && !/^(others)$/i.test(m[1])) return { sig: m[1].toLowerCase() };
    return { konst: s };
}

const KEYWORDS = new Set(['and', 'or', 'not', 'xor', 'nand', 'nor', 'when', 'else', 'others', 'downto', 'to', 'x']);
function rhsIdents(rhs) {
    const noStr = rhs.replace(/[xX]?"[^"]*"/g, ' ').replace(/'[^']'/g, ' ');
    const ids = new Set();
    for (const t of noStr.match(/[A-Za-z_]\w*/g) || []) if (!KEYWORDS.has(t.toLowerCase())) ids.add(t.toLowerCase());
    return [...ids];
}

function loadRtl(dir) {
    const ents = {};
    // rtl/ has subfolders (core/, core/datapath/, core/control/): walk them all
    const walk = d => fs.readdirSync(path.join(dir, d), { withFileTypes: true })
        .flatMap(x => x.isDirectory() ? walk(path.posix.join(d, x.name)) : [path.posix.join(d, x.name)]);
    for (const f of walk('')) {
        if (!f.endsWith('.vhd')) continue;
        const src = stripComments(fs.readFileSync(path.join(dir, f), 'utf8'));
        const e = parseEntity(src);
        if (!e) continue;
        ents[e.name.toLowerCase()] = { name: e.name, file: f, ports: e.ports, arch: parseArch(src) };
    }
    return ents;
}

// ---------------------------------------------------------------- union-find
function UF() { const p = {}; const find = k => { if (p[k] === undefined) p[k] = k; while (p[k] !== k) { p[k] = p[p[k]]; k = p[k]; } return k; };
    return { find, union: (a, b) => { const ra = find(a), rb = find(b); if (ra !== rb) p[ra] = rb; }, keys: () => Object.keys(p) }; }

// ---------------------------------------------------------------- checks
function checkEntities(model, rtl, err) {
    for (const [name, e] of Object.entries(model.entities)) {
        const r = rtl[name.toLowerCase()];
        if (!r) { err(`entity ${name}: no rtl/**/*.vhd defines it`); continue; }
        if (e.file !== 'rtl/' + r.file) err(`entity ${name}: model says ${e.file}, RTL is rtl/${r.file}`);
        const mp = {}; for (const [n, dir, w] of e.ports) mp[n.toLowerCase()] = { n, dir, w };
        const rp = {}; for (const p of r.ports) rp[p.name.toLowerCase()] = p;
        for (const k of Object.keys(rp)) {
            if (!mp[k]) err(`entity ${name}: port ${rp[k].name} is in the RTL but not in the model`);
            else if (mp[k].dir !== rp[k].dir || mp[k].w !== rp[k].width)
                err(`entity ${name}.${rp[k].name}: model ${mp[k].dir}/${mp[k].w} bit, RTL ${rp[k].dir}/${rp[k].width} bit`);
        }
        for (const k of Object.keys(mp)) if (!rp[k]) err(`entity ${name}: port ${mp[k].n} is in the model but not in the RTL`);
    }
}

function checkView(view, model, rtl, err) {
    const V = `view ${view.id}`;
    const uf = UF();
    const blocks = {};           // inst (lower) -> block
    const byId = {};
    for (const b of view.blocks) {
        byId[b.id] = b;
        if (b.inst) blocks[b.inst.toLowerCase()] = b;
    }
    const pinKey = (b, p) => `pin:${b.id}.${p.toLowerCase()}`;
    const rtlPins = new Set();   // pins the RTL connects to a signal
    const konstPins = new Set(), openPins = new Set();
    const seenInst = new Set();

    const root = rtl[view.entity.toLowerCase()];
    // boundary ports of the view's entity
    for (const b of view.blocks) if (b.port) {
        if (!root.ports.some(p => p.name.toLowerCase() === b.port.toLowerCase())) err(`${V}: port block ${b.id} -> ${b.port} is not a port of ${root.name}`);
        uf.union(pinKey(b, 'p'), `|${b.port.toLowerCase()}`); rtlPins.add(pinKey(b, 'p'));
    }
    for (const p of root.ports) if (!view.blocks.some(b => b.port && b.port.toLowerCase() === p.name.toLowerCase()))
        err(`${V}: port ${p.name} of ${root.name} is not drawn`);

    (function walk(pth, ent) {
        const arch = ent.arch;
        for (const inst of arch.instances) {
            const ip = (pth ? pth + '/' : '') + inst.label;
            const child = rtl[inst.entity.toLowerCase()];
            if (!child) { err(`${V}: ${ip}: unknown entity ${inst.entity}`); continue; }
            const blk = blocks[ip.toLowerCase()];
            if (blk) {
                seenInst.add(ip.toLowerCase());
                if (blk.entity.toLowerCase() !== inst.entity.toLowerCase()) err(`${V}: block ${blk.id} is ${blk.entity}, RTL instance ${ip} is ${inst.entity}`);
                for (const [formal, a] of Object.entries(inst.assoc)) {
                    const act = actual(a);
                    const k = pinKey(blk, formal);
                    if (act.sig) { uf.union(k, `${pth}|${act.sig}`); rtlPins.add(k); }
                    else if (act.konst) konstPins.add(k); else openPins.add(k);
                }
            } else if (child.arch.instances.length) {
                for (const [formal, a] of Object.entries(inst.assoc)) {
                    const act = actual(a);
                    if (act.sig) uf.union(`${ip}|${formal}`, `${pth}|${act.sig}`);
                }
                walk(ip, child);
            } else err(`${V}: RTL instance ${ip} (${inst.entity}) is not drawn`);
        }
        for (const as of arch.assigns) {
            if (/^\w+$/.test(as.rhs)) { uf.union(`${pth}|${as.lhs}`, `${pth}|${as.rhs.toLowerCase()}`); continue; }
            const id = `${pth}:${as.lhs}`;
            const blk = blocks[id.toLowerCase()];
            if (!blk) { err(`${V}: logic "${as.lhs} <= ${as.rhs.replace(/\s+/g, ' ')}" in ${pth || view.entity} is not drawn (expected a logic block with inst "${id}")`); continue; }
            seenInst.add(id.toLowerCase());
            const want = new Set([as.lhs, ...rhsIdents(as.rhs)]);
            const have = new Set(Object.keys(blk.pinDirs).map(s => s.toLowerCase()));
            for (const w of want) if (!have.has(w)) err(`${V}: logic block ${blk.id} misses pin ${w}`);
            for (const h of have) if (!want.has(h)) err(`${V}: logic block ${blk.id} has pin ${h}, not used by "${as.lhs} <= ..."`);
            for (const w of want) { uf.union(pinKey(blk, w), `${pth}|${w}`); rtlPins.add(pinKey(blk, w)); }
        }
    })('', root);

    for (const b of view.blocks) {
        if (b.inst && !seenInst.has(b.inst.toLowerCase())) err(`${V}: block ${b.id} (${b.inst}) does not exist in the RTL`);
        if (b.entity && !b.port) {
            const e = model.entities[b.entity];
            const drawn = new Set(Object.keys(b.pinDirs).map(s => s.toLowerCase()));
            for (const [n] of e.ports) if (!drawn.has(n.toLowerCase())) err(`${V}: block ${b.id} does not draw port ${n}`);
        }
    }

    // drawn wires
    const drawnPins = new Set();
    const refPin = (ref) => {
        const i = ref.lastIndexOf('.');
        const b = byId[ref.slice(0, i)];
        if (!b) { err(`${V}: wire endpoint ${ref}: no block ${ref.slice(0, i)}`); return null; }
        const p = ref.slice(i + 1);
        if (!Object.keys(b.pinDirs).some(x => x.toLowerCase() === p.toLowerCase())) { err(`${V}: wire endpoint ${ref}: block has no pin ${p}`); return null; }
        return pinKey(b, p);
    };
    for (const w of view.wires) {
        const pins = [];
        if (w.konst !== undefined) { const k = refPin(w.pin); if (k && !konstPins.has(k)) err(`${V}: ${w.pin} drawn as constant, RTL connects a signal`); if (k) drawnPins.add(k); continue; }
        if (w.open) { const k = refPin(w.pin); if (k && !openPins.has(k)) err(`${V}: ${w.pin} drawn as open, RTL connects it`); if (k) drawnPins.add(k); continue; }
        for (const r of wirePins(w)) { const k = refPin(r); if (k) pins.push([r, k]); }
        const roots = new Set(pins.map(([, k]) => uf.find(k)));
        if (roots.size > 1) err(`${V}: wire ${w.id} joins pins on different RTL nets: ${pins.map(([r, k]) => r + '~' + uf.find(k).replace(/^.*\|/, '')).join(', ')}`);
        for (const [r, k] of pins) { if (!rtlPins.has(k)) err(`${V}: wire ${w.id}: ${r} is not connected in the RTL`); drawnPins.add(k); }
    }
    // every RTL connection drawn: pins on a net with at least one other pin
    const groups = {};
    for (const k of rtlPins) (groups[uf.find(k)] = groups[uf.find(k)] || []).push(k);
    for (const g of Object.values(groups)) {
        if (g.length < 2) continue;
        for (const k of g) if (!drawnPins.has(k)) err(`${V}: ${k.slice(4)} is connected in the RTL (net ${uf.find(k).replace(/^.*\|/, '')}) but no wire is drawn to it`);
    }
    for (const k of konstPins) if (!drawnPins.has(k)) err(`${V}: constant input ${k.slice(4)} is not drawn`);
    for (const k of openPins) if (!drawnPins.has(k)) err(`${V}: open output ${k.slice(4)} is not drawn`);
}

function wirePins(w) {
    const out = [];
    for (const p of w.paths || []) for (const t of p) if (/^[A-Za-z_][\w]*\.[\w]+$/.test(t)) out.push(t);
    for (const t of w.pins || []) out.push(t);
    for (const t of w.stubs || []) out.push(t);
    return out;
}

function pinDirsOf(b, model) {
    const d = {};
    if (b.port) { d.p = 'x'; return d; }
    if (b.entity) for (const [n, dir] of model.entities[b.entity].ports) d[n] = dir;
    if (b.logic) { for (const n of b.logic.in) d[n] = 'in'; d[b.logic.out] = 'out'; }
    return d;
}

function checkDecoder(html, dumpFile, err) {
    const m = /<script id="decoder">([\s\S]*?)<\/script>/.exec(html);
    if (!m) { err('no <script id="decoder"> in the page'); return; }
    const mod = { exports: {} };
    new Function('module', m[1])(mod);
    const { controlUnit } = mod.exports;
    const order = [['RegWrite', 1], ['ASrc', 2], ['BSrc', 1], ['Illegal', 1], ['Branch', 1], ['ImmSrc', 3], ['Mem_Write', 1],
        ['Result_Src', 2], ['alu_control', 4], ['CSRwrite', 1], ['CSRop', 2], ['MRET', 1], ['JalrReg', 1], ['Jump', 1]];
    const lines = fs.readFileSync(dumpFile, 'utf8').split('\n').filter(Boolean);
    let bad = 0;
    for (const ln of lines) {
        const [op, f3, f7, rs1, bits] = ln.trim().split(/\s+/);
        const c = controlUnit(Number(op), Number(f3), Number(f7), Number(rs1));
        let js = '';
        for (const [n, w] of order) js += c[n].toString(2).padStart(w, '0');
        if (js !== bits) {
            if (bad++ < 10) err(`decoder: op=${op} f3=${f3} f7=${f7} rs1=${rs1}: VHDL ${bits}, JS ${js} (order ${order.map(o => o[0]).join(' ')})`);
        }
    }
    if (bad > 10) err(`decoder: ${bad} mismatches in total`);
    if (lines.length < 131072) err(`decoder: dump has only ${lines.length} lines`);
    return lines.length;
}

function main() {
    const [htmlFile, rtlDir, dump] = process.argv.slice(2);
    const html = fs.readFileSync(htmlFile, 'utf8');
    const mm = /<script type="application\/json" id="model">([\s\S]*?)<\/script>/.exec(html);
    const model = JSON.parse(mm[1]);
    const rtl = loadRtl(rtlDir);
    const errors = [];
    const err = s => errors.push(s);
    checkEntities(model, rtl, err);
    for (const v of model.views) {
        for (const b of v.blocks) b.pinDirs = pinDirsOf(b, model);
        checkView(v, model, rtl, err);
    }
    let n = 0;
    if (dump) n = checkDecoder(html, dump, err);
    if (errors.length) { for (const e of errors) console.log('  ' + e); console.log(`docs check: ${errors.length} problem(s)`); process.exit(1); }
    console.log(`docs check: ${Object.keys(model.entities).length} entities, ${model.views.length} views${dump ? `, ${n} decoder cases` : ''}: OK`);
}

if (require.main === module) main();
module.exports = { loadRtl };
