"use strict";

const fs = require("fs");
const path = require("path");

const WATCH = [
    ["clk", /^tb_professional\.clk$/, "digital", "Clock / Reset"],
    ["rst_ni", /^tb_professional\.rst_ni$/, "digital", "Clock / Reset"],
    ["adc_csn", /^tb_professional\.adc_csn$/, "digital", "SPI / ADC"],
    ["adc_sclk", /^tb_professional\.adc_sclk$/, "digital", "SPI / ADC"],
    ["adc_miso", /^tb_professional\.adc_miso$/, "digital", "SPI / ADC"],
    ["adc_mosi", /^tb_professional\.adc_mosi$/, "digital", "SPI / ADC"],
    ["spi_data_rdy", /^tb_professional\.dut\.spi_data_rdy$/, "digital", "SPI / ADC"],
    ["spi_data_val", /^tb_professional\.dut\.spi_data_val\[15:0\]$/, "vector", "SPI / ADC"],
    ["spi_sample_sticky", /^tb_professional\.dut\.u_spi_bridge\.r_sample_valid_sticky$/, "digital", "SPI / ADC"],
    ["dsp_integrator", /^tb_professional\.dut\.u_dsp\.integrator\[15:0\]$/, "vector", "DSP"],
    ["arc_irq", /^tb_professional\.dut\.irq_arc_critical$/, "digital", "DSP"],
    ["cpu_pc", /^tb_professional\.dut\.u_cpu\.pc\[7:0\]$/, "vector", "CPU / APB"],
    ["relay_gpio", /^tb_professional\.gpio_io\[0\]$/, "digital", "Relay / GPIO"],
    ["wdt_reset", /^tb_professional\.dut\.u_wdt\.wdt_reset_o$/, "digital", "Watchdog"],
    ["bist_done", /^tb_professional\.dut\.u_bist\.r_done$/, "digital", "BIST"]
];

const BLOCK_ORDER = ["Clock / Reset", "SPI / ADC", "DSP", "CPU / APB", "Relay / GPIO", "Watchdog", "BIST"];
const SIGNAL_ORDER = ["clk", "rst_ni", "adc_csn", "adc_sclk", "adc_miso", "adc_mosi", "spi_data_rdy", "spi_data_val", "spi_sample_sticky", "dsp_integrator", "arc_irq", "cpu_pc", "relay_gpio", "wdt_reset", "bist_done"];

const DEFAULT_INPUT = path.join(__dirname, "..", "sim", "intelli_safe_arc_test.vcd");
const DEFAULT_OUTPUT = path.join(__dirname, "output", "flow_visualizer_v3.html");

function args() {
    const out = { input: DEFAULT_INPUT, output: DEFAULT_OUTPUT, start: 0, end: 4000000 };
    const a = process.argv.slice(2);
    for (let i = 0; i < a.length; i += 1) {
        if (a[i] === "--input" && a[i + 1]) out.input = path.resolve(a[++i]);
        else if (a[i] === "--output" && a[i + 1]) out.output = path.resolve(a[++i]);
        else if (a[i] === "--start" && a[i + 1]) out.start = Number(a[++i]);
        else if (a[i] === "--end" && a[i + 1]) out.end = Number(a[++i]);
        else if (a[i] === "--help" || a[i] === "-h") help();
    }
    if (!Number.isFinite(out.start) || !Number.isFinite(out.end) || out.end <= out.start) {
        throw new Error("Khoang thoi gian khoi tao khong hop le.");
    }
    return out;
}

function help() {
    console.log("node script/flow_visualizer_v2.js [--input file.vcd] [--output file.html] [--start ps] [--end ps]");
    process.exit(0);
}

