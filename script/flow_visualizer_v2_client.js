"use strict";

(function () {
const data = window.FLOW_VIZ_V2_DATA;
if (!data) return;

const byKey = Object.fromEntries(data.signals.map((sig) => [sig.key, sig]));
const els = {};
const state = {
    start: data.meta.defaultStart || 0,
    end: data.meta.defaultEnd || Math.min(data.meta.maxTime, 4000000)
};

function $(id) { return document.getElementById(id); }
function clamp(v, min, max) { return Math.max(min, Math.min(max, v)); }
function windowSize() { return Math.max(1, state.end - state.start); }

function fmtPs(ps) {
    if (ps >= 1e9) return (ps / 1e9).toFixed(3) + " ms";
    if (ps >= 1e6) return (ps / 1e6).toFixed(3) + " us";
    if (ps >= 1e3) return (ps / 1e3).toFixed(3) + " ns";
    return String(ps) + " ps";
}

function parseNum(value) {
    return typeof value === "string" && /^[01]+$/.test(value) ? parseInt(value, 2) : null;
}

function labelValue(kind, value) {
    if (value == null) return "-";
    if (kind === "vector") {
        const num = parseNum(value);
        return num == null ? value : "0x" + num.toString(16).toUpperCase();
    }
    return value;
}

function lowerBound(list, target) {
    let lo = 0;
    let hi = list.length;
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (list[mid][0] < target) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}

function upperBound(list, target) {
    let lo = 0;
    let hi = list.length;
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (list[mid][0] <= target) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}

function clockValueAt(time) {
    const meta = data.meta.clockMeta;
    if (!meta) return null;
    if (time <= meta.firstTime) return meta.firstValue;
    const steps = Math.floor((time - meta.firstTime) / meta.half);
    return steps % 2 === 0 ? meta.firstValue : (meta.firstValue === "1" ? "0" : "1");
}

function valueAt(sig, time) {
    if (!sig) return null;
    if (sig.key === "clk") return clockValueAt(time);
    const list = sig.changes || [];
    if (!list.length) return null;
    const idx = upperBound(list, time) - 1;
    if (idx < 0) return list[0][1];
    return list[idx][1];
}

function clockChangesInRange(start, end, maxPoints) {
    const meta = data.meta.clockMeta;
    if (!meta) return [];
    const count = Math.ceil((end - start) / meta.half) + 3;
    if (maxPoints && count > maxPoints) return null;
    const out = [[start, clockValueAt(start), true]];
    let t = meta.firstTime;
    if (t < start) {
        const steps = Math.floor((start - meta.firstTime) / meta.half) + 1;
        t = meta.firstTime + (steps * meta.half);
    }
    for (; t <= end; t += meta.half) out.push([t, clockValueAt(t)]);
    return out;
}

function changesInRange(sig, start, end, maxPoints) {
    if (!sig) return [];
    if (sig.key === "clk") return clockChangesInRange(start, end, maxPoints);
    const list = sig.changes || [];
    if (!list.length) return [];
    const out = [];
    const firstIdx = lowerBound(list, start);
    const prev = list[Math.max(0, firstIdx - 1)] || list[0];
    if (prev) out.push([start, prev[1], true]);
    for (let i = firstIdx; i < list.length && list[i][0] <= end; i += 1) {
        out.push(list[i]);
        if (maxPoints && out.length > maxPoints) return null;
    }
    return out;
}

function eventsInWindow(start, end) {
    const out = [];
    const list = data.events || [];
    for (let i = 0; i < list.length; i += 1) {
        const item = list[i];
        if (item.time < start) continue;
        if (item.time > end) break;
        out.push(item);
    }
    return out;
}

function setWindow(start, end) {
    const maxTime = Math.max(1, data.meta.maxTime);
    const span = clamp(Math.round(end - start), 1, maxTime);
    let newStart = Math.round(start);
    if (newStart < 0) newStart = 0;
    if (newStart + span > maxTime) newStart = maxTime - span;
    state.start = clamp(newStart, 0, Math.max(0, maxTime - 1));
    state.end = clamp(state.start + span, state.start + 1, maxTime);
    renderAll();
}

function setCenter(center) {
    const span = windowSize();
    setWindow(center - (span / 2), center + (span / 2));
}

function blockClass(active, danger) {
    if (danger) return "block danger";
    return active ? "block active" : "block";
}

function signalValue(key) {
    const sig = byKey[key];
    return labelValue(sig ? sig.kind : "digital", valueAt(sig, state.end));
}

function syncControls() {
    const center = (state.start + state.end) / 2;
    const maxTime = Math.max(1, data.meta.maxTime);
    els.startInput.value = String(state.start);
    els.endInput.value = String(state.end);
    els.centerSlider.value = String(Math.round((center / maxTime) * 1000));
}

function renderSummary() {
    const cards = [
        ["Source", data.meta.sourceName],
        ["Timescale", data.meta.timescale],
        ["Window", fmtPs(state.start) + " -> " + fmtPs(state.end)],
        ["Center", fmtPs(Math.round((state.start + state.end) / 2))],
        ["Visible events", String(eventsInWindow(state.start, state.end).length)],
        ["Clock period", data.meta.clockMeta ? fmtPs(Math.round(data.meta.clockMeta.period)) : "unknown"]
    ];
    els.summaryCards.innerHTML = cards.map(([k, v]) => `<div class="card"><div class="k">${k}</div><div class="v">${v}</div></div>`).join("");
}

function renderPresets() {
    els.presetWrap.innerHTML = (data.presets || []).map((preset) =>
        `<button class="preset" data-key="${preset.key}" title="${preset.description || ""}">${preset.label}</button>`
    ).join("");
    els.presetWrap.querySelectorAll("button[data-key]").forEach((btn) => {
        btn.addEventListener("click", () => {
            const preset = (data.presets || []).find((item) => item.key === btn.dataset.key);
            if (preset) setWindow(preset.start, preset.end);
        });
    });
}

function renderAnchors() {
    const options = [`<option value="">Jump to notable event...</option>`];
    (data.anchors || []).forEach((item, idx) => {
        options.push(`<option value="${idx}">${fmtPs(item.time)} | ${item.title}</option>`);
    });
    els.eventJump.innerHTML = options.join("");
}

function renderBlocks() {
    const activity = {
        reset: changesInRange(byKey.rst_ni, state.start, state.end, 300),
        spi: (changesInRange(byKey.adc_csn, state.start, state.end, 800) || []).length + (changesInRange(byKey.spi_data_rdy, state.start, state.end, 800) || []).length,
        dsp: (changesInRange(byKey.dsp_integrator, state.start, state.end, 800) || []).length,
        cpu: (changesInRange(byKey.cpu_pc, state.start, state.end, 1200) || []).length,
        relay: (changesInRange(byKey.relay_gpio, state.start, state.end, 200) || []).length,
        wdt: (changesInRange(byKey.wdt_reset, state.start, state.end, 50) || []).length,
        bist: (changesInRange(byKey.bist_done, state.start, state.end, 50) || []).length
    };
    const specs = [
        { group: "Clock / Reset", active: activity.reset && activity.reset.length > 1 || valueAt(byKey.rst_ni, state.end) === "0", danger: valueAt(byKey.rst_ni, state.end) === "0", meta: `rst_ni=${signalValue("rst_ni")}` },
        { group: "SPI / ADC", active: activity.spi > 0 || valueAt(byKey.adc_csn, state.end) === "0", danger: false, meta: `csn=${signalValue("adc_csn")}, sample=${signalValue("spi_data_val")}` },
        { group: "DSP", active: activity.dsp > 1 || valueAt(byKey.arc_irq, state.end) === "1", danger: valueAt(byKey.arc_irq, state.end) === "1", meta: `integrator=${signalValue("dsp_integrator")}, irq=${signalValue("arc_irq")}` },
        { group: "CPU / APB", active: activity.cpu > 1, danger: false, meta: `pc=${signalValue("cpu_pc")}` },
        { group: "Relay / GPIO", active: activity.relay > 1 || valueAt(byKey.relay_gpio, state.end) === "1", danger: valueAt(byKey.relay_gpio, state.end) === "1", meta: `relay=${signalValue("relay_gpio")}` },
        { group: "Watchdog", active: activity.wdt > 1 || valueAt(byKey.wdt_reset, state.end) === "1", danger: valueAt(byKey.wdt_reset, state.end) === "1", meta: `wdt_reset=${signalValue("wdt_reset")}` },
        { group: "BIST", active: activity.bist > 1 || valueAt(byKey.bist_done, state.end) === "1", danger: false, meta: `done=${signalValue("bist_done")}` }
    ];
    els.blockRow.innerHTML = specs.map((item, idx) => `${idx ? '<div class="arrow">-></div>' : ''}<div class="${blockClass(item.active, item.danger)}"><div class="bt">${item.group}</div><div class="bm">${item.meta}</div></div>`).join("");
}

function renderSignals() {
    els.signalGrid.innerHTML = data.meta.signalOrder.map((key) => {
        const sig = byKey[key];
        if (!sig) return "";
        return `<div class="sig"><b>${sig.key}</b><div>${labelValue(sig.kind, valueAt(sig, state.end))}</div><span>${sig.full}</span></div>`;
    }).join("");
}

function buildTimingSvg() {
    const order = data.meta.signalOrder.filter((key) => byKey[key]);
    const width = 980;
    const rowH = 34;
    const height = order.length * rowH + 50;
    const span = Math.max(1, state.end - state.start);
    const xOf = (t) => 210 + (((t - state.start) / span) * width);
    const parts = [`<svg viewBox="0 0 1220 ${height}" width="1220" height="${height}" xmlns="http://www.w3.org/2000/svg">`];
    parts.push(`<line x1="210" y1="18" x2="${210 + width}" y2="18" stroke="#b8a98f"/>`);
    for (let i = 0; i <= 8; i += 1) {
        const x = 210 + ((width * i) / 8);
        const t = Math.round(state.start + ((state.end - state.start) * i) / 8);
        parts.push(`<line x1="${x}" y1="18" x2="${x}" y2="${height - 10}" stroke="#eee0c9"/>`);
        parts.push(`<text x="${x + 2}" y="12" font-size="11" fill="#5b6670">${fmtPs(t)}</text>`);
    }
    let y = 30;
    for (const key of order) {
        const sig = byKey[key];
        parts.push(`<text x="10" y="${y + 15}" font-size="12" fill="#223">${sig.key}</text>`);
        const items = changesInRange(sig, state.start, state.end, sig.kind === "digital" ? 1400 : 200);
        if (items === null) {
            parts.push(`<text x="220" y="${y + 15}" font-size="12" fill="#8b5e1a">Zoom in de thay ro hon.</text>`);
            y += rowH;
            continue;
        }
        if (sig.kind === "digital") {
            const level = (v) => (v === "1" ? y + 6 : y + 24);
            const first = items[0] || [state.start, "0"];
            let d = `M ${xOf(state.start)} ${level(first[1])}`;
            let prev = first;
            for (let i = 1; i < items.length; i += 1) {
                const cur = items[i];
                const x = xOf(cur[0]);
                d += ` L ${x} ${level(prev[1])} L ${x} ${level(cur[1])}`;
                prev = cur;
            }
            d += ` L ${xOf(state.end)} ${level(prev[1])}`;
            parts.push(`<path d="${d}" fill="none" stroke="#0b7285" stroke-width="1.6"/>`);
        } else {
            parts.push(`<line x1="210" y1="${y + 16}" x2="${210 + width}" y2="${y + 16}" stroke="#0b7285"/>`);
            items.slice(0, 60).forEach((item) => {
                const x = xOf(item[0]);
                parts.push(`<line x1="${x}" y1="${y + 6}" x2="${x}" y2="${y + 26}" stroke="#f08c00"/>`);
                parts.push(`<text x="${x + 3}" y="${y + 12}" font-size="10" fill="#7a4f00">${labelValue(sig.kind, item[1])}</text>`);
            });
        }
        y += rowH;
    }
    parts.push("</svg>");
    return parts.join("");
}

function renderTiming() {
    els.timing.innerHTML = buildTimingSvg();
}

function renderEvents() {
    const list = eventsInWindow(state.start, state.end);
    const limit = 400;
    const rows = list.slice(0, limit).map((item) =>
        `<tr><td>${fmtPs(item.time)}</td><td class="${item.sev}">${item.sev.toUpperCase()}</td><td>${item.block}</td><td>${item.title}</td><td>${item.detail}</td></tr>`
    );
    if (!rows.length) rows.push('<tr><td colspan="5">Khong co event nao trong cua so nay.</td></tr>');
    if (list.length > limit) rows.push(`<tr><td colspan="5">Dang hien ${limit}/${list.length} event. Hay thu zoom hep hon de doc chi tiet.</td></tr>`);
    els.eventBody.innerHTML = rows.join("");
}

function renderExplain() {
    const lines = [];
    const rst = valueAt(byKey.rst_ni, state.end);
    const csn = valueAt(byKey.adc_csn, state.end);
    const irq = valueAt(byKey.arc_irq, state.end);
    const relay = valueAt(byKey.relay_gpio, state.end);
    const wdt = valueAt(byKey.wdt_reset, state.end);
    const bist = valueAt(byKey.bist_done, state.end);
    const pc = signalValue("cpu_pc");
    const integ = signalValue("dsp_integrator");
    const recent = eventsInWindow(Math.max(0, state.end - Math.min(windowSize(), 400000)), state.end).slice(-3);

    if (rst === "0") lines.push("Reset dang duoc giu, nen cac khoi con lai chua vao chu ky hoat dong binh thuong.");
    else lines.push("Clock da cap va he thong dang ra khoi reset, co the theo doi luong tu SPI sang DSP roi toi CPU/relay.");

    if (csn === "0") lines.push("SPI dang o giua mot frame ADC, vi vay adc_sclk va adc_miso la hai tin hieu nen nhin dau tien.");
    else if (valueAt(byKey.spi_sample_sticky, state.end) === "1") lines.push("Bridge dang giu sample moi cho phan he thong doc, nghia la du lieu tu SPI da duoc latch noi bo.");

    if (irq === "1") lines.push("DSP dang assert arc IRQ; day la dau hieu bo phat hien ho quang dang kich hoat duong bao ve.");
    else lines.push(`Gia tri tich luy DSP hien tai la ${integ}, ban co the doi chieu voi threshold/event gan nhat.`);

    lines.push(`CPU dang o PC = ${pc}. Tin hieu nay rat hop de lien he waveform voi luong lenh.`);

    if (relay === "1") lines.push("Relay dang o muc trip, tuc la he thong dang cat tai de bao ve.");
    if (wdt === "1") lines.push("Watchdog reset dang duoc kich, can uu tien xem reset tree va nguyen nhan truoc do.");
    if (bist === "1") lines.push("BIST da hoan tat; neu ban zoom gan moc nay se de thay quan he giua test mode va data path binh thuong.");

    if (recent.length) {
        lines.push("Ba event gan nhat trong cua so hien tai: " + recent.map((item) => `${fmtPs(item.time)} ${item.title}`).join(" | "));
    }
    els.explainBox.textContent = lines.join(" ");
}

function applyInputWindow() {
    const start = Number(els.startInput.value);
    const end = Number(els.endInput.value);
    if (Number.isFinite(start) && Number.isFinite(end) && end > start) setWindow(start, end);
}

function applyWindowSize() {
    const size = Number(els.sizeSelect.value);
    if (!Number.isFinite(size) || size <= 0) return;
    const center = (state.start + state.end) / 2;
    setWindow(center - (size / 2), center + (size / 2));
}

function bind() {
    els.summaryCards = $("summaryCards");
    els.startInput = $("startInput");
    els.endInput = $("endInput");
    els.sizeSelect = $("sizeSelect");
    els.applyRange = $("applyRange");
    els.resetView = $("resetView");
    els.centerSlider = $("centerSlider");
    els.eventJump = $("eventJump");
    els.presetWrap = $("presetWrap");
    els.explainBox = $("explainBox");
    els.blockRow = $("blockRow");
    els.timing = $("timing");
    els.signalGrid = $("signalGrid");
    els.eventBody = $("eventBody");

    renderPresets();
    renderAnchors();

    els.applyRange.addEventListener("click", applyInputWindow);
    els.resetView.addEventListener("click", () => setWindow(data.meta.defaultStart, data.meta.defaultEnd));
    els.sizeSelect.addEventListener("change", applyWindowSize);
    els.centerSlider.addEventListener("input", () => {
        const center = (Number(els.centerSlider.value) / 1000) * Math.max(1, data.meta.maxTime);
        setCenter(center);
    });
    els.eventJump.addEventListener("change", () => {
        const idx = Number(els.eventJump.value);
        if (!Number.isFinite(idx)) return;
        const anchor = (data.anchors || [])[idx];
        if (anchor) setCenter(anchor.time);
    });
}

function renderAll() {
    syncControls();
    renderSummary();
    renderBlocks();
    renderSignals();
    renderTiming();
    renderEvents();
    renderExplain();
}

function boot() {
    bind();
    const span = windowSize();
    const options = Array.from(els.sizeSelect.options).map((opt) => Number(opt.value));
    let best = options[0];
    let delta = Math.abs(span - best);
    options.forEach((opt) => {
        const d = Math.abs(span - opt);
        if (d < delta) {
            delta = d;
            best = opt;
        }
    });
    els.sizeSelect.value = String(best);
    renderAll();
}

document.addEventListener("DOMContentLoaded", boot);
})();
