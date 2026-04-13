"use strict";

const fs = require("fs");
const path = require("path");

const WATCH = [
    ["clk", /^tb_professional\.clk$/, "clock", "Clock / Reset"],
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

const DEFAULT_INPUT = path.join(__dirname, "..", "sim", "intelli_safe_arc_test.vcd");
const DEFAULT_OUTPUT = path.join(__dirname, "output", "flow_visualizer_v1.html");

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
    if (!Number.isFinite(out.start) || !Number.isFinite(out.end) || out.end < out.start) {
        throw new Error("Khoang thoi gian khong hop le.");
    }
    return out;
}

function help() {
    console.log("node script/flow_visualizer_v1.js [--input file.vcd] [--output file.html] [--start ps] [--end ps]");
    process.exit(0);
}

function ensureDir(dir) { fs.mkdirSync(dir, { recursive: true }); }

function fmtPs(ps) {
    if (ps >= 1e9) return (ps / 1e9).toFixed(3) + " ms";
    if (ps >= 1e6) return (ps / 1e6).toFixed(3) + " us";
    if (ps >= 1e3) return (ps / 1e3).toFixed(3) + " ns";
    return String(ps) + " ps";
}

function refName(tokens) {
    return tokens.slice(4, -1).join(" ").replace(/\s+\[/g, "[").trim();
}

function parseNum(value) {
    return /^[01]+$/.test(value) ? parseInt(value, 2) : null;
}

function labelValue(kind, value) {
    if (value == null) return "-";
    if (kind === "vector") {
        const num = parseNum(value);
        return num == null ? value : "0x" + num.toString(16).toUpperCase();
    }
    return value;
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
                watched.push({ key, id, full, kind, group, changes: [] });
                break;
            }
        }
    }
    const map = new Map(watched.map((s) => [s.id, s]));
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
        const last = sig.changes[sig.changes.length - 1];
        if (!last || last.value !== value) sig.changes.push({ time: now, value });
    }
    return { timescale, signals: watched, maxTime };
}

function at(sig, time) {
    if (!sig || !sig.changes.length) return null;
    let best = sig.changes[0];
    for (const item of sig.changes) {
        if (item.time > time) break;
        best = item;
    }
    return best;
}

function inRange(sig, start, end) {
    const out = [];
    const prev = at(sig, start);
    if (prev) out.push({ time: start, value: prev.value, synthetic: true });
    for (const item of sig.changes) {
        if (item.time < start) continue;
        if (item.time > end) break;
        out.push(item);
    }
    return out;
}

function events(signals, start, end) {
    const byKey = Object.fromEntries(signals.map((s) => [s.key, s]));
    const out = [];
    const pushEdge = (key, from, to, title, detail, block, sev) => {
        const sig = byKey[key];
        if (!sig) return;
        for (let i = 1; i < sig.changes.length; i += 1) {
            const a = sig.changes[i - 1];
            const b = sig.changes[i];
            if (b.time < start || b.time > end) continue;
            if (a.value === from && b.value === to) out.push({ time: b.time, title, detail, block, sev });
        }
    };
    pushEdge("rst_ni", "0", "1", "Reset released", "He thong bat dau chay.", "Clock / Reset", "info");
    pushEdge("adc_csn", "1", "0", "SPI frame start", "Frontend bat dau lay mau.", "SPI / ADC", "info");
    pushEdge("adc_csn", "0", "1", "SPI frame end", "Frontend ket thuc frame.", "SPI / ADC", "info");
    pushEdge("spi_data_rdy", "0", "1", "SPI sample ready", "Bridge co sample moi.", "SPI / ADC", "good");
    pushEdge("spi_sample_sticky", "0", "1", "Bridge sample latched", "Sample da duoc latch noi bo.", "SPI / ADC", "info");
    pushEdge("arc_irq", "0", "1", "Arc IRQ asserted", "DSP phat hien ho quang.", "DSP", "danger");
    pushEdge("relay_gpio", "0", "1", "Relay trip", "GPIO relay len 1, cat dien.", "Relay / GPIO", "danger");
    pushEdge("wdt_reset", "0", "1", "Watchdog reset", "Watchdog kich reset.", "Watchdog", "danger");
    pushEdge("bist_done", "0", "1", "BIST done", "BIST hoan tat.", "BIST", "good");

    const pc = byKey.cpu_pc;
    if (pc) {
        for (const item of pc.changes) {
            if (item.time < start || item.time > end) continue;
            const num = parseNum(item.value);
            if (num === 0x01 || num === 0x03 || num === 0x08 || num === 0x09) {
                out.push({ time: item.time, title: "CPU PC -> " + labelValue("vector", item.value), detail: "CPU doi vector/trang thai quan trong.", block: "CPU / APB", sev: num === 0x03 ? "danger" : "info" });
            }
        }
    }

    const integ = byKey.dsp_integrator;
    if (integ) {
        const marks = new Set();
        for (const item of integ.changes) {
            if (item.time < start || item.time > end) continue;
            const num = parseNum(item.value);
            if (num == null) continue;
            for (const mark of [100, 500, 1000]) {
                if (num >= mark && !marks.has(mark)) {
                    marks.add(mark);
                    out.push({ time: item.time, title: "Integrator >= " + mark, detail: "Gia tri tich luy DSP da vuot moc " + mark + ".", block: "DSP", sev: mark === 1000 ? "danger" : "info" });
                }
            }
        }
    }

    out.sort((a, b) => a.time - b.time || a.title.localeCompare(b.title));
    return out;
}