function ensureDir(dir) { fs.mkdirSync(dir, { recursive: true }); }
function clamp(v, min, max) { return Math.max(min, Math.min(max, v)); }
function refName(tokens) { return tokens.slice(4, -1).join(" ").replace(/\s+\[/g, "[").trim(); }
function parseNum(value) { return /^[01]+$/.test(value) ? parseInt(value, 2) : null; }

function clockMeta(samples) {
    if (!samples || samples.length < 4) return null;
    const deltas = [];
    for (let i = 1; i < Math.min(samples.length, 16); i += 1) deltas.push(samples[i][0] - samples[i - 1][0]);
    const half = deltas.reduce((a, b) => a + b, 0) / deltas.length;
    return {
        firstTime: samples[0][0],
        firstValue: samples[0][1],
        half,
        period: half * 2
    };
}

function parseVcd(file) {
    const text = fs.readFileSync(file, "utf8");
    const lines = text.split(/\r?\n/);
    const scope = [];
    const ids = new Map();
    let timescale = "1ps";
    let idx = 0;

    for (; idx < lines.length; idx += 1) {
        const line = lines[idx].trim();
        if (!line) continue;
        if (line.startsWith("$timescale")) {
            if (lines[idx + 1] && !lines[idx + 1].trim().startsWith("$")) timescale = lines[idx + 1].trim();
        } else if (line.startsWith("$scope")) {
            scope.push(line.split(/\s+/)[2]);
        } else if (line.startsWith("$upscope")) {
            scope.pop();
        } else if (line.startsWith("$var")) {
            const t = line.split(/\s+/);
            ids.set(t[3], (scope.length ? scope.join(".") + "." : "") + refName(t));
        } else if (line.startsWith("$enddefinitions")) {
            idx += 1;
            break;
        }
    }

    const watched = [];
    for (const [key, re, kind, group] of WATCH) {
        for (const [id, full] of ids) {
            if (re.test(full)) {
                watched.push({ key, id, full, kind, group, changes: [], clockSamples: [], lastValue: null });
                break;
            }
        }
    }
    const map = new Map(watched.map((sig) => [sig.id, sig]));
    let now = 0;
    let maxTime = 0;

    for (; idx < lines.length; idx += 1) {
        const line = lines[idx].trim();
        if (!line) continue;
        if (line[0] === "#") {
            now = Number(line.slice(1));
            maxTime = now;
            continue;
        }
        if (line[0] === "$" || line[0] === "r" || line[0] === "R") continue;
        let value;
        let id;
        if (line[0] === "b" || line[0] === "B") {
            const p = line.split(/\s+/);
            value = p[0].slice(1).toLowerCase();
            id = p[1];
        } else {
            value = line[0].toLowerCase();
            id = line.slice(1).trim();
        }
        const sig = map.get(id);
        if (!sig) continue;
        if (sig.lastValue === value) continue;
        sig.lastValue = value;
        if (sig.key === "clk") {
            if (sig.clockSamples.length < 64) sig.clockSamples.push([now, value]);
            continue;
        }
        sig.changes.push([now, value]);
    }

    const clk = watched.find((sig) => sig.key === "clk");
    const meta = clockMeta(clk ? clk.clockSamples : null);
    const signals = watched.map((sig) => ({
        key: sig.key,
        full: sig.full,
        kind: sig.kind,
        group: sig.group,
        changes: sig.key === "clk" ? [] : sig.changes
    }));

    return { timescale, maxTime, signals, clockMeta: meta };
}

function pushEdge(out, sig, from, to, title, detail, block, sev) {
    if (!sig) return;
    for (let i = 1; i < sig.changes.length; i += 1) {
        const a = sig.changes[i - 1];
        const b = sig.changes[i];
        if (a[1] === from && b[1] === to) out.push({ time: b[0], title, detail, block, sev });
    }
}

function buildEvents(signals) {
    const byKey = Object.fromEntries(signals.map((sig) => [sig.key, sig]));
    const out = [];

    pushEdge(out, byKey.rst_ni, "0", "1", "Reset released", "He thong bat dau chay.", "Clock / Reset", "info");
    pushEdge(out, byKey.adc_csn, "1", "0", "SPI frame start", "Frontend bat dau lay mau.", "SPI / ADC", "info");
    pushEdge(out, byKey.adc_csn, "0", "1", "SPI frame end", "Frontend ket thuc frame.", "SPI / ADC", "info");
    pushEdge(out, byKey.spi_data_rdy, "0", "1", "SPI sample ready", "Bridge co sample moi.", "SPI / ADC", "good");
    pushEdge(out, byKey.spi_sample_sticky, "0", "1", "Bridge sample latched", "Sample da duoc latch noi bo.", "SPI / ADC", "info");
    pushEdge(out, byKey.arc_irq, "0", "1", "Arc IRQ asserted", "DSP phat hien ho quang.", "DSP", "danger");
    pushEdge(out, byKey.relay_gpio, "0", "1", "Relay trip", "GPIO relay len 1, cat dien.", "Relay / GPIO", "danger");
    pushEdge(out, byKey.wdt_reset, "0", "1", "Watchdog reset", "Watchdog kich reset.", "Watchdog", "danger");
    pushEdge(out, byKey.bist_done, "0", "1", "BIST done", "BIST hoan tat.", "BIST", "good");


    const integ = byKey.dsp_integrator;
    if (integ) {
        const levels = [100, 500, 1000];
        let prev = 0;
        for (const item of integ.changes) {
            const num = parseNum(item[1]);
            if (num == null) continue;
            for (const level of levels) {
                if (prev < level && num >= level) {
                    out.push({
                        time: item[0],
                        title: "Integrator >= " + level,
                        detail: "Gia tri tich luy DSP da vuot moc " + level + ".",
                        block: "DSP",
                        sev: level >= 1000 ? "danger" : "info"
                    });
                }
            }
            prev = num;
        }
    }

    out.sort((a, b) => a.time - b.time || a.title.localeCompare(b.title));
    return out;
}

function windowAround(time, span, maxTime) {
    const width = Math.min(span, Math.max(1, maxTime));
    const start = clamp(Math.round(time - (width / 2)), 0, Math.max(0, maxTime - width));
    return { start, end: start + width };
}

function firstEvent(events, title) {
    return events.find((item) => item.title === title) || null;
}

function buildAnchors(events) {
    const anchors = [];
    const add = (item) => {
        if (!item) return;
        if (anchors.some((entry) => entry.time === item.time && entry.title === item.title)) return;
        anchors.push(item);
    };

    ["Reset released", "SPI sample ready", "Arc IRQ asserted", "Relay trip", "Watchdog reset", "BIST done"].forEach((title) => add(firstEvent(events, title)));
    events.filter((item) => item.sev === "danger").slice(0, 12).forEach(add);
    events.filter((item) => item.title.startsWith("CPU PC ->")).slice(0, 12).forEach(add);
    anchors.sort((a, b) => a.time - b.time || a.title.localeCompare(b.title));
    return anchors.slice(0, 40);
}

function buildPresets(events, defaultStart, defaultEnd, maxTime) {
    const presets = [];
    const bootEnd = clamp(Math.max(defaultEnd, 4000000), 1, Math.max(1, maxTime));
    presets.push({ key: "boot", label: "Boot / Reset", start: 0, end: bootEnd, description: "Khoi dong, reset, va cac frame SPI dau tien." });

    const sample = firstEvent(events, "SPI sample ready");
    const arc = firstEvent(events, "Arc IRQ asserted");
    const relay = firstEvent(events, "Relay trip");
    const wdt = firstEvent(events, "Watchdog reset");
    const bist = firstEvent(events, "BIST done");

    if (sample) {
        const w = windowAround(sample.time, 600000, maxTime);
        presets.push({ key: "sample", label: "SPI Sample", start: w.start, end: w.end, description: "Tap trung vao mot frame SPI va sample ready." });
    }
    if (arc) {
        const w = windowAround(arc.time, 800000, maxTime);
        presets.push({ key: "arc", label: "Arc Detect", start: w.start, end: w.end, description: "DSP tang tich luy va assert arc IRQ." });
    }
    if (relay) {
        const w = windowAround(relay.time, 800000, maxTime);
        presets.push({ key: "relay", label: "Relay Trip", start: w.start, end: w.end, description: "Khoanh vung luc relay bi cat do su kien bao ve." });
    }
    if (wdt) {
        const w = windowAround(wdt.time, 1200000, maxTime);
        presets.push({ key: "watchdog", label: "Watchdog", start: w.start, end: w.end, description: "Theo doi luc watchdog reset xuat hien." });
    }
    if (bist) {
        const w = windowAround(bist.time, 1000000, maxTime);
        presets.push({ key: "bist", label: "BIST", start: w.start, end: w.end, description: "Xem moc BIST done va duong lien quan." });
    }
    return presets;
}

function stripComments(text) {
    return text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
}

function skipWs(text, idx) {
    while (idx < text.length && /\s/.test(text[idx])) idx += 1;
    return idx;
}

function isIdentStart(ch) {
    return !!ch && /[A-Za-z_]/.test(ch);
}

function isIdent(ch) {
    return !!ch && /[A-Za-z0-9_]/.test(ch);
}

function parseBalanced(text, openIdx) {
    const open = text[openIdx];
    const pairs = { '(': ')', '[': ']', '{': '}' };
    const close = pairs[open];
    if (!close) throw new Error("Ky tu mo khong hop le: " + open);
    let depth = 0;
    for (let i = openIdx; i < text.length; i += 1) {
        if (text[i] === open) depth += 1;
        else if (text[i] === close) {
            depth -= 1;
            if (depth === 0) return { content: text.slice(openIdx + 1, i), end: i };
        }
    }
    throw new Error("Khong tim thay dau dong cho cap ngoac " + open);
}

function splitTopLevel(text, delim) {
    const out = [];
    let start = 0;
    let paren = 0;
    let square = 0;
    let brace = 0;
    for (let i = 0; i < text.length; i += 1) {
        const ch = text[i];
        if (ch === '(') paren += 1;
        else if (ch === ')') paren -= 1;
        else if (ch === '[') square += 1;
        else if (ch === ']') square -= 1;
        else if (ch === '{') brace += 1;
        else if (ch === '}') brace -= 1;
        else if (ch === delim && paren === 0 && square === 0 && brace === 0) {
            out.push(text.slice(start, i));
            start = i + 1;
        }
    }
    out.push(text.slice(start));
    return out;
}

function extractLastIdentifier(text) {
    const m = text.match(/([A-Za-z_][A-Za-z0-9_]*)\s*(\[[^\]]+\])*\s*$/);
    return m ? m[1] : null;
}

