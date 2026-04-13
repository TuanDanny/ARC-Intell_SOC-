"use strict";

(function () {
const data = window.FLOW_VIZ_V3_DATA;
if (!data) return;

const byKey = Object.fromEntries(data.signals.map((sig) => [sig.key, sig]));
const els = {};
const state = {
    start: data.meta.defaultStart || 0,
    end: data.meta.defaultEnd || Math.min(data.meta.maxTime, 4000000),
    selectedSignal: null,
    cursorTime: data.meta.defaultEnd || Math.min(data.meta.maxTime, 4000000),
    playTimer: null,
    eventFollowTimer: null,
    eventIndex: 0,
    teachingMode: false,
    signalScrollTop: 0,
    archView: 'full',
    archShowDirect: true,
    archShowClockReset: true,
    archShowApb: true,
    archShowIo: true,
    archShowGlueSummary: true,
    archSelectedPin: null,
    archModalOpen: false,
    archWireStart: null,
    archManualWires: [],
    archFeedback: {
        kind: 'info',
        title: 'Huong dan',
        detail: 'Double-click vao so do de mo fullscreen wiring playground.'
    },
    archCodeNode: null
};

function $(id) { return document.getElementById(id); }
function clamp(v, min, max) { return Math.max(min, Math.min(max, v)); }
function windowSize() { return Math.max(1, state.end - state.start); }
function inspectionTime() { return clamp(Math.round(state.cursorTime == null ? state.end : state.cursorTime), state.start, state.end); }
function cursorSvgX() { return 230 + (((inspectionTime() - state.start) / Math.max(1, state.end - state.start)) * 980); }

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
    state.cursorTime = clamp(state.cursorTime == null ? state.end : state.cursorTime, state.start, state.end);
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

function visibleSignalOrder() {
    return (data.meta.signalOrder || []).filter((key) => byKey[key]);
}

function ensureSelectedSignal() {
    const order = visibleSignalOrder();
    if (!order.length) {
        state.selectedSignal = null;
        return [];
    }
    if (!state.selectedSignal || !byKey[state.selectedSignal]) state.selectedSignal = order[0];
    return order;
}

function signalRowIndex(key) {
    return visibleSignalOrder().indexOf(key);
}

function scrollSignalCardIntoView(key) {
    const card = els.signalGrid ? els.signalGrid.querySelector(`[data-signal-key="${key}"]`) : null;
    if (card) card.scrollIntoView({ block: "nearest", behavior: "smooth" });
}

function timingHitTest(evt) {
    const svg = els.timing ? els.timing.querySelector("svg") : null;
    const order = ensureSelectedSignal();
    if (!svg || !order.length) return null;
    const rect = svg.getBoundingClientRect();
    const x = evt.clientX - rect.left;
    const y = evt.clientY - rect.top;
    const left = 230;
    const width = 980;
    const top = 36;
    const rowH = 34;
    const bottom = top + (order.length * rowH);
    if (x < left || x > left + width || y < top || y > bottom) return null;
    const rowIdx = clamp(Math.floor((y - top) / rowH), 0, order.length - 1);
    const key = order[rowIdx];
    const sig = byKey[key];
    const time = clamp(
        Math.round(state.start + (((x - left) / width) * Math.max(1, state.end - state.start))),
        state.start,
        state.end
    );
    return { svg, x, y, rowIdx, key, sig, time };
}

function stopPlayCursor() {
    if (state.playTimer) {
        clearInterval(state.playTimer);
        state.playTimer = null;
    }
}

function stopEventFollow() {
    if (state.eventFollowTimer) {
        clearInterval(state.eventFollowTimer);
        state.eventFollowTimer = null;
    }
}

function notableEvents() {
    return data.anchors || [];
}

function nearestEventIndex(time) {
    const events = notableEvents();
    if (!events.length) return -1;
    let bestIdx = 0;
    let bestDelta = Math.abs(events[0].time - time);
    for (let i = 1; i < events.length; i += 1) {
        const delta = Math.abs(events[i].time - time);
        if (delta < bestDelta) {
            bestIdx = i;
            bestDelta = delta;
        }
    }
    return bestIdx;
}

function ensureEventIndex() {
    const events = notableEvents();
    if (!events.length) {
        state.eventIndex = -1;
        return null;
    }
    if (!Number.isFinite(state.eventIndex) || state.eventIndex < 0 || state.eventIndex >= events.length) {
        state.eventIndex = nearestEventIndex(inspectionTime());
    }
    return events[state.eventIndex] || null;
}

function recommendedSignalForEvent(event) {
    if (!event) return state.selectedSignal;
    if (event.block === "SPI / ADC") return event.title.includes("frame") ? "adc_csn" : "spi_data_rdy";
    if (event.block === "DSP") return event.title.includes("IRQ") ? "arc_irq" : "dsp_integrator";
    if (event.block === "Relay / GPIO") return "relay_gpio";
    if (event.block === "Watchdog") return "wdt_reset";
    if (event.block === "BIST") return "bist_done";
    if (event.block === "Clock / Reset") return "rst_ni";
    return state.selectedSignal;
}

function teachingHints(event) {
    if (!event) return "Chon mot moc event de bat dau hoc theo tung buoc.";
    if (event.block === "SPI / ADC") return "Hay nhin adc_csn, adc_sclk, adc_miso va spi_data_rdy de thay tron vong lay mau ADC.";
    if (event.block === "DSP") return "Hay doi chieu dsp_integrator voi arc_irq de thay luc bo phat hien vuot nguong.";
    if (event.block === "Relay / GPIO") return "Tap trung vao relay_gpio va event truoc do de thay chuoi bao ve ket thuc o relay.";
    if (event.block === "Watchdog") return "Nhin wdt_reset cung rst_ni de thay reset tree va phan ung sau su co.";
    if (event.block === "BIST") return "Theo doi bist_done va duong du lieu BIST neu ban muon hieu self-test ket thuc ra sao.";
    if (event.block === "Clock / Reset") return "Khoi dong bang rst_ni va clk la cach nhanh nhat de hieu he thong bat dau chay nhu the nao.";
    return event.detail || "Theo doi cac signal lien quan quanh moc nay.";
}

function selectEventIndex(index, options) {
    const events = notableEvents();
    if (!events.length) return;
    const opts = options || {};
    const bounded = clamp(index, 0, events.length - 1);
    const event = events[bounded];
    state.eventIndex = bounded;
    if (opts.stopPlay !== false) stopPlayCursor();
    if (opts.stopFollow !== false) stopEventFollow();
    const span = windowSize();
    const maxTime = Math.max(1, data.meta.maxTime);
    const start = clamp(Math.round(event.time - (span / 2)), 0, Math.max(0, maxTime - span));
    state.start = start;
    state.end = clamp(start + span, start + 1, maxTime);
    state.cursorTime = clamp(event.time, state.start, state.end);
    const suggested = recommendedSignalForEvent(event);
    if (suggested && byKey[suggested]) state.selectedSignal = suggested;
    renderAll();
    if (opts.focus !== false) focusTimingCursor();
}

function stepTeaching(delta) {
    const events = notableEvents();
    if (!events.length) return;
    state.teachingMode = true;
    const current = ensureEventIndex();
    const currentIdx = current ? state.eventIndex : nearestEventIndex(inspectionTime());
    const nextIdx = clamp((currentIdx < 0 ? 0 : currentIdx) + delta, 0, events.length - 1);
    selectEventIndex(nextIdx, { stopPlay: true, stopFollow: true, focus: true });
}

function toggleTeachingMode() {
    state.teachingMode = !state.teachingMode;
    if (state.teachingMode) {
        const idx = nearestEventIndex(inspectionTime());
        if (idx >= 0) state.eventIndex = idx;
    } else {
        stopEventFollow();
    }
    renderRuntimeViews();
}

function toggleEventFollow() {
    const events = notableEvents();
    if (!events.length) return;
    if (state.eventFollowTimer) {
        stopEventFollow();
        renderRuntimeViews();
        return;
    }
    stopPlayCursor();
    state.teachingMode = true;
    const currentIdx = nearestEventIndex(inspectionTime());
    state.eventIndex = currentIdx >= 0 ? currentIdx : 0;
    selectEventIndex(state.eventIndex, { stopPlay: true, stopFollow: false, focus: true });
    state.eventFollowTimer = setInterval(() => {
        const nextIdx = (state.eventIndex + 1) % events.length;
        selectEventIndex(nextIdx, { stopPlay: true, stopFollow: false, focus: true });
    }, 1800);
    renderRuntimeViews();
}

function scrollTimingToX(x, alignRatio) {
    const timing = els.timing;
    if (!timing) return;
    const ratio = alignRatio == null ? 0.72 : alignRatio;
    requestAnimationFrame(() => {
        const target = Math.max(0, x - (timing.clientWidth * ratio));
        timing.scrollLeft = target;
    });
}

function focusTimingCursor() {
    scrollTimingToX(cursorSvgX(), 0.72);
}

function setCursorTime(time, options) {
    const opts = options || {};
    if (opts.stopPlay !== false) stopPlayCursor();
    if (opts.stopFollow !== false) stopEventFollow();
    state.cursorTime = clamp(Math.round(time), state.start, state.end);
    state.eventIndex = nearestEventIndex(state.cursorTime);
    renderRuntimeViews();
    if (opts.focus !== false) focusTimingCursor();
}

function togglePlayCursor() {
    if (state.playTimer) {
        stopPlayCursor();
        renderRuntimeViews();
        return;
    }
    stopEventFollow();
    const tickMs = 120;
    state.playTimer = setInterval(() => {
        const step = Math.max(1, Math.round(windowSize() / 90));
        let next = inspectionTime() + step;
        if (next >= state.end) next = state.start;
        state.cursorTime = next;
        state.eventIndex = nearestEventIndex(state.cursorTime);
        renderRuntimeViews();
        focusTimingCursor();
    }, tickMs);
    renderRuntimeViews();
}

function signalValue(key, time) {
    const sig = byKey[key];
    const at = time == null ? inspectionTime() : time;
    return labelValue(sig ? sig.kind : "digital", valueAt(sig, at));
}

function syncControls() {
    const center = (state.start + state.end) / 2;
    const maxTime = Math.max(1, data.meta.maxTime);
    els.startInput.value = String(state.start);
    els.endInput.value = String(state.end);
    els.centerSlider.value = String(Math.round((center / maxTime) * 1000));
    if (els.eventJump) {
        const idx = nearestEventIndex(inspectionTime());
        els.eventJump.value = idx >= 0 ? String(idx) : "";
    }
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
    const inspect = inspectionTime();
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
        { group: "Clock / Reset", active: activity.reset && activity.reset.length > 1 || valueAt(byKey.rst_ni, inspect) === "0", danger: valueAt(byKey.rst_ni, inspect) === "0", meta: `rst_ni=${signalValue("rst_ni", inspect)}` },
        { group: "SPI / ADC", active: activity.spi > 0 || valueAt(byKey.adc_csn, inspect) === "0", danger: false, meta: `csn=${signalValue("adc_csn", inspect)}, sample=${signalValue("spi_data_val", inspect)}` },
        { group: "DSP", active: activity.dsp > 1 || valueAt(byKey.arc_irq, inspect) === "1", danger: valueAt(byKey.arc_irq, inspect) === "1", meta: `integrator=${signalValue("dsp_integrator", inspect)}, irq=${signalValue("arc_irq", inspect)}` },
        { group: "CPU / APB", active: activity.cpu > 1, danger: false, meta: `pc=${signalValue("cpu_pc", inspect)}` },
        { group: "Relay / GPIO", active: activity.relay > 1 || valueAt(byKey.relay_gpio, inspect) === "1", danger: valueAt(byKey.relay_gpio, inspect) === "1", meta: `relay=${signalValue("relay_gpio", inspect)}` },
        { group: "Watchdog", active: activity.wdt > 1 || valueAt(byKey.wdt_reset, inspect) === "1", danger: valueAt(byKey.wdt_reset, inspect) === "1", meta: `wdt_reset=${signalValue("wdt_reset", inspect)}` },
        { group: "BIST", active: activity.bist > 1 || valueAt(byKey.bist_done, inspect) === "1", danger: false, meta: `done=${signalValue("bist_done", inspect)}` }
    ];
    els.blockRow.innerHTML = specs.map((item, idx) => `${idx ? '<div class="arrow">-></div>' : ''}<div class="${blockClass(item.active, item.danger)}"><div class="bt">${item.group}</div><div class="bm">${item.meta}</div></div>`).join("");
}

function renderSignals() {
    const order = ensureSelectedSignal();
    const selectedRow = signalRowIndex(state.selectedSignal) + 1;
    const inspect = inspectionTime();
    const restoreScrollTop = state.signalScrollTop || 0;
    const cards = [
        `<div class="sig sig-help"><b>How To Read This</b><div>Signals Now dang theo vach tim Play Cursor. Mac dinh cursor nam o mep phai nen giong snapshot cua vach cam.</div><span>Panel nay co the cuon doc, va se giu nguyen vi tri cuon hien tai cua ban khi cursor/event thay doi.</span>${selectedRow > 0 ? `<div class="sig-help-selected">Dang chon: Row ${selectedRow} = ${state.selectedSignal} | Cursor @ ${fmtPs(inspect)}</div>` : ``}</div>`
    ];
    order.forEach((key, idx) => {
        const sig = byKey[key];
        const selected = key === state.selectedSignal ? " selected" : "";
        const currentValue = labelValue(sig.kind, valueAt(sig, inspect));
        const endValue = labelValue(sig.kind, valueAt(sig, state.end));
        const extra = inspect === state.end ? `End snapshot @ ${fmtPs(state.end)}` : `End snapshot @ ${fmtPs(state.end)} = ${endValue}`;
        cards.push(`<button class="sig sig-button${selected}" type="button" data-signal-key="${sig.key}"><div class="sig-top"><b>${sig.key}</b><span class="sig-row-chip">Row ${idx + 1}</span></div><div class="sig-value">${currentValue}</div><div class="sig-meta">Cursor @ ${fmtPs(inspect)}</div><div class="sig-submeta">${extra}</div><span>${sig.full}</span></button>`);
    });
    els.signalGrid.innerHTML = cards.join("");
    els.signalGrid.querySelectorAll("[data-signal-key]").forEach((btn) => {
        btn.addEventListener("click", () => {
            state.selectedSignal = btn.dataset.signalKey;
            renderRuntimeViews();
            focusTimingCursor();
        });
    });
    requestAnimationFrame(() => {
        els.signalGrid.scrollTop = Math.max(0, restoreScrollTop);
    });
}

function buildTimingSvg() {
    const order = ensureSelectedSignal();
    const width = 980;
    const rowH = 34;
    const height = order.length * rowH + 56;
    const span = Math.max(1, state.end - state.start);
    const inspect = inspectionTime();
    const xOf = (t) => 230 + (((t - state.start) / span) * width);
    const snapshotX = xOf(state.end);
    const playX = xOf(inspect);
    const playLabelX = Math.min(230 + width - 76, playX + 6);
    const parts = [`<svg viewBox="0 0 1240 ${height}" width="1240" height="${height}" xmlns="http://www.w3.org/2000/svg">`];
    parts.push(`<line x1="230" y1="18" x2="${230 + width}" y2="18" stroke="#b8a98f"/>`);
    for (let i = 0; i <= 8; i += 1) {
        const x = 230 + ((width * i) / 8);
        const t = Math.round(state.start + ((state.end - state.start) * i) / 8);
        parts.push(`<line x1="${x}" y1="18" x2="${x}" y2="${height - 10}" stroke="#eee0c9"/>`);
        parts.push(`<text x="${x + 2}" y="12" font-size="11" fill="#5b6670">${fmtPs(t)}</text>`);
    }
    parts.push(`<line x1="${snapshotX}" y1="18" x2="${snapshotX}" y2="${height - 10}" stroke="#f08c00" stroke-width="2" stroke-dasharray="5 4"/>`);
    parts.push(`<text x="${Math.max(234, snapshotX - 102)}" y="30" font-size="10" fill="#a55a00">End snapshot</text>`);
    parts.push(`<line x1="${playX}" y1="18" x2="${playX}" y2="${height - 10}" stroke="#7c5cff" stroke-width="2.2"/>`);
    parts.push(`<text x="${playLabelX}" y="42" font-size="10" fill="#5f3dc4">Play cursor</text>`);
    parts.push(`<line id="timingHoverLine" x1="230" y1="18" x2="230" y2="${height - 10}" stroke="#7c5cff" stroke-width="1.6" stroke-dasharray="4 4" visibility="hidden"/>`);

    let y = 36;
    order.forEach((key, rowIdx) => {
        const sig = byKey[key];
        const selected = key === state.selectedSignal;
        const rowTop = y - 8;
        if (selected) {
            parts.push(`<rect x="4" y="${rowTop}" width="1226" height="30" rx="8" fill="#fff4d6" stroke="#f0b24f"/>`);
        }
        parts.push(`<text x="14" y="${y + 12}" font-size="10" fill="#8b5e1a">${rowIdx + 1}</text>`);
        parts.push(`<text x="32" y="${y + 12}" font-size="12" fill="#223" font-weight="${selected ? '700' : '400'}">${sig.key}</text>`);
        const items = changesInRange(sig, state.start, state.end, sig.kind === "digital" ? 1400 : 200);
        if (items === null) {
            parts.push(`<text x="240" y="${y + 12}" font-size="12" fill="#8b5e1a">Zoom in de thay ro hon.</text>`);
            y += rowH;
            return;
        }
        if (sig.kind === "digital") {
            const level = (v) => (v === "1" ? y + 3 : y + 21);
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
            parts.push(`<path d="${d}" fill="none" stroke="${selected ? '#c27100' : '#0b7285'}" stroke-width="${selected ? '2.2' : '1.6'}"/>`);
        } else {
            parts.push(`<line x1="230" y1="${y + 13}" x2="${230 + width}" y2="${y + 13}" stroke="${selected ? '#c27100' : '#0b7285'}"/>`);
            const marks = [];
            const maxMarks = sig.key === 'cpu_pc' ? 18 : 24;
            const step = Math.max(1, Math.ceil(items.length / maxMarks));
            let lastLabel = null;
            for (let i = 0; i < items.length; i += step) {
                const item = items[i];
                const label = labelValue(sig.kind, item[1]);
                if (label === lastLabel && sig.key === 'cpu_pc') continue;
                marks.push({ time: item[0], label });
                lastLabel = label;
            }
            if (marks.length > maxMarks) marks.length = maxMarks;
            marks.forEach((mark) => {
                const x = xOf(mark.time);
                parts.push(`<line x1="${x}" y1="${y + 3}" x2="${x}" y2="${y + 23}" stroke="#f08c00"/>`);
                parts.push(`<text x="${x + 3}" y="${y + 9}" font-size="10" fill="#7a4f00">${mark.label}</text>`);
            });
            if (items.length > maxMarks * 2) {
                parts.push(`<text x="${230 + width - 130}" y="${y + 25}" font-size="10" fill="#8b5e1a">zoom in for detail</text>`);
            }
        }
        y += rowH;
    });
    parts.push("</svg>");
    return parts.join("");
}

function hideTimingHover() {
    const hover = els.timingHover;
    if (hover) hover.style.display = "none";
    const hoverLine = els.timing ? els.timing.querySelector("#timingHoverLine") : null;
    if (hoverLine) hoverLine.setAttribute("visibility", "hidden");
}

function updateTimingHover(evt) {
    const hit = timingHitTest(evt);
    if (!hit) {
        hideTimingHover();
        return;
    }
    const hover = els.timingHover;
    const hoverLine = hit.svg.querySelector("#timingHoverLine");
    if (hoverLine) {
        hoverLine.setAttribute("x1", String(hit.x));
        hoverLine.setAttribute("x2", String(hit.x));
        hoverLine.setAttribute("visibility", "visible");
    }
    if (!hover) return;
    hover.style.display = "block";
    hover.innerHTML = `<b>Row ${hit.rowIdx + 1}: ${hit.key}</b><span>${fmtPs(hit.time)} | ${labelValue(hit.sig.kind, valueAt(hit.sig, hit.time))}</span><small>Click de chon signal nay.</small>`;
    hover.style.left = `${evt.clientX + 18}px`;
    hover.style.top = `${evt.clientY + 18}px`;
}

function selectTimingSignal(evt) {
    const hit = timingHitTest(evt);
    if (!hit) return;
    state.selectedSignal = hit.key;
    setCursorTime(hit.time, { focus: true });
}

function renderTiming() {
    const selectedRow = signalRowIndex(state.selectedSignal) + 1;
    const inspect = inspectionTime();
    const currentEvent = ensureEventIndex();
    const events = notableEvents();
    const stepText = currentEvent && state.eventIndex >= 0 ? `Step ${state.eventIndex + 1}/${events.length}: ${currentEvent.title}` : `Chua co event noi bat`;
    const guide = selectedRow > 0
        ? `Dang xem Row ${selectedRow} = ${state.selectedSignal}. Play cursor tim dang dung tai ${fmtPs(inspect)}.`
        : `Play cursor tim dang dung tai ${fmtPs(inspect)}.`;
    const playLabel = state.playTimer ? "Pause Cursor" : "Play Cursor";
    const followLabel = state.eventFollowTimer ? "Stop Auto-Follow" : "Auto-Follow Events";
    const teachLabel = state.teachingMode ? "Teaching Mode: ON" : "Teaching Mode";
    const sliderValue = Math.round(((inspect - state.start) / Math.max(1, state.end - state.start)) * 1000);
    const teachingPanel = state.teachingMode && currentEvent
        ? `<div class="teaching-card"><div class="teaching-head"><b>${stepText}</b><span>${fmtPs(currentEvent.time)} | ${currentEvent.block}</span></div><div class="teaching-body">${currentEvent.detail}</div><div class="teaching-hint">${teachingHints(currentEvent)}</div></div>`
        : ``;
    els.timing.innerHTML = `<div class="timing-guide"><b>${guide}</b><span>Vach tim = gia tri ma Signals Now dang theo. Vach cam = snapshot cuoi cua window. Click signal ben phai se tu focus den vung cursor nay.</span></div><div class="event-controls"><button type="button" class="cursor-btn secondary" id="eventPrevBtn">Prev Step</button><button type="button" class="cursor-btn secondary" id="eventNextBtn">Next Step</button><button type="button" class="cursor-btn" id="teachingToggleBtn">${teachLabel}</button><button type="button" class="cursor-btn" id="eventFollowBtn">${followLabel}</button><div class="event-readout"><b>${stepText}</b><span>${currentEvent ? `${fmtPs(currentEvent.time)} | ${currentEvent.block}` : `Khong co event de theo doi`}</span></div></div>${teachingPanel}<div class="cursor-controls"><button type="button" class="cursor-btn" id="cursorPlayBtn">${playLabel}</button><button type="button" class="cursor-btn secondary" id="cursorResetBtn">Cursor Ve Cuoi</button><button type="button" class="cursor-btn secondary" id="cursorStartBtn">Cursor Ve Dau</button><div class="cursor-readout"><b>Cursor:</b> ${fmtPs(inspect)}<span>Window end: ${fmtPs(state.end)}</span></div><input id="cursorSlider" class="cursor-slider" type="range" min="0" max="1000" value="${sliderValue}"></div>${buildTimingSvg()}`;
    let hover = $("timingHoverFloat");
    if (!hover) {
        hover = document.createElement("div");
        hover.id = "timingHoverFloat";
        hover.className = "timing-hover";
        document.body.appendChild(hover);
    }
    els.timingHover = hover;
    hideTimingHover();
    const svg = els.timing.querySelector("svg");
    if (svg) {
        svg.addEventListener("mousemove", updateTimingHover);
        svg.addEventListener("mouseleave", hideTimingHover);
        svg.addEventListener("click", selectTimingSignal);
    }
    const playBtn = $("cursorPlayBtn");
    const resetBtn = $("cursorResetBtn");
    const startBtn = $("cursorStartBtn");
    const slider = $("cursorSlider");
    const prevBtn = $("eventPrevBtn");
    const nextBtn = $("eventNextBtn");
    const teachBtn = $("teachingToggleBtn");
    const followBtn = $("eventFollowBtn");
    if (playBtn) playBtn.addEventListener("click", togglePlayCursor);
    if (resetBtn) resetBtn.addEventListener("click", () => setCursorTime(state.end, { focus: true }));
    if (startBtn) startBtn.addEventListener("click", () => setCursorTime(state.start, { focus: true }));
    if (prevBtn) prevBtn.addEventListener("click", () => stepTeaching(-1));
    if (nextBtn) nextBtn.addEventListener("click", () => stepTeaching(1));
    if (teachBtn) teachBtn.addEventListener("click", toggleTeachingMode);
    if (followBtn) followBtn.addEventListener("click", toggleEventFollow);
    if (slider) {
        slider.addEventListener("input", () => {
            const next = state.start + ((Number(slider.value) / 1000) * Math.max(1, state.end - state.start));
            setCursorTime(next, { focus: false });
        });
        slider.addEventListener("change", () => focusTimingCursor());
    }
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
    const inspect = inspectionTime();
    const rst = valueAt(byKey.rst_ni, inspect);
    const csn = valueAt(byKey.adc_csn, inspect);
    const irq = valueAt(byKey.arc_irq, inspect);
    const relay = valueAt(byKey.relay_gpio, inspect);
    const wdt = valueAt(byKey.wdt_reset, inspect);
    const bist = valueAt(byKey.bist_done, inspect);
    const pc = signalValue("cpu_pc", inspect);
    const integ = signalValue("dsp_integrator", inspect);
    const recent = eventsInWindow(Math.max(0, inspect - Math.min(windowSize(), 400000)), inspect).slice(-3);

    if (rst === "0") lines.push("Reset dang duoc giu, nen cac khoi con lai chua vao chu ky hoat dong binh thuong.");
    else lines.push("Clock da cap va he thong dang ra khoi reset, co the theo doi luong tu SPI sang DSP roi toi CPU/relay.");

    if (csn === "0") lines.push("SPI dang o giua mot frame ADC, vi vay adc_sclk va adc_miso la hai tin hieu nen nhin dau tien.");
    else if (valueAt(byKey.spi_sample_sticky, inspect) === "1") lines.push("Bridge dang giu sample moi cho phan he thong doc, nghia la du lieu tu SPI da duoc latch noi bo.");

    if (irq === "1") lines.push("DSP dang assert arc IRQ; day la dau hieu bo phat hien ho quang dang kich hoat duong bao ve.");
    else lines.push(`Gia tri tich luy DSP tai Play Cursor hien tai la ${integ}, ban co the doi chieu voi threshold/event gan nhat.`);

    lines.push(`Play Cursor dang dung tai ${fmtPs(inspect)}, va Signals Now ben phai dang doc gia tri theo vach tim nay.`);
    lines.push(`CPU dang o PC = ${pc}. Tin hieu nay rat hop de lien he waveform voi luong lenh.`);
    lines.push(`Vach cam van giu vai tro snapshot cuoi cua window, con vach tim la moc song de ban hoc luong tin hieu tung thoi diem.`);

    if (relay === "1") lines.push("Relay dang o muc trip, tuc la he thong dang cat tai de bao ve.");
    if (wdt === "1") lines.push("Watchdog reset dang duoc kich, can uu tien xem reset tree va nguyen nhan truoc do.");
    if (bist === "1") lines.push("BIST da hoan tat; neu ban zoom gan moc nay se de thay quan he giua test mode va data path binh thuong.");

    if (recent.length) {
        lines.push("Ba event gan nhat tinh den Play Cursor: " + recent.map((item) => `${fmtPs(item.time)} ${item.title}`).join(" | "));
    }
    if (state.teachingMode) {
        const stepEvent = ensureEventIndex();
        if (stepEvent) lines.push(`Teaching Mode dang bat. Moc hien tai: ${stepEvent.title}. ${teachingHints(stepEvent)}`);
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

function escapeHtml(text) {
    return String(text == null ? '' : text)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

function renderSummary() {
    const arch = data.architecture || { nodes: [], connections: [] };
    const directCount = (arch.connections || []).filter((conn) => (conn.endpoints || []).length >= 2).length;
    const internalCount = (arch.connections || []).filter((conn) => (conn.endpoints || []).length < 2).length;
    const cards = [
        ["Source", data.meta.sourceName],
        ["Timescale", data.meta.timescale],
        ["Window", fmtPs(state.start) + " -> " + fmtPs(state.end)],
        ["Visible events", String(eventsInWindow(state.start, state.end).length)],
        ["Modules", String(Math.max(0, (arch.nodes || []).length - 1))],
        ["Direct nets", String(directCount)],
        ["Internal nets", String(internalCount)],
        ["Clock period", data.meta.clockMeta ? fmtPs(Math.round(data.meta.clockMeta.period)) : "unknown"]
    ];
    els.summaryCards.innerHTML = cards.map(([k, v]) => `<div class="card"><div class="k">${k}</div><div class="v">${v}</div></div>`).join("");
}

function architecturePresentationPorts() {
    return {
        top_io: ['clk_i', 'rst_ni_async', 'adc_miso_i', 'adc_mosi_o', 'adc_sclk_o', 'adc_csn_o', 'uart_tx_o', 'uart_rx_i', 'gpio_pin_io'],
        u_rstgen: ['clk_i', 'rst_ni', 'rst_no', 'init_no'],
        u_wdt: ['clk_i', 'rst_ni', 'paddr_i', 'pwdata_i', 'psel_i', 'penable_i', 'pwrite_i', 'prdata_o', 'pready_o', 'pslverr_o', 'wdt_reset_o'],
        u_cpu: ['clk_i', 'rst_ni', 'irq_arc_i', 'irq_timer_i', 'apb_mst'],
        apb_cpu_master: ['if'],
        u_interconnect: ['penable_i', 'pwrite_i', 'paddr_i', 'psel_i', 'pwdata_i', 'prdata_o', 'pready_o', 'pslverr_o', 'penable_o', 'pwrite_o', 'paddr_o', 'psel_o', 'pwdata_o', 'prdata_i', 'pready_i', 'pslverr_i'],
        apb_dsp_if: ['if'],
        u_spi_bridge: ['clk_i', 'rst_ni', 'paddr_i', 'pwdata_i', 'pwrite_i', 'psel_i', 'penable_i', 'prdata_o', 'pready_o', 'pslverr_o', 'adc_miso_i', 'adc_mosi_o', 'adc_sclk_o', 'adc_csn_o', 'sample_data_o', 'sample_valid_o'],
        u_dsp: ['clk_i', 'rst_ni', 'adc_data_i', 'adc_valid_i', 'apb_slv', 'irq_arc_o'],
        u_bist: ['clk_i', 'rst_ni', 'paddr_i', 'pwdata_i', 'psel_i', 'penable_i', 'pwrite_i', 'prdata_o', 'pready_o', 'pslverr_o', 'bist_data_o', 'bist_valid_o', 'bist_active_o', 'dsp_irq_i'],
        u_gpio: ['HCLK', 'HRESETn', 'PADDR', 'PWDATA', 'PWRITE', 'PSEL', 'PENABLE', 'PRDATA', 'PREADY', 'PSLVERR', 'gpio_in', 'gpio_out', 'gpio_dir'],
        u_uart: ['clk_i', 'rst_ni', 'paddr_i', 'pwdata_i', 'pwrite_i', 'psel_i', 'penable_i', 'prdata_o', 'pready_o', 'pslverr_o', 'sout_o', 'sin_i'],
        u_timer: ['HCLK', 'HRESETn', 'PADDR', 'PWDATA', 'PWRITE', 'PSEL', 'PENABLE', 'PRDATA', 'PREADY', 'PSLVERR', 'events_o']
    };
}

function isArchClockResetSignal(signal) {
    return signal === 'clk_i' || /^rst/i.test(signal);
}

function isArchApbDetailSignal(signal) {
    return /^(s_paddr|s_pwdata|s_prdata|s_psel|s_penable|s_pwrite|s_pready|s_pslverr)$/.test(signal);
}

function isArchIoSignal(signal) {
    return /^(adc_|uart_)/.test(signal);
}

function architectureViewData() {
    const arch = data.architecture || { nodes: [], connections: [], glue: [] };
    const portAllow = architecturePresentationPorts();
    const rawNodes = (arch.nodes || []).filter((node) => node && node.id);
    const nodes = rawNodes
        .filter((node) => state.archView === 'full' || !!portAllow[node.id])
        .map((node) => {
            if (state.archView === 'full') return node;
            const allowed = new Set(portAllow[node.id] || []);
            return { ...node, ports: (node.ports || []).filter((port) => allowed.has(port.name)) };
        })
        .filter((node) => node.id === 'top_io' || (node.ports || []).length);

    const nodeIds = new Set(nodes.map((node) => node.id));
    const portIds = new Set();
    nodes.forEach((node) => {
        (node.ports || []).forEach((port) => portIds.add(`${node.id}.${port.name}`));
    });

    const connections = (arch.connections || [])
        .map((conn) => ({
            signal: conn.signal,
            endpoints: (conn.endpoints || []).filter((ep) => nodeIds.has(ep.node) && portIds.has(`${ep.node}.${ep.port}`))
        }))
        .filter((conn) => conn.endpoints.length >= 2)
        .filter((conn) => {
            if (!state.archShowDirect) return false;
            if (!state.archShowClockReset && isArchClockResetSignal(conn.signal)) return false;
            if (!state.archShowApb && isArchApbDetailSignal(conn.signal)) return false;
            if (!state.archShowIo && isArchIoSignal(conn.signal)) return false;
            return true;
        });

    const groupOrder = (arch.groupOrder || []).filter((group) => nodes.some((node) => node.group === group));
    return { arch, nodes, connections, groupOrder };
}

function architecturePortKey(nodeId, portName) {
    return `${nodeId}.${portName}`;
}

function architecturePortMeta(viewData, portKey) {
    if (!portKey) return null;
    const cut = String(portKey).indexOf('.');
    if (cut < 0) return null;
    const nodeId = String(portKey).slice(0, cut);
    const portName = String(portKey).slice(cut + 1);
    const node = (viewData.nodes || []).find((item) => item.id === nodeId);
    const port = node ? (node.ports || []).find((item) => item.name === portName) : null;
    return node && port ? { key: portKey, node, port } : null;
}

function architectureRawConnectionsForPort(portKey) {
    return ((data.architecture && data.architecture.connections) || []).filter((conn) =>
        (conn.endpoints || []).some((ep) => architecturePortKey(ep.node, ep.port) === portKey)
    );
}

function architectureSelectedPinData(viewData) {
    const meta = architecturePortMeta(viewData, state.archSelectedPin);
    if (!meta) return null;

    const connections = [];
    const matchKeys = new Set([meta.key]);

    (viewData.connections || []).forEach((conn) => {
        const endpoints = (conn.endpoints || []).map((ep) => ({
            ...ep,
            key: architecturePortKey(ep.node, ep.port)
        }));
        if (!endpoints.some((ep) => ep.key === meta.key)) return;
        const others = endpoints.filter((ep) => ep.key !== meta.key);
        others.forEach((ep) => matchKeys.add(ep.key));
        connections.push({
            signal: conn.signal,
            endpoints,
            others,
            isBus: endpoints.length > 2
        });
    });

    connections.sort((a, b) => a.signal.localeCompare(b.signal));
    return { meta, connections, matchKeys };
}
function architectureGlueStories() {
    const glue = (data.architecture && data.architecture.glue) || [];
    const byLhs = new Map(glue.map((item) => [item.lhs, item.rhs]));
    const stories = [];

    function add(title, detail, exprs, chips) {
        const lines = (exprs || []).filter(Boolean);
        if (!lines.length) return;
        stories.push({ title, detail, exprs: lines, chips: chips || [] });
    }

    add(
        'SPI / BIST -> DSP mux',
        'Top-level chon du lieu tu SPI hoac BIST roi dua vao u_dsp. Day la luong data quan trong nhat cua signal path.',
        [
            byLhs.get('dsp_data_in') ? 'dsp_data_in = ' + byLhs.get('dsp_data_in') : '',
            byLhs.get('dsp_valid_in') ? 'dsp_valid_in = ' + byLhs.get('dsp_valid_in') : ''
        ],
        ['SPI', 'BIST', 'DSP']
    );

    add(
        'DSP IRQ -> CPU gate',
        'IRQ arc tu DSP duoc gate boi BIST mode, nen luc BIST chay CPU se khong nhan arc interrupt that.',
        [
            byLhs.get('irq_arc_critical') ? 'irq_arc_critical = ' + byLhs.get('irq_arc_critical') : '',
            byLhs.get('bist_dsp_irq_capture') ? 'bist_dsp_irq_capture = ' + byLhs.get('bist_dsp_irq_capture') : ''
        ],
        ['DSP', 'CPU', 'BIST']
    );

    add(
        'APB DSP bridge',
        'DSP APB interface khong noi truc tiep bang mot instance slave rieng, ma duoc glue tu s_p* sang apb_dsp_if roi tra ve s_prdata/s_pready/s_pslverr.',
        [
            byLhs.get('apb_dsp_if.paddr') ? 'apb_dsp_if.paddr = ' + byLhs.get('apb_dsp_if.paddr') : '',
            byLhs.get('apb_dsp_if.psel') ? 'apb_dsp_if.psel = ' + byLhs.get('apb_dsp_if.psel') : '',
            byLhs.get('s_prdata[1]') ? 's_prdata[1] = ' + byLhs.get('s_prdata[1]') : ''
        ],
        ['Interconnect', 'DSP', 'APB']
    );

    add(
        'Timer -> CPU interrupt',
        'Timer khong noi vao CPU bang direct net module-to-module, ma qua glue irq_timer_tick o top-level.',
        [byLhs.get('irq_timer_tick') ? 'irq_timer_tick = ' + byLhs.get('irq_timer_tick') : ''],
        ['Timer', 'CPU']
    );

    add(
        'Watchdog reset hold',
        'Reset cua watchdog duoc keo dai thanh mot reset tree an toan hon truoc khi quay lai rst logic chung.',
        [
            byLhs.get('wdt_reset_hold_active') ? 'wdt_reset_hold_active = ' + byLhs.get('wdt_reset_hold_active') : '',
            byLhs.get('combined_rst_n') ? 'combined_rst_n = ' + byLhs.get('combined_rst_n') : ''
        ],
        ['WDT', 'Reset']
    );

    add(
        'GPIO / relay drive',
        'Relay va GPIO board di qua tri-state glue o top-level, nen tren so do direct net khong the hien day du logic output-enable nay.',
        [
            byLhs.get('gpio_pin_io[0]') ? 'gpio_pin_io[0] = ' + byLhs.get('gpio_pin_io[0]') : '',
            byLhs.get('gpio_pin_io[3:1]') ? 'gpio_pin_io[3:1] = ' + byLhs.get('gpio_pin_io[3:1]') : ''
        ],
        ['GPIO', 'Relay']
    );

    const foundMap = Array.from(byLhs.keys()).some((lhs) => /^start_addr\[\d+\]$/.test(lhs));
    if (foundMap) {
        stories.push({
            title: 'APB address map',
            detail: 'u_interconnect giai ma 8 vung dia chi cho RAM, DSP, GPIO, UART, TIMER, WATCHDOG, BIST va SPI bridge.',
            exprs: ['start_addr[i] / end_addr[i] -> RAM, DSP, GPIO, UART, TIMER, WATCHDOG, BIST, SPI'],
            chips: ['RAM', 'DSP', 'GPIO', 'UART', 'TIMER', 'WDT', 'BIST', 'SPI']
        });
    }
    return stories;
}

function renderArchitectureControls(viewData) {
    if (!els.archViewFull) return;
    els.archViewFull.classList.toggle('active', state.archView === 'full');
    els.archViewPresentation.classList.toggle('active', state.archView === 'presentation');
    els.archShowDirect.checked = state.archShowDirect;
    els.archShowClockReset.checked = state.archShowClockReset;
    els.archShowApb.checked = state.archShowApb;
    els.archShowIo.checked = state.archShowIo;
    els.archShowGlueSummary.checked = state.archShowGlueSummary;

    const modeLabel = state.archView === 'presentation' ? 'Presentation Mode' : 'Full RTL';
    const directCount = viewData.connections.length;
    const nodeCount = Math.max(0, viewData.nodes.length - 1);
    const hint = state.archView === 'presentation'
        ? 'Khong auto-ve day. Bam vao chan de xem endpoint cung net, rat hop de hoc nhanh va tu cau day khi lam bao cao.'
        : 'Khong auto-ve day. Bam vao chan port de xem direct-net endpoint duoc trich tu RTL.';
    els.archStatus.innerHTML = `
        <span class="arch-status-chip mode">${escapeHtml(modeLabel)}</span>
        <span class="arch-status-chip">Visible blocks: ${nodeCount}</span>
        <span class="arch-status-chip">Hint nets: ${directCount}</span>
        <span class="arch-status-note">${escapeHtml(hint)}</span>`;
}

function renderArchitectureGlueSummary() {
    if (!els.archGlueSummary) return;
    if (!state.archShowGlueSummary) {
        els.archGlueSummary.innerHTML = '';
        els.archGlueSummary.style.display = 'none';
        return;
    }
    const stories = architectureGlueStories();
    if (!stories.length) {
        els.archGlueSummary.innerHTML = '<div class="muted">Khong tim thay glue summary noi bat nao.</div>';
        els.archGlueSummary.style.display = 'block';
        return;
    }
    els.archGlueSummary.style.display = 'grid';
    els.archGlueSummary.innerHTML = stories.map((story) => `
        <div class="arch-story-card">
            <div class="arch-story-title">${escapeHtml(story.title)}</div>
            <div class="arch-story-detail">${escapeHtml(story.detail)}</div>
            <div class="arch-story-chips">${(story.chips || []).map((chip) => `<span class="arch-story-chip">${escapeHtml(chip)}</span>`).join('')}</div>
            <div class="arch-story-code">${(story.exprs || []).map((expr) => `<div>${escapeHtml(expr)}</div>`).join('')}</div>
        </div>`).join('');
}

function setArchitectureView(mode) {
    state.archView = mode === 'presentation' ? 'presentation' : 'full';
    if (state.archView === 'presentation') {
        state.archShowDirect = true;
        state.archShowClockReset = true;
        state.archShowApb = false;
        state.archShowIo = true;
        state.archShowGlueSummary = true;
    } else {
        state.archShowDirect = true;
        state.archShowClockReset = true;
        state.archShowApb = true;
        state.archShowIo = true;
    }
    refreshArchitectureViews();
}

function renderArchitecturePanel(viewData) {
    const currentView = viewData || architectureViewData();
    if (state.archSelectedPin && !architecturePortMeta(currentView, state.archSelectedPin)) {
        state.archSelectedPin = null;
    }
    renderArchitectureControls(currentView);
    renderArchitectureGlueSummary();
    renderArchitectureDiagram(currentView);
    renderArchitecturePinInfo(currentView);
    renderArchitectureModalState(currentView);
}

function renderArchitectureDiagram(viewData) {
    const arch = data.architecture;
    const currentView = viewData || architectureViewData();
    if (!arch || !currentView.nodes.length) {
        els.archOverview.innerHTML = '<div class="muted">Chua co du lieu kien truc.</div>';
        return;
    }

    const nodes = currentView.nodes;
    const groupOrder = currentView.groupOrder || [];
    const nodeMap = new Map(nodes.map((node) => [node.id, node]));
    const groupIndex = new Map(groupOrder.map((group, idx) => [group, idx]));
    const portUsage = new Map();

    (currentView.connections || []).forEach((conn) => {
        const endpoints = (conn.endpoints || []).filter((ep) => nodeMap.has(ep.node));
        if (endpoints.length < 2) return;
        endpoints.forEach((ep) => {
            const key = architecturePortKey(ep.node, ep.port);
            if (!portUsage.has(key)) portUsage.set(key, { cols: [] });
            const stat = portUsage.get(key);
            endpoints.forEach((other) => {
                if (other.node === ep.node && other.port === ep.port) return;
                const otherNode = nodeMap.get(other.node);
                stat.cols.push(groupIndex.get(otherNode.group) ?? 0);
            });
        });
    });

    function groupFill(group) {
        if (group === 'Top I/O') return '#e3f0ff';
        if (group === 'Infrastructure') return '#f5efe1';
        if (group === 'Interconnect') return '#f7ecd4';
        if (group === 'CPU / Control') return '#efe7ff';
        if (group === 'Signal Path') return '#fff0da';
        if (group === 'Peripherals') return '#eef7eb';
        return '#f6f1e8';
    }

    function groupHeaderFill(group) {
        if (group === 'Top I/O') return '#b9d8fb';
        if (group === 'Infrastructure') return '#e7d8b2';
        if (group === 'Interconnect') return '#eed6a5';
        if (group === 'CPU / Control') return '#d8c7ff';
        if (group === 'Signal Path') return '#ffd89d';
        if (group === 'Peripherals') return '#cfe9c7';
        return '#ddd2c2';
    }

    function portColor(port) {
        if (port.direction === 'input') return '#0b7285';
        if (port.direction === 'output') return '#c27100';
        if (port.direction === 'inout') return '#7c5c00';
        if (port.direction === 'interface') return '#5c4c99';
        return '#6b7280';
    }

    function defaultPortSide(node, port) {
        if (node.module === 'APB_BUS') return 'center';
        if (port.direction === 'input') return 'left';
        if (port.direction === 'output') return 'right';
        if (port.direction === 'interface') return 'center';
        if (port.direction === 'inout') return 'right';
        return 'left';
    }

    function inferPortSide(node, port) {
        return defaultPortSide(node, port);
    }

    const selectedData = architectureSelectedPinData(currentView);
    const selectedKey = selectedData ? selectedData.meta.key : null;
    const matchedKeys = selectedData ? selectedData.matchKeys : new Set();

    function portVisual(portKey, port) {
        const selected = portKey === selectedKey;
        const matched = !selected && matchedKeys.has(portKey);
        const base = portColor(port);
        return {
            selected,
            matched,
            stroke: selected ? '#d9480f' : (matched ? '#2b8a3e' : base),
            fill: selected ? '#fff4e6' : (matched ? '#ebfbee' : '#fffefb'),
            label: selected ? '#7a2e0b' : (matched ? '#1b6f34' : '#1f2933')
        };
    }

    const colWidth = 560;
    const boxWidth = 360;
    const marginX = 64;
    const startY = 118;
    const titleY = 30;
    const gapY = 64;
    const headerH = 32;
    const rowH = 21;
    const footerH = 22;
    const positions = {};
    let maxHeight = 180;

    groupOrder.forEach((group, colIdx) => {
        let y = startY;
        nodes.filter((node) => node.group === group).forEach((node) => {
            const ports = (node.ports || []).map((port, idx) => ({ ...port, _idx: idx, _side: inferPortSide(node, port) }));
            const left = ports.filter((port) => port._side === 'left').sort((a, b) => a._idx - b._idx);
            const right = ports.filter((port) => port._side === 'right').sort((a, b) => a._idx - b._idx);
            const center = ports.filter((port) => port._side === 'center').sort((a, b) => a._idx - b._idx);
            const rows = Math.max(left.length, right.length, center.length, 2);
            const height = headerH + 18 + (rows * rowH) + footerH;
            const x = marginX + (colIdx * colWidth);
            positions[node.id] = { x, y, w: boxWidth, h: height, group, node, left, right, center, colIdx };
            y += height + gapY;
            maxHeight = Math.max(maxHeight, y + 30);
        });
    });

    const width = Math.max(2320, marginX * 2 + groupOrder.length * colWidth);
    const height = maxHeight + 24;
    const parts = [`<svg viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">`];
    parts.push(`<defs>
        <pattern id="archGridSmall" width="20" height="20" patternUnits="userSpaceOnUse">
            <path d="M 20 0 L 0 0 0 20" fill="none" stroke="#efe7d8" stroke-width="1"/>
        </pattern>
        <pattern id="archGridBig" width="100" height="100" patternUnits="userSpaceOnUse">
            <rect width="100" height="100" fill="url(#archGridSmall)"/>
            <path d="M 100 0 L 0 0 0 100" fill="none" stroke="#e0d3bd" stroke-width="1.2"/>
        </pattern>
    </defs>`);
    parts.push(`<rect x="0" y="0" width="${width}" height="${height}" fill="url(#archGridBig)"/>`);

    groupOrder.forEach((group, colIdx) => {
        const laneX = marginX + (colIdx * colWidth) - 18;
        const laneW = boxWidth + 36;
        parts.push(`<rect x="${laneX}" y="12" width="${laneW}" height="${height - 24}" rx="16" fill="${groupFill(group)}" opacity="0.55" stroke="#d6c5a8"/>`);
        parts.push(`<text x="${laneX + 14}" y="${titleY}" fill="#52606d" font-size="13" font-weight="700">${escapeHtml(group)}</text>`);
    });

    nodes.forEach((node) => {
        const pos = positions[node.id];
        if (!pos) return;
        const bodyFill = node.module === 'APB_BUS' ? '#fff9ef' : '#fffefb';
        const headerFill = groupHeaderFill(pos.group);
        parts.push(`<rect x="${pos.x}" y="${pos.y}" width="${pos.w}" height="${pos.h}" rx="14" fill="${bodyFill}" stroke="#bfae8e" stroke-width="1.2"/>`);
        parts.push(`<rect x="${pos.x}" y="${pos.y}" width="${pos.w}" height="${headerH}" rx="14" fill="${headerFill}" stroke="#bfae8e" stroke-width="1.2"/>`);
        parts.push(`<rect x="${pos.x}" y="${pos.y + headerH - 10}" width="${pos.w}" height="10" fill="${headerFill}" stroke="none"/>`);
        parts.push(`<text x="${pos.x + 12}" y="${pos.y + 19}" fill="#1f2933" font-size="13" font-weight="700">${escapeHtml(node.label)}</text>`);
        parts.push(`<text x="${pos.x + 12}" y="${pos.y + 34}" fill="#5b6670" font-size="10.5">${escapeHtml(node.module)}</text>`);
        if (node.sourceText) {
            const btnW = 80;
            const btnH = 18;
            const btnX = pos.x + pos.w - btnW - 12;
            const btnY = pos.y + 8;
            parts.push(`<g class="arch-code-trigger" data-arch-node-code="${escapeHtml(node.id)}">`);
            parts.push(`<rect x="${btnX}" y="${btnY}" width="${btnW}" height="${btnH}" rx="9" fill="#fff8e1" stroke="#d9b25f"/>`);
            parts.push(`<text x="${btnX + (btnW / 2)}" y="${btnY + 12}" fill="#7a4f00" font-size="9.8" text-anchor="middle">Xem nguyen ly</text>`);
            parts.push(`</g>`);
        }
        parts.push(`<text x="${pos.x + pos.w - 12}" y="${pos.y + pos.h - 6}" text-anchor="end" fill="#7b6b55" font-size="10">${escapeHtml(pos.group)}</text>`);

        pos.left.forEach((port, idx) => {
            const py = pos.y + headerH + 16 + (idx * rowH) + 8;
            const portKey = architecturePortKey(node.id, port.name);
            const visual = portVisual(portKey, port);
            const labelW = Math.min(170, Math.max(94, port.name.length * 7.2));
            const hitX = pos.x - 18 - labelW;
            const dash = visual.matched && !visual.selected ? ' stroke-dasharray="4 3"' : '';
            parts.push(`<g class="arch-port-btn" data-port-key="${escapeHtml(portKey)}">`);
            parts.push(`<rect x="${hitX}" y="${py - 10}" width="${labelW + 20}" height="20" rx="10" fill="#ffffff" fill-opacity="0.001" stroke="none"/>`);
            if (visual.selected || visual.matched) parts.push(`<rect x="${hitX}" y="${py - 10}" width="${labelW + 20}" height="20" rx="10" fill="${visual.fill}" stroke="${visual.stroke}" stroke-width="${visual.selected ? 1.8 : 1.2}"${dash}/>`);
            parts.push(`<line x1="${pos.x - 10}" y1="${py}" x2="${pos.x}" y2="${py}" stroke="${visual.stroke}" stroke-width="${visual.selected ? 1.9 : 1.5}"/>`);
            parts.push(`<circle cx="${pos.x}" cy="${py}" r="${visual.selected ? 4.4 : 3.3}" fill="#fffefb" stroke="${visual.stroke}" stroke-width="${visual.selected ? 2.1 : 1.5}"/>`);
            parts.push(`<circle cx="${pos.x}" cy="${py}" r="1.6" fill="${visual.stroke}"/>`);
            parts.push(`<text x="${pos.x + 8}" y="${py + 4}" fill="${visual.label}" font-size="10.8" font-weight="${visual.selected ? '700' : '500'}">${escapeHtml(port.name)}</text>`);
            parts.push(`</g>`);
        });

        pos.right.forEach((port, idx) => {
            const py = pos.y + headerH + 16 + (idx * rowH) + 8;
            const portKey = architecturePortKey(node.id, port.name);
            const visual = portVisual(portKey, port);
            const labelW = Math.min(170, Math.max(94, port.name.length * 7.2));
            const hitX = pos.x + pos.w - 2;
            const dash = visual.matched && !visual.selected ? ' stroke-dasharray="4 3"' : '';
            parts.push(`<g class="arch-port-btn" data-port-key="${escapeHtml(portKey)}">`);
            parts.push(`<rect x="${hitX}" y="${py - 10}" width="${labelW + 20}" height="20" rx="10" fill="#ffffff" fill-opacity="0.001" stroke="none"/>`);
            if (visual.selected || visual.matched) parts.push(`<rect x="${hitX}" y="${py - 10}" width="${labelW + 20}" height="20" rx="10" fill="${visual.fill}" stroke="${visual.stroke}" stroke-width="${visual.selected ? 1.8 : 1.2}"${dash}/>`);
            parts.push(`<line x1="${pos.x + pos.w}" y1="${py}" x2="${pos.x + pos.w + 10}" y2="${py}" stroke="${visual.stroke}" stroke-width="${visual.selected ? 1.9 : 1.5}"/>`);
            parts.push(`<circle cx="${pos.x + pos.w}" cy="${py}" r="${visual.selected ? 4.4 : 3.3}" fill="#fffefb" stroke="${visual.stroke}" stroke-width="${visual.selected ? 2.1 : 1.5}"/>`);
            parts.push(`<circle cx="${pos.x + pos.w}" cy="${py}" r="1.6" fill="${visual.stroke}"/>`);
            parts.push(`<text x="${pos.x + pos.w - 8}" y="${py + 4}" fill="${visual.label}" font-size="10.8" font-weight="${visual.selected ? '700' : '500'}" text-anchor="end">${escapeHtml(port.name)}</text>`);
            parts.push(`</g>`);
        });

        pos.center.forEach((port, idx) => {
            const py = pos.y + headerH + 16 + (idx * rowH) + 8;
            const portKey = architecturePortKey(node.id, port.name);
            const visual = portVisual(portKey, port);
            const pillW = Math.min(130, Math.max(58, port.name.length * 7.2));
            const pillX = pos.x + (pos.w / 2) - (pillW / 2);
            const dash = visual.matched && !visual.selected ? ' stroke-dasharray="4 3"' : '';
            parts.push(`<g class="arch-port-btn" data-port-key="${escapeHtml(portKey)}">`);
            parts.push(`<rect x="${pillX - 14}" y="${py - 12}" width="${pillW + 28}" height="24" rx="12" fill="#ffffff" fill-opacity="0.001" stroke="none"/>`);
            parts.push(`<rect x="${pillX}" y="${py - 9}" width="${pillW}" height="18" rx="9" fill="${visual.fill}" stroke="${visual.stroke}" stroke-width="${visual.selected ? 1.9 : 1.2}"${dash}/>`);
            parts.push(`<text x="${pos.x + (pos.w / 2)}" y="${py + 4}" text-anchor="middle" fill="${visual.label}" font-size="10.5" font-weight="${visual.selected ? '700' : '500'}">${escapeHtml(port.name)}</text>`);
            parts.push(`<line x1="${pillX - 10}" y1="${py}" x2="${pillX}" y2="${py}" stroke="${visual.stroke}" stroke-width="${visual.selected ? 1.8 : 1.4}"/>`);
            parts.push(`<line x1="${pillX + pillW}" y1="${py}" x2="${pillX + pillW + 10}" y2="${py}" stroke="${visual.stroke}" stroke-width="${visual.selected ? 1.8 : 1.4}"/>`);
            parts.push(`</g>`);
        });
    });

    parts.push('</svg>');
    els.archOverview.innerHTML = parts.join('');
    bindArchitectureDiagramInteractions(els.archOverview, 'main', currentView);
}

function architectureHighlightCodeLine(line) {
    const raw = String(line || '');
    const commentIdx = raw.indexOf('//');
    const codePart = commentIdx >= 0 ? raw.slice(0, commentIdx) : raw;
    const commentPart = commentIdx >= 0 ? raw.slice(commentIdx) : '';
    let html = escapeHtml(codePart);

    const rules = [
        { re: /\b(module|endmodule|always_ff|always_comb|always_latch|assign)\b/g, cls: 'arch-code-token-core' },
        { re: /\b(if|else|case|endcase|begin|end|for|generate|endgenerate)\b/g, cls: 'arch-code-token-flow' },
        { re: /\b(input|output|inout|logic|wire|reg|parameter|localparam|interface)\b/g, cls: 'arch-code-token-type' },
        { re: /(\`[A-Za-z_][A-Za-z0-9_]*)/g, cls: 'arch-code-token-macro' },
        { re: /\b(\d+'[bdhoBDHO][0-9a-fA-F_xXzZ]+|\d+)\b/g, cls: 'arch-code-token-number' }
    ];

    rules.forEach((rule) => {
        html = html.replace(rule.re, '<span class="arch-code-token ' + rule.cls + '">$1</span>');
    });

    if (commentPart) {
        html += '<span class="arch-code-token arch-code-token-comment">' + escapeHtml(commentPart) + '</span>';
    }

    return html || '&nbsp;';
}
function architectureCodePreviewRows(sourceText, maxLines) {
    return String(sourceText || '')
        .replace(/\r/g, '')
        .split('\n')
        .slice(0, maxLines)
        .map((line, idx) =>
            '<div class="arch-code-preview-row">' +
                '<span class="arch-code-line-no">' + escapeHtml(String(idx + 1)) + '</span>' +
                '<code class="arch-code-line-text">' + architectureHighlightCodeLine(line) + '</code>' +
            '</div>'
        ).join('');
}

function architectureCodeRoleSummary(node, facts) {
    const traits = [];
    if ((facts.alwaysFF || 0) > 0) traits.push('giu trang thai bang logic tuan tu');
    if ((facts.alwaysComb || 0) > 0 || (facts.assignCount || 0) > 0) traits.push('xu ly logic to hop / wiring');
    if ((facts.instanceCount || 0) > 0) traits.push('ghep noi voi cac block con');
    if ((facts.interfaceCount || 0) > 0) traits.push('di qua interface');
    const role = traits.length ? traits.join(', ') : 'chu yeu la wrapper / giao tiep don gian';
    return node.label + ' thuoc nhom ' + node.group + '. Block nay ' + role + '.';
}

function architectureCodeStyleSummary(facts) {
    const parts = [];
    if (facts.alwaysFF) parts.push(facts.alwaysFF + ' always_ff');
    if (facts.alwaysComb) parts.push(facts.alwaysComb + ' always_comb');
    else if (facts.alwaysAny) parts.push(facts.alwaysAny + ' always');
    if (facts.assignCount) parts.push(facts.assignCount + ' assign');
    if (facts.caseCount) parts.push(facts.caseCount + ' case');
    return parts.length ? parts.join(' | ') : 'Khong co nhieu khoi dieu khien lon; block nay kha gon.';
}

function architectureCodeReadFlow(facts) {
    const steps = [];
    steps.push('Doc danh sach port de hieu block nhan gi va xuat gi.');
    if ((facts.alwaysFF || 0) > 0) steps.push('Xem cac khoi always_ff truoc, vi day la noi giu state / thanh ghi.');
    if ((facts.alwaysComb || 0) > 0 || (facts.assignCount || 0) > 0) steps.push('Sau do xem wiring va logic to hop de hieu luong du lieu.');
    if ((facts.instanceCount || 0) > 0) steps.push('Cuoi cung doi chieu cac instance con de thay block nay dong vai tro wrapper hay controller.');
    return steps.slice(0, 3);
}

function architectureCodeCardHtml() {
    const node = architectureNodeById(state.archCodeNode);
    if (!node || !node.sourceText) return '';
    const facts = node.rtlPrinciple || {};
    const notes = (facts.notes && facts.notes.length)
        ? facts.notes.slice(0, 4)
        : ['Module nay chu yeu la wrapper / wiring, nen phan quan trong nhat la cach cac port va assign duoc ghep lai trong file RTL.'];
    const chips = [
        ['IN', facts.inputCount || 0],
        ['OUT', facts.outputCount || 0],
        ['IO', facts.inoutCount || 0],
        ['IF', facts.interfaceCount || 0],
        ['always_ff', facts.alwaysFF || 0],
        ['always_comb', facts.alwaysComb || 0],
        ['assign', facts.assignCount || 0],
        ['instance', facts.instanceCount || 0]
    ];
    const lineCount = String(node.sourceText || '').replace(/\r/g, '').split('\n').length;
    const preview = architectureCodePreviewRows(node.sourceText, 18);
    const roleSummary = architectureCodeRoleSummary(node, facts);
    const styleSummary = architectureCodeStyleSummary(facts);
    const readFlow = architectureCodeReadFlow(facts);
    const portSummary = 'Input ' + (facts.inputCount || 0) + ' | Output ' + (facts.outputCount || 0) + ' | Inout ' + (facts.inoutCount || 0) + ' | Interface ' + (facts.interfaceCount || 0);
    const childSummary = (facts.instanceCount || 0) > 0
        ? 'Module nay co ' + facts.instanceCount + ' block con ben trong.'
        : 'Module nay khong ghep nhieu block con; ban co the doc tu tren xuong duoi kha nhanh.';
    const stateSummary = (facts.alwaysFF || 0) > 0
        ? 'Co ' + facts.alwaysFF + ' khoi sequential, day la noi giu state / dem / thanh ghi.'
        : 'Khong thay khoi sequential lon; block nay nghieng ve wiring va giao tiep.';
    const logicSummary = ((facts.alwaysComb || 0) + (facts.assignCount || 0)) > 0
        ? 'Logic to hop / glue kha ro, phu hop de doc theo luong input -> output.'
        : 'Logic to hop rat gon, co the doc nhanh tu danh sach port va instance.';

    return '<div class="arch-pin-card primary arch-code-inline">' +
        '<div class="arch-pin-head arch-code-head">' +
            '<div>' +
                '<div class="arch-pin-title">Xem nguyen ly code: ' + escapeHtml(node.label) + ' (' + escapeHtml(node.module) + ')</div>' +
                '<div class="arch-pin-meta"><span class="arch-code-file">' + escapeHtml(node.group) + ' | ' + escapeHtml(node.sourceFile || 'unknown source') + '</span></div>' +
                '<div class="arch-code-summary">' + escapeHtml(roleSummary) + '</div>' +
            '</div>' +
            '<div class="arch-pin-action-row"><button type="button" class="arch-clear-btn" data-arch-close-code>Dong code</button></div>' +
        '</div>' +
        '<div class="arch-code-top-grid">' +
            '<div class="arch-code-pane">' +
                '<div class="arch-code-section-title">Tom tat nhanh</div>' +
                '<div class="arch-code-facts arch-code-facts-tight">' + chips.map((item) => '<span class="arch-code-chip"><b>' + escapeHtml(item[0]) + '</b> ' + escapeHtml(String(item[1])) + '</span>').join('') + '</div>' +
                '<div class="arch-code-mini-list">' +
                    '<div class="arch-code-mini-card"><b>Port & giao tiep</b><span>' + escapeHtml(portSummary) + '</span></div>' +
                    '<div class="arch-code-mini-card"><b>State / sequential</b><span>' + escapeHtml(stateSummary) + '</span></div>' +
                    '<div class="arch-code-mini-card"><b>Logic / wiring</b><span>' + escapeHtml(logicSummary) + '</span></div>' +
                    '<div class="arch-code-mini-card"><b>Ghep noi</b><span>' + escapeHtml(childSummary) + '</span></div>' +
                '</div>' +
            '</div>' +
            '<div class="arch-code-pane">' +
                '<div class="arch-code-section-title">Cach doc block nay</div>' +
                '<div class="arch-code-guide-list">' + readFlow.map((step, idx) => '<div class="arch-code-guide-item"><span>' + escapeHtml(String(idx + 1)) + '</span><div>' + escapeHtml(step) + '</div></div>').join('') + '</div>' +
                '<div class="arch-code-section-sub arch-code-sub-block">Kieu code: ' + escapeHtml(styleSummary) + '</div>' +
            '</div>' +
        '</div>' +
        '<div class="arch-code-pane">' +
            '<div class="arch-code-section-title">Nen chu y</div>' +
            '<div class="arch-code-notes">' + notes.map((note) => '<div class="arch-code-note">' + escapeHtml(note) + '</div>').join('') + '</div>' +
        '</div>' +
        '<div class="arch-code-pane">' +
            '<div class="arch-code-strip">' +
                '<div>' +
                    '<div class="arch-code-section-title">Preview RTL</div>' +
                    '<div class="arch-code-section-sub">18 dong dau tien de dinh vi nhanh. Tong so dong: ' + escapeHtml(String(lineCount)) + '.</div>' +
                '</div>' +
                '<div class="arch-code-path">' + escapeHtml(node.sourceFile || 'unknown source') + '</div>' +
            '</div>' +
            '<div class="arch-code-legend">' +
                '<span class="arch-code-legend-chip core">Core</span>' +
                '<span class="arch-code-legend-chip flow">Flow</span>' +
                '<span class="arch-code-legend-chip type">Type</span>' +
                '<span class="arch-code-legend-chip macro">Macro</span>' +
                '<span class="arch-code-legend-chip comment">Comment</span>' +
            '</div>' +
            '<div class="arch-code-preview">' + preview + '</div>' +
        '</div>' +
        '<details class="arch-code-details">' +
            '<summary>Xem RTL day du</summary>' +
            '<div class="arch-code-details-body">' +
                '<div class="arch-code-section-sub">Ban nen doc phan port, sau do tim always_ff / always_comb / assign / instance de hieu block nhanh hon.</div>' +
                '<pre class="arch-code-source arch-code-source-inline">' + escapeHtml(node.sourceText) + '</pre>' +
            '</div>' +
        '</details>' +
    '</div>';
}

function renderArchitecturePinInfo(viewData) {
    if (!els.archPinInfo) return;
    const currentView = viewData || architectureViewData();
    const selected = architectureSelectedPinData(currentView);
    const codeCard = architectureCodeCardHtml();

    if (!selected) {
        const visiblePortCount = currentView.nodes.reduce((sum, node) => sum + ((node.ports || []).length), 0);
        els.archPinInfo.innerHTML = `
            <div class="arch-pin-card primary">
                <div class="arch-pin-title">Pin Explorer</div>
                <div class="arch-pin-detail">So do nay chi giu block va chan. No khong auto-ve day noi giua cac khoi nua, de ban tu doi chieu va cau day cho chac chan hon.</div>
                <div class="arch-pin-steps">
                    <div class="arch-pin-step"><b>1.</b> Bam vao circle hoac ten chan tren Architecture Diagram.</div>
                    <div class="arch-pin-step"><b>2.</b> Panel nay se hien net va cac endpoint cung net cua chan do.</div>
                    <div class="arch-pin-step"><b>3.</b> Double-click vao so do de mo fullscreen va thu wiring tung cap chan.</div>
                </div>
                <div class="arch-pin-meta">Dang mo ${Math.max(0, currentView.nodes.length - 1)} block / ${visiblePortCount} chan trong view hien tai.</div>
            </div>
            ${codeCard}`;
        return;
    }

    const meta = selected.meta;
    const rawConnections = architectureRawConnectionsForPort(meta.key);
    const codeBtn = meta.node.sourceText ? `<button type="button" class="arch-clear-btn" data-arch-open-code="${escapeHtml(meta.node.id)}">Xem nguyen ly</button>` : '';
    let body = '';

    if (!selected.connections.length) {
        const detail = !state.archShowDirect
            ? 'Ban dang tat Direct hints, nen panel khong hien endpoint nao. Bat lai Direct hints de xem goi y noi day.'
            : (rawConnections.length
                ? 'Pin nay co net trong RTL nhung dang bi an boi bo loc hien tai. Thu bat lai Clock/Reset, APB detail, Board I/O hoac chuyen ve Full RTL.'
                : 'Pin nay khong nam trong direct-net extractor hien tai. Neu no di qua mux/assign top-level, hay xem Glue Summary ben tren.');
        body = `<div class="arch-pin-card"><div class="arch-pin-empty">${escapeHtml(detail)}</div></div>`;
    } else {
        body = selected.connections.map((conn) => {
            const endpointList = conn.others.length
                ? conn.others.map((ep) => {
                    const epMeta = architecturePortMeta(currentView, ep.key) || architecturePortMeta(data.architecture || { nodes: [] }, ep.key);
                    const sub = epMeta
                        ? `${epMeta.node.group} | ${epMeta.port.direction || 'unknown'} | ${epMeta.node.module}`
                        : `${ep.direction || 'unknown'} | ${ep.module || '-'}`;
                    return `<button type="button" class="arch-endpoint-btn" data-arch-target-port="${escapeHtml(ep.key)}"><b>${escapeHtml(ep.key)}</b><span>${escapeHtml(sub)}</span></button>`;
                }).join('')
                : '<div class="arch-pin-empty">Khong co endpoint khac dang hien trong bo loc nay.</div>';
            const kind = conn.isBus ? `Shared net (${conn.endpoints.length} endpoints)` : 'Direct net';
            return `
                <div class="arch-pin-card">
                    <div class="arch-net-head">
                        <span class="signal-chip">${escapeHtml(conn.signal)}</span>
                        <span class="arch-net-kind">${escapeHtml(kind)}</span>
                    </div>
                    <div class="arch-pin-detail">Cac diem duoi day dang cung mot net voi chan ban vua chon. Ban co the bam vao tung endpoint de doi focus sang chan do.</div>
                    <div class="arch-endpoint-list">${endpointList}</div>
                </div>`;
        }).join('');
    }

    const metaText = `${meta.node.group} | ${meta.port.direction || 'unknown'} | ${meta.node.module}${meta.port.type ? ' | ' + meta.port.type : ''}`;
    els.archPinInfo.innerHTML = `
        <div class="arch-pin-card primary">
            <div class="arch-pin-head">
                <div>
                    <div class="arch-pin-title">Selected Pin</div>
                    <div class="arch-pin-path">${escapeHtml(meta.key)}</div>
                </div>
                <div class="arch-pin-action-row">${codeBtn}<button type="button" class="arch-clear-btn" data-arch-clear>Bo chon</button></div>
            </div>
            <div class="arch-pin-meta">${escapeHtml(metaText)}</div>
            <div class="arch-pin-detail">Chan nay dang duoc highlight mau cam tren so do. Cac chan cung net se duoc highlight mau xanh de ban nhin nhanh noi can cau day.</div>
        </div>
        ${body}
        ${codeCard}`;

    bindArchitecturePinPanel(els.archPinInfo, currentView);
}

function architectureSignalColor(signal) {
    if (signal === 'clk_i') return '#64748b';
    if (/^rst|rst_/.test(signal)) return '#7c3aed';
    if (/^adc_|^spi_/.test(signal)) return '#0b7285';
    if (/^uart_/.test(signal)) return '#2563eb';
    if (/^gpio|relay/i.test(signal)) return '#2b8a3e';
    if (/arc|irq_arc|dsp_irq/i.test(signal)) return '#c92a2a';
    if (/wdt/i.test(signal)) return '#a61e4d';
    if (/bist/i.test(signal)) return '#7c4dff';
    if (/^apb_|^(s_paddr|s_pwdata|s_prdata|s_psel|s_penable|s_pwrite|s_pready|s_pslverr|start_addr|end_addr)$/.test(signal)) return '#b7791f';
    return '#6b7280';
}

function architectureWireKey(a, b) {
    return [a, b].sort().join('::');
}

function architectureSignalsForPair(connections, a, b) {
    return (connections || []).filter((conn) => {
        const keys = new Set((conn.endpoints || []).map((ep) => architecturePortKey(ep.node, ep.port)));
        return keys.has(a) && keys.has(b);
    }).map((conn) => conn.signal);
}

function architectureRawSignalsForPair(a, b) {
    return architectureSignalsForPair((data.architecture && data.architecture.connections) || [], a, b);
}

function architectureSetFeedback(kind, title, detail) {
    state.archFeedback = { kind, title, detail };
}

function syncArchitectureModalBodyState() {
    document.body.classList.toggle('arch-modal-open', !!state.archModalOpen);
}

function architectureNodeById(nodeId) {
    return ((data.architecture && data.architecture.nodes) || []).find((node) => node.id === nodeId) || null;
}

function architectureExplainWireFailure(viewData, a, b) {
    if (a === b) return 'Ban dang chon cung mot chan. Hay chon chan thu hai o block khac de noi day.';
    const metaA = architecturePortMeta(viewData, a) || architecturePortMeta(data.architecture || { nodes: [] }, a);
    const metaB = architecturePortMeta(viewData, b) || architecturePortMeta(data.architecture || { nodes: [] }, b);
    const rawA = architectureRawConnectionsForPort(a).map((conn) => conn.signal);
    const rawB = architectureRawConnectionsForPort(b).map((conn) => conn.signal);
    if (metaA && metaB && metaA.node.id === metaB.node.id) return 'Hai chan nay cung nam trong mot block. Playground nay danh cho ket noi giua cac block / module.';
    if (!rawA.length || !rawB.length) return 'Mot trong hai chan nay khong nam trong direct-net extractor. Rat co the no di qua glue logic hoac mux top-level.';
    const aList = Array.from(new Set(rawA)).slice(0, 4).join(', ');
    const bList = Array.from(new Set(rawB)).slice(0, 4).join(', ');
    return `${a} dang thuoc net ${aList || 'khong ro'}, con ${b} dang thuoc net ${bList || 'khong ro'}. Khong co net chung nen noi nhu vay la sai.`;
}

function architectureAttemptWire(viewData, fromKey, toKey) {
    const signals = architectureRawSignalsForPair(fromKey, toKey);
    if (!signals.length) {
        architectureSetFeedback('danger', 'Noi sai', architectureExplainWireFailure(viewData, fromKey, toKey));
        return false;
    }
    const key = architectureWireKey(fromKey, toKey);
    if (state.archManualWires.some((wire) => wire.key === key)) {
        architectureSetFeedback('info', 'Da noi roi', `${fromKey} va ${toKey} da co mot wire hop le trong playground.`);
        return true;
    }
    state.archManualWires.push({ key, from: fromKey, to: toKey, signal: signals[0] });
    architectureSetFeedback('good', 'Noi dung', `${fromKey} va ${toKey} cung net ${signals[0]}. Tool da ve wire nay trong fullscreen.`);
    return true;
}

function architectureResetWires() {
    state.archManualWires = [];
    state.archWireStart = null;
    architectureSetFeedback('info', 'Bat dau lai', 'Hay bam vao mot chan bat ky de chon diem bat dau wiring.');
}

function architectureOpenModal() {
    state.archModalOpen = true;
    syncArchitectureModalBodyState();
    renderArchitectureModalState();
}

function architectureCloseModal() {
    state.archModalOpen = false;
    state.archWireStart = null;
    if (els.archModal) els.archModal.hidden = true;
    syncArchitectureModalBodyState();
}

function architectureOpenCode(nodeId) {
    const node = architectureNodeById(nodeId);
    if (!node || !node.sourceText) return;
    state.archCodeNode = nodeId;
    refreshArchitectureViews();
}

function architectureCloseCode() {
    state.archCodeNode = null;
    if (els.archCodeModal) els.archCodeModal.hidden = true;
    refreshArchitectureViews();
}

function bindArchitecturePinPanel(container, currentView) {
    if (!container) return;
    const clearBtn = container.querySelector('[data-arch-clear]');
    if (clearBtn) {
        clearBtn.addEventListener('click', () => {
            state.archSelectedPin = null;
            refreshArchitectureViews();
        });
    }
    container.querySelectorAll('[data-arch-target-port]').forEach((btn) => {
        btn.addEventListener('click', () => {
            state.archSelectedPin = btn.getAttribute('data-arch-target-port');
            refreshArchitectureViews();
        });
    });
    container.querySelectorAll('[data-arch-open-code]').forEach((btn) => {
        btn.addEventListener('click', () => {
            architectureOpenCode(btn.getAttribute('data-arch-open-code'));
        });
    });
    container.querySelectorAll('[data-arch-close-code]').forEach((btn) => {
        btn.addEventListener('click', () => {
            architectureCloseCode();
        });
    });
}

function renderArchitectureWirePanel(viewData) {
    if (!els.archWirePanel) return;
    const currentView = viewData || architectureViewData();
    const feedback = state.archFeedback || { kind: 'info', title: 'Huong dan', detail: 'Hay bam vao 2 chan lien tiep de noi day.' };
    const visibleWires = state.archManualWires.filter((wire) => architecturePortMeta(currentView, wire.from) && architecturePortMeta(currentView, wire.to));
    const wireRows = visibleWires.length
        ? visibleWires.map((wire) => `<div class="arch-wire-item"><span class="signal-chip">${escapeHtml(wire.signal)}</span><div class="arch-wire-item-path">${escapeHtml(wire.from)}<br>${escapeHtml(wire.to)}</div></div>`).join('')
        : '<div class="arch-wire-empty">Chua co wire nao duoc ve. Hay thu noi 2 chan giua 2 block.</div>';
    els.archWirePanel.innerHTML = `
        <div class="arch-wire-card">
            <div class="arch-wire-title">Wiring Playground</div>
            <div class="arch-wire-guide">Bam 2 chan lien tiep. Neu dung cung net trong RTL, tool moi ve wire.</div>
            <div class="arch-wire-start"><b>Diem bat dau:</b> ${state.archWireStart ? escapeHtml(state.archWireStart) : 'Chua chon'}</div>
            <div class="arch-wire-status ${escapeHtml(feedback.kind || 'info')}"><b>${escapeHtml(feedback.title || 'Info')}</b><span>${escapeHtml(feedback.detail || '')}</span></div>
            <div class="arch-wire-subtitle">Wires da ve (${visibleWires.length})</div>
            <div class="arch-wire-list">${wireRows}</div>
        </div>`;
}

function renderArchitectureModalWires() {
    if (!els.archModalOverview || !state.archModalOpen) return;
    const baseSvg = els.archModalOverview.querySelector('svg');
    if (!baseSvg) return;
    const old = els.archModalOverview.querySelector('.arch-wire-overlay');
    if (old) old.remove();
    const viewBox = (baseSvg.getAttribute('viewBox') || '').split(/\s+/).map((item) => Number(item));
    if (viewBox.length !== 4 || viewBox.some((item) => !Number.isFinite(item))) return;
    const [vx, vy, vw, vh] = viewBox;
    const NS = 'http://www.w3.org/2000/svg';
    const overlay = document.createElementNS(NS, 'svg');
    overlay.setAttribute('class', 'arch-wire-overlay');
    overlay.setAttribute('viewBox', `${vx} ${vy} ${vw} ${vh}`);
    overlay.setAttribute('width', String(vw));
    overlay.setAttribute('height', String(vh));
    overlay.setAttribute('preserveAspectRatio', 'xMidYMid meet');

    function anchorFor(portKey) {
        const group = els.archModalOverview.querySelector(`[data-port-key="${portKey}"]`);
        if (!group) return null;
        const circles = group.querySelectorAll('circle');
        const dot = circles.length ? circles[0] : null;
        if (!dot) return null;
        return {
            x: Number(dot.getAttribute('cx')),
            y: Number(dot.getAttribute('cy'))
        };
    }

    state.archManualWires.forEach((wire, idx) => {
        const a = anchorFor(wire.from);
        const b = anchorFor(wire.to);
        if (!a || !b) return;
        const dir = b.x >= a.x ? 1 : -1;
        const spread = ((idx % 7) - 3) * 18;
        const midX = Math.max(Math.min(((a.x + b.x) / 2) + spread, Math.max(a.x, b.x) - 26), Math.min(a.x, b.x) + 26);
        const d = `M ${a.x} ${a.y} L ${a.x + (dir * 22)} ${a.y} L ${midX} ${a.y} L ${midX} ${b.y} L ${b.x - (dir * 22)} ${b.y} L ${b.x} ${b.y}`;
        const path = document.createElementNS(NS, 'path');
        path.setAttribute('d', d);
        path.setAttribute('fill', 'none');
        path.setAttribute('stroke', architectureSignalColor(wire.signal));
        path.setAttribute('stroke-width', '2.6');
        path.setAttribute('opacity', '0.92');
        overlay.appendChild(path);
    });
    els.archModalOverview.appendChild(overlay);
}

function renderArchitectureModalState(viewData) {
    if (!els.archModal || !els.archModalOverview) return;
    if (!state.archModalOpen) {
        els.archModal.hidden = true;
        syncArchitectureModalBodyState();
        return;
    }
    const currentView = viewData || architectureViewData();
    els.archModal.hidden = false;
    els.archModalOverview.innerHTML = els.archOverview.innerHTML;
    bindArchitectureDiagramInteractions(els.archModalOverview, 'modal', currentView);
    renderArchitectureModalWires();
    renderArchitectureWirePanel(currentView);
    if (els.archModalPinInfo) {
        els.archModalPinInfo.innerHTML = els.archPinInfo ? els.archPinInfo.innerHTML : '';
        bindArchitecturePinPanel(els.archModalPinInfo, currentView);
    }
    syncArchitectureModalBodyState();
}

function bindArchitectureDiagramInteractions(container, mode, viewData) {
    if (!container) return;
    container.querySelectorAll('[data-port-key]').forEach((el) => {
        el.addEventListener('click', (event) => {
            event.stopPropagation();
            const key = el.getAttribute('data-port-key');
            if (!key) return;
            if (mode === 'modal') {
                state.archSelectedPin = key;
                if (!state.archWireStart) {
                    state.archWireStart = key;
                    architectureSetFeedback('info', 'Chon chan thu hai', `${key} dang la diem bat dau. Hay bam vao chan thu hai de thu noi day.`);
                } else if (state.archWireStart === key) {
                    state.archWireStart = null;
                    architectureSetFeedback('info', 'Da bo chan bat dau', 'Hay chon mot chan khac neu ban muon bat dau wiring tu dau.');
                } else {
                    const ok = architectureAttemptWire(viewData, state.archWireStart, key);
                    if (ok) state.archWireStart = null;
                }
                refreshArchitectureViews();
                return;
            }
            state.archSelectedPin = state.archSelectedPin === key ? null : key;
            refreshArchitectureViews();
        });
    });
    container.querySelectorAll('[data-arch-node-code]').forEach((el) => {
        el.addEventListener('click', (event) => {
            event.stopPropagation();
            architectureOpenCode(el.getAttribute('data-arch-node-code'));
        });
    });
    const svg = container.querySelector('svg');
    if (!svg) return;
    if (mode === 'main') {
        svg.addEventListener('dblclick', (event) => {
            const target = event.target;
            if (target && typeof target.closest === 'function' && target.closest('[data-arch-node-code]')) return;
            architectureOpenModal();
        });
    }
    svg.addEventListener('click', (event) => {
        const target = event.target;
        if (target && typeof target.closest === 'function') {
            if (target.closest('[data-port-key]') || target.closest('[data-arch-node-code]')) return;
        }
        if (mode === 'modal') {
            state.archSelectedPin = null;
            state.archWireStart = null;
            architectureSetFeedback('info', 'Da xoa lua chon tam thoi', 'Hay bam lai vao mot chan de bat dau wiring.');
        } else {
            state.archSelectedPin = null;
        }
        refreshArchitectureViews();
    });
}

function renderArchitectureCodeModal() {
    if (els.archCodeModal) els.archCodeModal.hidden = true;
}

function refreshArchitectureViews() {
    const currentView = architectureViewData();
    if (state.archSelectedPin && !architecturePortMeta(currentView, state.archSelectedPin)) state.archSelectedPin = null;
    if (state.archWireStart && !architecturePortMeta(currentView, state.archWireStart)) state.archWireStart = null;
    renderArchitecturePanel(currentView);
    renderArchitectureCodeModal();
}

function renderModuleCatalog() {
    const arch = data.architecture || { nodes: [] };
    const groupRank = new Map((arch.groupOrder || []).map((group, idx) => [group, idx]));
    const sortedNodes = (arch.nodes || []).slice().sort((a, b) => (groupRank.get(a.group) ?? 999) - (groupRank.get(b.group) ?? 999) || a.label.localeCompare(b.label));
    const cards = sortedNodes.map((node) => {
        const groups = { input: [], output: [], inout: [], interface: [], ref: [], unknown: [] };
        (node.ports || []).forEach((port) => {
            const dir = groups[port.direction] ? port.direction : 'unknown';
            groups[dir].push(port);
        });
        const section = (label, key, cls) => groups[key].length ? `<div class="port-group"><div class="port-head ${cls}">${label}</div>${groups[key].map((p) => `<div class="port-row"><span class="port-name">${escapeHtml(p.name)}</span><span class="port-type">${escapeHtml(p.type || '-')}</span></div>`).join('')}</div>` : '';
        return `<div class="module-card"><div class="module-title">${escapeHtml(node.label)}</div><div class="module-sub">${escapeHtml(node.module)} | ${escapeHtml(node.group)}</div>${section('Inputs', 'input', 'in')}${section('Outputs', 'output', 'out')}${section('Inouts', 'inout', 'io')}${section('Interfaces', 'interface', 'if')}${section('Other', 'unknown', 'unk')}</div>`;
    });
    els.moduleCatalog.innerHTML = cards.join('');
}

function renderConnectionCatalog() {
    const arch = data.architecture || { connections: [] };
    const sorted = (arch.connections || []).slice().sort((a, b) => {
        const aDirect = (a.endpoints || []).length >= 2 ? 0 : 1;
        const bDirect = (b.endpoints || []).length >= 2 ? 0 : 1;
        return aDirect - bDirect || a.signal.localeCompare(b.signal);
    });
    const rows = sorted.map((conn) => {
        const direct = (conn.endpoints || []).length >= 2;
        const endpoints = conn.endpoints.map((ep) => `${escapeHtml(ep.node)}.<b>${escapeHtml(ep.port)}</b> <span class="endpoint-dir">(${escapeHtml(ep.direction)})</span>`).join('<br>');
        const status = direct ? '<span class="status-chip ok">direct</span>' : '<span class="status-chip warn">internal/glue</span>';
        return `<tr><td><span class="signal-chip">${escapeHtml(conn.signal)}</span></td><td>${status}</td><td>${endpoints}</td></tr>`;
    });
    els.connectionBody.innerHTML = rows.join('') || '<tr><td colspan="3">Khong co net nao duoc trich ra.</td></tr>';
}

function renderGlue() {
    const arch = data.architecture || { glue: [] };
    if (!arch.glue || !arch.glue.length) {
        els.glueList.innerHTML = '<div class="muted">Khong tim thay assign top-level nao.</div>';
        return;
    }
    els.glueList.innerHTML = arch.glue.map((item) => `<div class="glue-card"><div class="glue-lhs">${escapeHtml(item.lhs)}</div><div class="glue-arrow">=</div><div class="glue-rhs">${escapeHtml(item.rhs)}</div></div>`).join('');
}

function renderStaticArchitecture() {
    refreshArchitectureViews();
    renderModuleCatalog();
    renderConnectionCatalog();
    renderGlue();
}

function bind() {
    els.summaryCards = $("summaryCards");
    els.archOverview = $("archOverview");
    els.archToolbar = $("archToolbar");
    els.archViewFull = $("archViewFull");
    els.archViewPresentation = $("archViewPresentation");
    els.archOpenFullscreen = $("archOpenFullscreen");
    els.archShowDirect = $("archShowDirect");
    els.archShowClockReset = $("archShowClockReset");
    els.archShowApb = $("archShowApb");
    els.archShowIo = $("archShowIo");
    els.archShowGlueSummary = $("archShowGlueSummary");
    els.archStatus = $("archStatus");
    els.archGlueSummary = $("archGlueSummary");
    els.archPinInfo = $("archPinInfo");
    els.archModal = $("archFullscreenModal");
    els.archModalOverview = $("archModalOverview");
    els.archWirePanel = $("archWirePanel");
    els.archModalPinInfo = $("archModalPinInfo");
    els.archCloseModal = $("archCloseModal");
    els.archResetWires = $("archResetWires");
    els.archCodeModal = $("archCodeModal");
    els.archCodeTitle = $("archCodeTitle");
    els.archCodeMeta = $("archCodeMeta");
    els.archCodeFacts = $("archCodeFacts");
    els.archCodeNotes = $("archCodeNotes");
    els.archCodeSource = $("archCodeSource");
    els.archCloseCode = $("archCloseCode");
    els.moduleCatalog = $("moduleCatalog");
    els.connectionBody = $("connectionBody");
    els.glueList = $("glueList");
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

    els.archViewFull.addEventListener("click", () => setArchitectureView('full'));
    els.archViewPresentation.addEventListener("click", () => setArchitectureView('presentation'));
    if (els.archOpenFullscreen) {
        els.archOpenFullscreen.addEventListener("click", () => architectureOpenModal());
    }
    els.archShowDirect.addEventListener("change", () => { state.archShowDirect = els.archShowDirect.checked; refreshArchitectureViews(); });
    els.archShowClockReset.addEventListener("change", () => { state.archShowClockReset = els.archShowClockReset.checked; refreshArchitectureViews(); });
    els.archShowApb.addEventListener("change", () => { state.archShowApb = els.archShowApb.checked; refreshArchitectureViews(); });
    els.archShowIo.addEventListener("change", () => { state.archShowIo = els.archShowIo.checked; refreshArchitectureViews(); });
    els.archShowGlueSummary.addEventListener("change", () => { state.archShowGlueSummary = els.archShowGlueSummary.checked; refreshArchitectureViews(); });

    if (els.archCloseModal) els.archCloseModal.addEventListener('click', architectureCloseModal);
    if (els.archResetWires) els.archResetWires.addEventListener('click', () => {
        architectureResetWires();
        refreshArchitectureViews();
    });
    if (els.archModal) {
        els.archModal.addEventListener('click', (event) => {
            if (event.target === els.archModal) architectureCloseModal();
        });
    }
    if (els.archCloseCode) els.archCloseCode.addEventListener('click', architectureCloseCode);
    if (els.archCodeModal) {
        els.archCodeModal.addEventListener('click', (event) => {
            if (event.target === els.archCodeModal) architectureCloseCode();
        });
    }

    els.applyRange.addEventListener("click", applyInputWindow);
    els.resetView.addEventListener("click", () => {
        stopPlayCursor();
        stopEventFollow();
        setWindow(data.meta.defaultStart, data.meta.defaultEnd);
    });
    els.sizeSelect.addEventListener("change", applyWindowSize);
    els.centerSlider.addEventListener("input", () => {
        const center = (Number(els.centerSlider.value) / 1000) * Math.max(1, data.meta.maxTime);
        setCenter(center);
    });
    els.eventJump.addEventListener("change", () => {
        const idx = Number(els.eventJump.value);
        if (!Number.isFinite(idx)) return;
        selectEventIndex(idx, { stopPlay: true, stopFollow: true, focus: true });
    });
    els.signalGrid.addEventListener("scroll", () => {
        state.signalScrollTop = els.signalGrid.scrollTop;
    });

    document.addEventListener('keydown', (event) => {
        if (event.key !== 'Escape') return;
        if (state.archCodeNode) {
            architectureCloseCode();
            return;
        }
        if (state.archModalOpen) {
            architectureCloseModal();
        }
    });
}

function renderRuntimeViews() {
    renderBlocks();
    renderSignals();
    renderTiming();
    renderExplain();
}

function renderAll() {
    syncControls();
    renderSummary();
    renderRuntimeViews();
    renderEvents();
}

function boot() {
    bind();
    renderStaticArchitecture();
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
window.addEventListener("beforeunload", stopPlayCursor);
window.addEventListener("beforeunload", stopEventFollow);
})();
















































