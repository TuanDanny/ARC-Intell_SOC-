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
const DEFAULT_OUTPUT = path.join(__dirname, "output", "flow_visualizer_v2.html");

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

function html(bundle) {
    const payload = JSON.stringify(bundle).replace(/</g, "\\u003c").replace(/<\//g, "<\\/");
    return `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>In_SOC Flow Visualizer V2</title>
<link rel="stylesheet" href="../flow_visualizer_v2.css">
</head><body><div class="page">
<div class="panel"><h1>In_SOC Flow Visualizer V2</h1><div class="muted">V2 doc VCD that cua du an nhung cho phep ban zoom/thay doi cua so thoi gian ngay tren HTML, jump theo event, va xem block flow dang hoat dong tai moc hien tai.</div></div>
<div class="panel"><h2>Summary</h2><div id="summaryCards" class="cards"></div></div>
<div class="panel"><h2>Controls</h2><div class="controls">
<div><label for="startInput">Start (ps)</label><input id="startInput" type="number"></div>
<div><label for="endInput">End (ps)</label><input id="endInput" type="number"></div>
<div><label for="sizeSelect">Window Size</label><select id="sizeSelect"><option value="50000">50 ns</option><option value="200000">200 ns</option><option value="1000000">1 us</option><option value="5000000">5 us</option><option value="20000000">20 us</option><option value="100000000">100 us</option></select></div>
<div><label>&nbsp;</label><button id="applyRange">Apply Range</button></div>
<div><label>&nbsp;</label><button id="resetView">Back To Default</button></div>
</div>
<div class="range-row"><div><label for="centerSlider">Center Timeline</label><input id="centerSlider" type="range" min="0" max="1000" value="0"></div><div><label for="eventJump">Jump To Event</label><select id="eventJump"></select></div></div>
<div id="presetWrap" class="preset-wrap"></div><div id="explainBox" class="explain"></div></div>
<div class="panel"><h2>Block Flow</h2><div id="blockRow" class="blocks"></div></div>
<div class="panel grid"><div><h2>Timing Diagram</h2><div id="timing" class="timing"></div></div><div><h2>Signals Now</h2><div id="signalGrid" class="signal-grid"></div></div></div>
<div class="panel"><h2>Event Timeline In Window</h2><div class="table-wrap"><table><thead><tr><th>Time</th><th>Severity</th><th>Block</th><th>Event</th><th>Detail</th></tr></thead><tbody id="eventBody"></tbody></table></div></div>
</div><script>window.FLOW_VIZ_V2_DATA = ${payload};</script><script src="../flow_visualizer_v2_client.js"></script></body></html>`;
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
        events,
        signals: parsed.signals
    };
    ensureDir(path.dirname(a.output));
    fs.writeFileSync(a.output, html(bundle), "utf8");
    console.log("Flow Visualizer V2 da tao xong.");
    console.log("Input : " + a.input);
    console.log("Output: " + a.output);
    console.log("Default window: " + defaultStart + " -> " + defaultEnd + " ps");
    console.log("Signals: " + parsed.signals.length + ", events: " + events.length + ", anchors: " + bundle.anchors.length);
}

try { main(); } catch (e) { console.error("[flow_visualizer_v2] Loi:", e.message); process.exit(1); }