function parsePortList(text) {
    const parts = splitTopLevel(text, ',');
    const ports = [];
    let inherit = null;
    for (const raw of parts) {
        const item = raw.replace(/\s+/g, ' ').trim();
        if (!item) continue;
        const dm = item.match(/^(input|output|inout|ref)\b\s*(.*)$/);
        let direction = dm ? dm[1] : null;
        let rest = dm ? dm[2].trim() : item;
        const name = extractLastIdentifier(rest);
        if (!name) continue;
        const nameIdx = rest.lastIndexOf(name);
        let type = rest.slice(0, nameIdx).trim();
        if (!direction) {
            if (/^[A-Za-z_][A-Za-z0-9_]*(\s*\[[^\]]+\])*$/i.test(rest) && inherit) {
                direction = inherit.direction;
                type = inherit.type;
            } else {
                direction = 'interface';
                type = type || rest.slice(0, nameIdx).trim();
                inherit = null;
            }
        } else {
            inherit = { direction, type };
        }
        ports.push({ name, direction, type: type || '' });
    }
    return ports;
}

function parseModuleDefs(rootDir) {
    const files = [];
    function walk(dir) {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) walk(full);
            else if (entry.isFile() && entry.name.endsWith('.sv')) files.push(full);
        }
    }
    walk(rootDir);

    const defs = new Map();
    for (const file of files) {
        const text = stripComments(fs.readFileSync(file, 'utf8'));
        let search = 0;
        while (search < text.length) {
            const modRe = /\bmodule\s+([A-Za-z_][A-Za-z0-9_]*)\b/g;
            modRe.lastIndex = search;
            const hit = modRe.exec(text);
            if (!hit) break;
            const name = hit[1];
            let idx = skipWs(text, hit.index + hit[0].length);
            if (text[idx] === '#') {
                idx = text.indexOf('(', idx);
                if (idx < 0) break;
                idx = skipWs(text, parseBalanced(text, idx).end + 1);
            }
            if (text[idx] !== '(') {
                search = hit.index + hit[0].length;
                continue;
            }
            const ports = parseBalanced(text, idx);
            const endmodule = text.indexOf('endmodule', ports.end + 1);
            defs.set(name, {
                name,
                file,
                ports: parsePortList(ports.content),
                bodyText: endmodule >= 0 ? text.slice(ports.end + 1, endmodule) : ''
            });
            search = endmodule >= 0 ? endmodule + 'endmodule'.length : ports.end + 1;
        }
    }
    return defs;
}