function blockStats(signals, ev, start, end) {
    const groups = {};
    for (const sig of signals) {
        const items = inRange(sig, start, end);
        if (!groups[sig.group]) groups[sig.group] = { changes: 0, danger: false };
        groups[sig.group].changes += Math.max(0, items.length - 1);
    }
    for (const e of ev) {
        if (!groups[e.block]) groups[e.block] = { changes: 0, danger: false };
        if (e.sev === "danger") groups[e.block].danger = true;
    }
    return groups;
}

function clockMeta(sig) {
    if (!sig || sig.changes.length < 4) return null;
    const ds = [];
    for (let i = 1; i < Math.min(sig.changes.length, 12); i += 1) ds.push(sig.changes[i].time - sig.changes[i - 1].time);
    const half = ds.reduce((a, b) => a + b, 0) / ds.length;
    return { half, period: half * 2 };
}

function svgTiming(signals, start, end) {
    const width = 980;
    const rowH = 34;
    const rows = signals.filter((s) => s.key !== "clk");
    let y = 30;
    const span = Math.max(1, end - start);
    const xOf = (t) => 210 + ((t - start) / span) * width;
    const parts = [`<svg viewBox="0 0 1220 ${rows.length * rowH + 50}" width="1220" height="${rows.length * rowH + 50}" xmlns="http://www.w3.org/2000/svg">`];
    parts.push(`<line x1="210" y1="18" x2="${210 + width}" y2="18" stroke="#b8a98f"/>`);
    for (let i = 0; i <= 8; i += 1) {
        const x = 210 + (width * i) / 8;
        const t = Math.round(start + ((end - start) * i) / 8);
        parts.push(`<line x1="${x}" y1="18" x2="${x}" y2="${rows.length * rowH + 40}" stroke="#eee0c9"/>`);
        parts.push(`<text x="${x + 2}" y="12" font-size="11" fill="#5b6670">${fmtPs(t)}</text>`);
    }
    for (const sig of rows) {
        parts.push(`<text x="10" y="${y + 15}" font-size="12" fill="#223" font-family="Consolas, monospace">${sig.key}</text>`);
        const items = inRange(sig, start, end);
        if (items.length > 2500) {
            parts.push(`<text x="220" y="${y + 15}" font-size="12" fill="#8b5e1a">Zoom in de nhin ro hon.</text>`);
            y += rowH;
            continue;
        }
        if (sig.kind === "digital") {
            let d = "";
            const level = (v) => (v === "1" ? y + 6 : y + 24);
            const first = items[0] || { time: start, value: "0" };
            d += `M ${xOf(start)} ${level(first.value)}`;
            let prev = first;
            for (let i = 1; i < items.length; i += 1) {
                const cur = items[i];
                const x = xOf(cur.time);
                d += ` L ${x} ${level(prev.value)} L ${x} ${level(cur.value)}`;
                prev = cur;
            }
            d += ` L ${xOf(end)} ${level(prev.value)}`;
            parts.push(`<path d="${d}" fill="none" stroke="#0b7285" stroke-width="1.6"/>`);
        } else {
            parts.push(`<line x1="210" y1="${y + 16}" x2="${210 + width}" y2="${y + 16}" stroke="#0b7285"/>`);
            for (const item of items.slice(0, 60)) {
                const x = xOf(item.time);
                const val = labelValue("vector", item.value);
                parts.push(`<line x1="${x}" y1="${y + 6}" x2="${x}" y2="${y + 26}" stroke="#f08c00"/>`);
                parts.push(`<text x="${x + 3}" y="${y + 12}" font-size="10" fill="#7a4f00">${val}</text>`);
            }
        }
        y += rowH;
    }
    parts.push("</svg>");
    return parts.join("");
}