function parseNamedConnections(text) {
    const out = [];
    for (const raw of splitTopLevel(text, ',')) {
        const item = raw.trim();
        if (!item || item === '.*') continue;
        const m = item.match(/^\.([A-Za-z_][A-Za-z0-9_]*)\s*\(([\s\S]*)\)$/);
        if (m) out.push({ port: m[1], expr: m[2].trim() });
    }
    return out;
}

function parseInstances(bodyText) {
    const out = [];
    const keywords = new Set(['if', 'for', 'while', 'case', 'assign', 'always_ff', 'always_comb', 'always', 'logic', 'wire', 'reg', 'parameter', 'localparam', 'begin', 'end', 'else', 'generate', 'endgenerate']);
    let i = 0;
    while (i < bodyText.length) {
        if (!isIdentStart(bodyText[i])) {
            i += 1;
            continue;
        }
        const firstStart = i;
        i += 1;
        while (i < bodyText.length && isIdent(bodyText[i])) i += 1;
        const moduleName = bodyText.slice(firstStart, i);
        if (keywords.has(moduleName)) continue;
        let j = skipWs(bodyText, i);
        if (bodyText[j] === '#') {
            const open = bodyText.indexOf('(', j);
            if (open < 0) continue;
            j = skipWs(bodyText, parseBalanced(bodyText, open).end + 1);
        }
        if (!isIdentStart(bodyText[j])) continue;
        const secondStart = j;
        j += 1;
        while (j < bodyText.length && isIdent(bodyText[j])) j += 1;
        const instanceName = bodyText.slice(secondStart, j);
        j = skipWs(bodyText, j);
        if (bodyText[j] !== '(') continue;
        const ports = parseBalanced(bodyText, j);
        j = skipWs(bodyText, ports.end + 1);
        if (bodyText[j] !== ';') continue;
        out.push({ moduleName, instanceName, connections: parseNamedConnections(ports.content) });
        i = j + 1;
    }
    return out;
}

function parseAssigns(bodyText) {
    const out = [];
    const re = /\bassign\s+([^=;]+?)\s*=\s*([^;]+);/g;
    let m;
    while ((m = re.exec(bodyText))) {
        out.push({ lhs: m[1].trim(), rhs: m[2].trim() });
    }
    return out;
}

function classifyNode(moduleName, instanceName) {
    const key = (moduleName + ' ' + instanceName).toLowerCase();
    if (instanceName === 'top_io') return 'Top I/O';
    if (/rst|watchdog|wdt/.test(key)) return 'Infrastructure';
    if (/apb_node|apb_bus/.test(key)) return 'Interconnect';
    if (/cpu/.test(key)) return 'CPU / Control';
    if (/spi|dsp|bist/.test(key)) return 'Signal Path';
    if (/gpio|uart|timer/.test(key)) return 'Peripherals';
    return 'Other';
}

function groupPorts(ports) {
    const out = { input: [], output: [], inout: [], interface: [], ref: [], unknown: [] };
    for (const port of ports || []) {
        const dir = out[port.direction] ? port.direction : 'unknown';
        out[dir].push(port);
    }
    return out;
}

function previewLines(groups) {
    const lines = [];
    if (groups.input.length) lines.push('IN: ' + groups.input.slice(0, 4).map((p) => p.name).join(', ') + (groups.input.length > 4 ? ' ...' : ''));
    if (groups.output.length) lines.push('OUT: ' + groups.output.slice(0, 4).map((p) => p.name).join(', ') + (groups.output.length > 4 ? ' ...' : ''));
    if (groups.inout.length) lines.push('IO: ' + groups.inout.slice(0, 4).map((p) => p.name).join(', ') + (groups.inout.length > 4 ? ' ...' : ''));
    if (groups.interface.length) lines.push('IF: ' + groups.interface.slice(0, 3).map((p) => p.name).join(', ') + (groups.interface.length > 3 ? ' ...' : ''));
    return lines;
}

function simpleSignal(expr) {
    const trimmed = expr.trim();
    if (/^[A-Za-z_][A-Za-z0-9_]*(\[[^\]]+\])*$/i.test(trimmed)) return trimmed;
    const iface = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)\.[A-Za-z_][A-Za-z0-9_]*(\[[^\]]+\])*$/);
    return iface ? iface[1] : null;
}

function normalizeSignal(signal) {
    const m = signal.match(/^([A-Za-z_][A-Za-z0-9_]*)(\[[^\]]+\])+$/);
    if (!m) return signal;
    const base = m[1];
    return /^(s_paddr|s_pwdata|s_prdata|s_psel|s_penable|s_pwrite|s_pready|s_pslverr|start_addr|end_addr)$/.test(base) ? base : signal;
}

function endpointFlow(endpoint) {
    const dir = endpoint.direction;
    if (endpoint.node === 'top_io') {
        if (dir === 'input') return 'source';
        if (dir === 'output') return 'sink';
        return 'both';
    }
    if (dir === 'output') return 'source';
    if (dir === 'input') return 'sink';
    return 'both';
}

function makePairs(endpoints) {
    const sources = endpoints.filter((ep) => endpointFlow(ep) === 'source' || endpointFlow(ep) === 'both');
    const sinks = endpoints.filter((ep) => endpointFlow(ep) === 'sink' || endpointFlow(ep) === 'both');
    const out = [];
    if (sources.length && sinks.length) {
        for (const src of sources) {
            for (const dst of sinks) {
                if (src.node !== dst.node) out.push([src, dst]);
            }
        }
    } else if (endpoints.length > 1) {
        for (let i = 1; i < endpoints.length; i += 1) {
            if (endpoints[0].node !== endpoints[i].node) out.push([endpoints[0], endpoints[i]]);
        }
    }
    return out;
}

function countMatches(text, regex) {
    const hit = text.match(regex);
    return hit ? hit.length : 0;
}