function html(file, start, end, data, ev) {
    const clk = data.signals.find((s) => s.key === "clk");
    const cmeta = clockMeta(clk);
    const stats = blockStats(data.signals, ev, start, end);
    const cards = [
        ["Source", path.basename(file)],
        ["Timescale", data.timescale],
        ["Window", fmtPs(start) + " -> " + fmtPs(end)],
        ["Event count", String(ev.length)],
        ["Clock period", cmeta ? fmtPs(Math.round(cmeta.period)) : "unknown"]
    ];
    const cardsHtml = cards.map(([k, v]) => `<div class="card"><div class="k">${k}</div><div class="v">${v}</div></div>`).join("");
    const blocksHtml = Object.keys(stats).map((k) => {
        const cls = stats[k].danger ? "block danger" : (stats[k].changes > 0 ? "block active" : "block");
        return `<div class="${cls}"><div class="bt">${k}</div><div class="bm">Changes in window: ${stats[k].changes}</div></div>`;
    }).join("");
    const signalHtml = data.signals.map((s) => `<div class="sig"><b>${s.key}</b><br><span>${s.full}</span></div>`).join("");
    const eventRows = ev.map((e) => `<tr><td>${fmtPs(e.time)}</td><td class="${e.sev}">${e.sev.toUpperCase()}</td><td>${e.block}</td><td>${e.title}</td><td>${e.detail}</td></tr>`).join("");
    const explain = [
        `Cua so nay dang xem ${fmtPs(start)} den ${fmtPs(end)}.`,
        `Ban nen doc theo thu tu: Reset -> SPI frame -> Sample ready -> DSP IRQ -> CPU PC -> Relay/Watchdog/BIST.`,
        `Neu adc_sclk hoac clock qua day, hay giam window va chay lai script voi start/end hep hon.`
    ].join(" ");
    return `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>In_SOC Flow Visualizer V1</title>
<style>
body{margin:0;font-family:Segoe UI,Tahoma,sans-serif;background:linear-gradient(180deg,#f3ecdf,#ece2cf);color:#1f2933}
.page{max-width:1480px;margin:0 auto;padding:24px}.panel{background:#fffaf2;border:1px solid #dccfb7;border-radius:18px;padding:18px;box-shadow:0 16px 32px rgba(90,65,31,.08);margin-bottom:18px}
h1,h2{margin:0 0 10px}.muted{color:#5b6670;line-height:1.55}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:10px}.card{border:1px solid #e2d6c0;border-radius:12px;padding:12px;background:#fffdf8}.k{font-size:12px;color:#5b6670;text-transform:uppercase}.v{font-size:18px;font-weight:700;margin-top:6px}
.blocks,.signals{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px}.block,.sig{border:1px solid #e2d6c0;border-radius:14px;padding:12px;background:#f2e8d5}.block.active{background:#dceef8}.block.danger{background:#ffd9d9}.bt{font-weight:700;margin-bottom:6px}.bm{color:#5b6670;font-size:13px}.sig span{font-family:Consolas,monospace;font-size:12px;color:#5b6670;word-break:break-all}
table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:10px 12px;border-bottom:1px solid #eadfcb;vertical-align:top}th{background:#f8f1e3}.good{color:#2b8a3e;font-weight:700}.info{color:#0b7285;font-weight:700}.danger{color:#c92a2a;font-weight:700}.timing{overflow:auto;border:1px solid #e2d6c0;border-radius:12px;background:#fffdf9;padding:10px}
</style></head><body><div class="page">
<div class="panel"><h1>In_SOC Flow Visualizer V1</h1><div class="muted">V1 doc VCD that cua du an va xuat ra timing + event + overview theo khoang thoi gian ban chon.</div><div class="muted">${explain}</div></div>
<div class="panel"><h2>Summary</h2><div class="cards">${cardsHtml}</div></div>
<div class="panel"><h2>Block Overview</h2><div class="blocks">${blocksHtml}</div></div>
<div class="panel"><h2>Timing Diagram</h2><div class="timing">${svgTiming(data.signals, start, end)}</div></div>
<div class="panel"><h2>Event Timeline</h2><table><thead><tr><th>Time</th><th>Severity</th><th>Block</th><th>Event</th><th>Detail</th></tr></thead><tbody>${eventRows || `<tr><td colspan="5">Khong co event nao trong cua so nay.</td></tr>`}</tbody></table></div>
<div class="panel"><h2>Signal Map</h2><div class="signals">${signalHtml}</div></div>
</div></body></html>`;
}

function main() {
    const a = args();
    if (!fs.existsSync(a.input)) throw new Error("Khong tim thay VCD input.");
    const data = parseVcd(a.input);
    const start = Math.max(0, a.start);
    const end = Math.min(data.maxTime, a.end);
    const ev = events(data.signals, start, end);
    ensureDir(path.dirname(a.output));
    fs.writeFileSync(a.output, html(a.input, start, end, data, ev), "utf8");
    console.log("Flow Visualizer V1 da tao xong.");
    console.log("Input : " + a.input);
    console.log("Output: " + a.output);
    console.log("Range : " + start + " -> " + end + " ps");
    console.log("Events: " + ev.length);
}

try { main(); } catch (e) { console.error("[flow_visualizer_v1] Loi:", e.message); process.exit(1); }