function buildModulePrinciple(def) {
    const ports = def ? (def.ports || []) : [];
    const body = def ? (def.bodyText || '') : '';
    const alwaysFF = countMatches(body, /\balways_ff\b/g);
    const alwaysComb = countMatches(body, /\balways_comb\b/g);
    const alwaysAny = countMatches(body, /\balways\b/g);
    const assignCount = countMatches(body, /\bassign\b/g);
    const caseCount = countMatches(body, /\bcase\b/g);
    const instanceCount = body ? parseInstances(body).length : 0;
    const notes = [];

    if (alwaysFF) notes.push(`${alwaysFF} khoi always_ff giu trang thai / thanh ghi chinh cua block.`);
    if (alwaysComb) notes.push(`${alwaysComb} khoi always_comb tao logic to hop ho tro duong du lieu va dieu khien.`);
    if (!alwaysComb && alwaysAny) notes.push(`${alwaysAny} khoi always kieu tong quat duoc dung trong module nay.`);
    if (assignCount) notes.push(`${assignCount} lenh assign dung de glue signal hoac tao wiring combinational don gian.`);
    if (caseCount) notes.push(`${caseCount} cau truc case cho thay block co giai ma hoac state / mux logic.`);
    if (instanceCount) notes.push(`${instanceCount} instance con duoc ghep vao trong block nay.`);
    if (!notes.length) notes.push('Module nay chu yeu la giao tiep, wrapper, hoac wiring don gian nen code rat gon.');

    return {
        inputCount: ports.filter((port) => port.direction === 'input').length,
        outputCount: ports.filter((port) => port.direction === 'output').length,
        inoutCount: ports.filter((port) => port.direction === 'inout').length,
        interfaceCount: ports.filter((port) => port.direction === 'interface').length,
        alwaysFF,
        alwaysComb,
        alwaysAny,
        assignCount,
        caseCount,
        instanceCount,
        notes
    };
}
function buildArchitecture() {
    const rtlRoot = path.join(__dirname, '..', 'rtl');
    const defs = parseModuleDefs(rtlRoot);
    const topDef = defs.get('top_soc');
    if (!topDef) throw new Error('Khong parse duoc module top_soc de tao so do V3.');

    const instances = parseInstances(topDef.bodyText);
    const topGroups = groupPorts(topDef.ports);
    const fileCache = new Map();
    const readSourceText = (file) => {
        if (!file) return '';
        if (!fileCache.has(file)) fileCache.set(file, fs.readFileSync(file, 'utf8'));
        return fileCache.get(file);
    };
    const nodes = [{
        id: 'top_io',
        instance: 'top_io',
        label: 'top_soc I/O',
        module: 'top_soc',
        group: 'Top I/O',
        ports: topDef.ports,
        preview: previewLines(topGroups),
        sourceFile: topDef.file,
        sourceText: readSourceText(topDef.file),
        rtlPrinciple: buildModulePrinciple(topDef)
    }];

    for (const inst of instances) {
        const def = defs.get(inst.moduleName);
        const ports = def ? def.ports : (inst.moduleName === 'APB_BUS' ? [{ name: 'if', direction: 'interface', type: 'APB_BUS' }] : inst.connections.map((conn) => ({ name: conn.port, direction: 'unknown', type: '' })));
        const groups = groupPorts(ports);
        nodes.push({
            id: inst.instanceName,
            instance: inst.instanceName,
            label: inst.instanceName,
            module: inst.moduleName,
            group: classifyNode(inst.moduleName, inst.instanceName),
            ports,
            preview: previewLines(groups),
            sourceFile: def ? def.file : '',
            sourceText: def ? readSourceText(def.file) : '',
            rtlPrinciple: def ? buildModulePrinciple(def) : null
        });
    }

    const nodeMap = new Map(nodes.map((node) => [node.id, node]));
    const signalMap = new Map();
    function addSignal(signal, endpoint) {
        if (!signalMap.has(signal)) signalMap.set(signal, []);
        signalMap.get(signal).push(endpoint);
    }

    topDef.ports.forEach((port) => addSignal(port.name, {
        node: 'top_io',
        module: 'top_soc',
        port: port.name,
        direction: port.direction,
        type: port.type
    }));

    for (const inst of instances) {
        const node = nodeMap.get(inst.instanceName);
        if (inst.moduleName === 'APB_BUS') {
            addSignal(inst.instanceName, {
                node: inst.instanceName,
                module: inst.moduleName,
                port: 'if',
                direction: 'interface',
                type: 'APB_BUS'
            });
        }
        const portMap = new Map((node.ports || []).map((port) => [port.name, port]));
        for (const conn of inst.connections) {
            const net = simpleSignal(conn.expr);
            if (!net) continue;
            const norm = normalizeSignal(net);
            const port = portMap.get(conn.port);
            addSignal(norm, {
                node: inst.instanceName,
                module: inst.moduleName,
                port: conn.port,
                direction: port ? port.direction : 'unknown',
                type: port ? port.type : ''
            });
        }
    }

    const connections = Array.from(signalMap.entries()).map(([signal, endpoints]) => ({
        signal,
        endpoints: endpoints.sort((a, b) => a.node.localeCompare(b.node) || a.port.localeCompare(b.port))
    })).sort((a, b) => a.signal.localeCompare(b.signal));

    const pairMap = new Map();
    for (const conn of connections) {
        for (const [src, dst] of makePairs(conn.endpoints)) {
            const key = src.node + '->' + dst.node;
            if (!pairMap.has(key)) pairMap.set(key, { from: src.node, to: dst.node, signals: [] });
            pairMap.get(key).signals.push(conn.signal);
        }
    }

    function summarizeEdgeSignals(signals) {
        const tags = [];
        const add = (tag) => { if (!tags.includes(tag)) tags.push(tag); };
        if (signals.some((sig) => sig === 'clk_i')) add('clk');
        if (signals.some((sig) => /rst/i.test(sig))) add('reset');
        if (signals.some((sig) => /^adc_/.test(sig) || /^spi_/.test(sig))) add('SPI/ADC');
        if (signals.some((sig) => /^uart_/.test(sig))) add('UART');
        if (signals.some((sig) => /^gpio/.test(sig))) add('GPIO');
        if (signals.some((sig) => /^apb_/.test(sig) || /^(s_paddr|s_pwdata|s_prdata|s_psel|s_penable|s_pwrite|s_pready|s_pslverr|start_addr|end_addr)$/.test(sig))) add('APB');
        if (signals.some((sig) => /dsp_data_in|dsp_valid_in|sample_data|sample_valid|spi_data_val|spi_data_rdy/i.test(sig))) add('sample');
        if (signals.some((sig) => /arc|irq_arc|dsp_irq/i.test(sig))) add('arc irq');
        if (signals.some((sig) => /irq_timer|timer_events/i.test(sig))) add('timer irq');
        if (signals.some((sig) => /wdt/i.test(sig))) add('watchdog');
        if (signals.some((sig) => /bist/i.test(sig))) add('BIST');
        if (!tags.length) add(signals[0]);
        const head = tags.slice(0, 2).join(' + ');
        const extra = tags.length > 2 ? ' +' + (tags.length - 2) : '';
        return head + extra;
    }

    const edgeScore = (edge) => edge.signals.reduce((score, sig) => score + (/(adc_|uart_|gpio|irq|bist|spi_|dsp_|wdt|apb_|s_p|start_addr|end_addr)/i.test(sig) ? 4 : (/(clk|rst)/i.test(sig) ? 1 : 2)), 0);
    const diagramEdges = Array.from(pairMap.values()).map((edge) => ({
        from: edge.from,
        to: edge.to,
        signals: Array.from(new Set(edge.signals)).sort(),
        score: edgeScore(edge)
    })).filter((edge) => {
        const onlyClockish = edge.signals.every((sig) => sig === 'clk_i' || /^rst/.test(sig));
        return !onlyClockish;
    }).sort((a, b) => b.score - a.score || a.from.localeCompare(b.from) || a.to.localeCompare(b.to)).slice(0, 20).map((edge) => ({
        from: edge.from,
        to: edge.to,
        signalCount: edge.signals.length,
        label: summarizeEdgeSignals(edge.signals),
        signals: edge.signals
    }));

    return {
        groupOrder: ['Top I/O', 'Infrastructure', 'CPU / Control', 'Interconnect', 'Signal Path', 'Peripherals', 'Other'],
        topFile: path.join(rtlRoot, 'top_soc.sv'),
        nodes: nodes.filter((node) => node.group !== 'Other' || node.id === 'top_io' || node.ports.length),
        connections,
        diagramEdges,
        glue: parseAssigns(topDef.bodyText)
    };
}

function html(bundle) {
    const payload = JSON.stringify(bundle).replace(/</g, "\\u003c").replace(/<\//g, "<\\/");
    const assetVersion = Date.now();
    return `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>In_SOC Flow Visualizer V3</title>
<link rel="stylesheet" href="../flow_visualizer_v3.css?v=${assetVersion}">
</head><body><div class="page">
<div class="panel"><h1>In_SOC Flow Visualizer V3</h1><div class="muted">V3 ket hop 2 lop thong tin: waveform/time-flow tu V2 va so do khoi kien truc duoc trich tu RTL that cua du an. Muc tieu la de ban nhin nhanh block nao co trong top_soc, port nao duoc khai bao, va chung noi voi nhau qua nhung net nao.</div></div>
<div class="panel"><h2>Summary</h2><div id="summaryCards" class="cards"></div></div>
<div class="panel"><h2>Architecture Diagram</h2><div class="muted">So do nay duoc tao tu top-level [top_soc] va danh sach instance/port trong RTL. Tool nay khong con tu ve day noi giua cac block nua; no giu lai block + chan + nut chon chan. Ban bam vao tung chan de xem cac endpoint cung net roi tu doi chieu va cau day theo y minh. Double-click vao so do de mo fullscreen playground, tu noi day va xem code RTL cua tung khoi.</div><div class="arch-toolbar" id="archToolbar"><div class="arch-mode-group"><button id="archViewFull" type="button" class="arch-mode-btn">Full RTL</button><button id="archViewPresentation" type="button" class="arch-mode-btn secondary">Presentation</button><button id="archOpenFullscreen" type="button" class="arch-mode-btn secondary">Fullscreen</button></div><label class="arch-check"><input id="archShowDirect" type="checkbox" checked> Direct hints</label><label class="arch-check"><input id="archShowClockReset" type="checkbox" checked> Clock/Reset</label><label class="arch-check"><input id="archShowApb" type="checkbox" checked> APB detail</label><label class="arch-check"><input id="archShowIo" type="checkbox" checked> Board I/O</label><label class="arch-check"><input id="archShowGlueSummary" type="checkbox" checked> Glue summary</label></div><div id="archStatus" class="arch-status"></div><div id="archGlueSummary" class="arch-glue-summary"></div><div id="archOverview" class="arch-overview"></div><div id="archPinInfo" class="arch-pin-info"></div></div>
<div class="panel"><h2>Module Port Catalog</h2><div id="moduleCatalog" class="module-catalog"></div></div>
<div class="panel"><h2>Connection Catalog</h2><div class="table-wrap connection-wrap"><table><thead><tr><th>Signal</th><th>Status</th><th>Endpoints</th></tr></thead><tbody id="connectionBody"></tbody></table></div></div>
<div class="panel"><h2>Internal Glue / Assign</h2><div id="glueList" class="glue-list"></div></div>
<div class="panel"><h2>Controls</h2><div class="controls">
<div><label for="startInput">Start (ps)</label><input id="startInput" type="number"></div>
<div><label for="endInput">End (ps)</label><input id="endInput" type="number"></div>
<div><label for="sizeSelect">Window Size</label><select id="sizeSelect"><option value="50000">50 ns</option><option value="200000">200 ns</option><option value="1000000">1 us</option><option value="5000000">5 us</option><option value="20000000">20 us</option><option value="100000000">100 us</option></select></div>
<div><label>&nbsp;</label><button id="applyRange">Apply Range</button></div>
<div><label>&nbsp;</label><button id="resetView">Back To Default</button></div>
</div>
<div class="range-row"><div><label for="centerSlider">Center Timeline</label><input id="centerSlider" type="range" min="0" max="1000" value="0"></div><div><label for="eventJump">Jump To Event</label><select id="eventJump"></select></div></div>
<div id="presetWrap" class="preset-wrap"></div><div id="explainBox" class="explain"></div></div>
<div class="panel"><h2>Live Block Flow</h2><div id="blockRow" class="blocks"></div></div>
<div class="panel grid"><div><h2>Timing Diagram</h2><div id="timing" class="timing"></div></div><div><h2>Signals Now</h2><div id="signalGrid" class="signal-grid"></div></div></div>
<div class="panel"><h2>Event Timeline In Window</h2><div class="table-wrap"><table><thead><tr><th>Time</th><th>Severity</th><th>Block</th><th>Event</th><th>Detail</th></tr></thead><tbody id="eventBody"></tbody></table></div></div>
<div id="archFullscreenModal" class="arch-modal" hidden>
  <div class="arch-modal-shell">
    <div class="arch-modal-header">
      <div>
        <div class="arch-modal-title">Architecture Wiring Playground</div>
        <div class="arch-modal-sub">Double-click tu so do chinh de vao day. Bam 2 chan lien tiep de thu noi day. Tool chi ve wire khi hai chan dung cung mot net trong RTL.</div>
      </div>
      <div class="arch-modal-actions">
        <button id="archResetWires" type="button" class="arch-modal-btn secondary">Xoa Day</button>
        <button id="archCloseModal" type="button" class="arch-modal-btn">Dong</button>
      </div>
    </div>
    <div class="arch-modal-body">
      <div class="arch-modal-canvas"><div id="archModalOverview" class="arch-overview arch-overview-modal"></div></div>
      <div class="arch-modal-side">
        <div id="archWirePanel" class="arch-wire-panel"></div>
        <div id="archModalPinInfo" class="arch-pin-info arch-pin-info-modal"></div>
      </div>
    </div>
  </div>
</div>
<div id="archCodeModal" class="arch-code-modal" hidden>
  <div class="arch-code-shell">
    <div class="arch-code-header">
      <div>
        <div class="arch-code-title" id="archCodeTitle">Xem nguyen ly code de thiet ke khoi nay</div>
        <div class="arch-code-meta" id="archCodeMeta"></div>
      </div>
      <button id="archCloseCode" type="button" class="arch-modal-btn">Dong</button>
    </div>
    <div class="arch-code-body">
      <div class="arch-code-facts" id="archCodeFacts"></div>
      <div class="arch-code-notes" id="archCodeNotes"></div>
      <pre class="arch-code-source" id="archCodeSource"></pre>
    </div>
  </div>
</div></div><script>window.FLOW_VIZ_V3_DATA = ${payload};</script><script src="../flow_visualizer_v3_client.js?v=${assetVersion}"></script></body></html>`;
}

function main() {
    const a = args();
    if (!fs.existsSync(a.input)) throw new Error("Khong tim thay VCD input.");
    const parsed = parseVcd(a.input);
    const defaultStart = clamp(Math.round(a.start), 0, Math.max(0, parsed.maxTime - 1));
    const defaultEnd = clamp(Math.round(a.end), defaultStart + 1, parsed.maxTime);
    const events = buildEvents(parsed.signals);
    const bundle = {
        meta: {
            sourceName: path.basename(a.input),
            timescale: parsed.timescale,
            maxTime: parsed.maxTime,
            defaultStart,
            defaultEnd,
            blockOrder: BLOCK_ORDER,
            signalOrder: SIGNAL_ORDER,
            clockMeta: parsed.clockMeta
        },
        presets: buildPresets(events, defaultStart, defaultEnd, parsed.maxTime),
        anchors: buildAnchors(events),
        architecture: buildArchitecture(),
        events,
        signals: parsed.signals
    };
    ensureDir(path.dirname(a.output));
    fs.writeFileSync(a.output, html(bundle), 'utf8');
    console.log('Flow Visualizer V3 da tao xong.');
    console.log('Input : ' + a.input);
    console.log('Output: ' + a.output);
    console.log('Default window: ' + defaultStart + ' -> ' + defaultEnd + ' ps');
    console.log('Signals: ' + parsed.signals.length + ', events: ' + events.length + ', modules: ' + bundle.architecture.nodes.length + ', nets: ' + bundle.architecture.connections.length);
}

try { main(); } catch (e) { console.error('[flow_visualizer_v3] Loi:', e.message); process.exit(1); }










