import * as moon from "mbt:f4ah6o/gpui/examples/browser_layout";
import evidence from "../../layout_playground/evidence.json";
import projections from "../../layout_playground/projection_evidence.json";

const $ = (selector) => document.querySelector(selector);
const format = (value) => Number(value.toFixed(4)).toString();
const ids = JSON.parse(moon.gpui_layout_presets());
let snapshot;
let pending = 0;

function schedule() {
  if (!pending) pending = requestAnimationFrame(render);
}

function childControls(index) {
  const name = index === 0 ? "A" : "B";
  const fieldset = document.createElement("fieldset");
  const legend = document.createElement("legend");
  legend.textContent = `Child ${name}`;
  fieldset.append(legend);
  const fields = document.createElement("div");
  fields.className = "child-fields";
  for (const [field, label, maximum, step] of [
    ["basis", "Basis", 200, 1], ["grow", "Grow", 4, 0.25],
    ["shrink", "Shrink", 4, 0.25], ["minimum", "Min", 200, 1],
    ["maximum", "Max", 200, 1],
  ]) {
    const wrapper = document.createElement("label");
    wrapper.textContent = label;
    const input = document.createElement("input");
    input.type = "number";
    input.min = "0";
    input.max = String(maximum);
    input.step = String(step);
    input.dataset.field = field;
    input.dataset.child = String(index);
    input.setAttribute("aria-label", `Child ${name} ${label.toLowerCase()}`);
    if (field === "maximum") input.placeholder = "Unbounded";
    wrapper.append(input);
    fields.append(wrapper);
  }
  fieldset.append(fields);
  return fieldset;
}

function syncControls() {
  const config = snapshot.config;
  $("#preset").value = String(snapshot.selected);
  for (const control of document.querySelectorAll("[data-field]")) {
    const { field, child } = control.dataset;
    const value = child !== undefined ? config.children[Number(child)][field]
      : field === "direction" ? Number(config.column) : config[field];
    if (control !== document.activeElement) control.value = value ?? "";
  }
  $("#extent-value").textContent = `${format(config.extent)} pt`;
  $("#cross-value").textContent = `${format(config.cross)} pt`;
  $("#gap-value").textContent = `${format(config.gap)} pt`;
}

function viewport(groups) {
  const all = groups.flat();
  const left = Math.min(0, ...all.map(([x]) => x));
  const top = Math.min(0, ...all.map(([, y]) => y));
  return {
    left, top,
    width: Math.max(...all.map(([x, , w]) => x + w)) - left,
    height: Math.max(...all.map(([, y, , h]) => y + h)) - top,
  };
}

function paint(canvas, bounds, view) {
  const rect = canvas.getBoundingClientRect();
  const scale = window.devicePixelRatio || 1;
  canvas.width = Math.max(1, Math.round(rect.width * scale));
  canvas.height = Math.max(1, Math.round(rect.height * scale));
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Canvas 2D context is unavailable.");
  context.setTransform(scale, 0, 0, scale, 0, 0);
  const zoom = Math.min((rect.width - 48) / Math.max(view.width, 1), (rect.height - 54) / Math.max(view.height, 1));
  const ox = (rect.width - view.width * zoom) / 2 - view.left * zoom;
  const oy = (rect.height - view.height * zoom) / 2 - view.top * zoom;
  const [x, y, w, h] = bounds[0];
  context.fillStyle = "#ffffffa8";
  context.fillRect(ox + x * zoom, oy + y * zoom, w * zoom, h * zoom);
  context.strokeStyle = "#879b7b";
  context.setLineDash([4, 3]);
  context.strokeRect(ox + x * zoom, oy + y * zoom, w * zoom, h * zoom);
  context.setLineDash([]);
  for (let i = 1; i < bounds.length; i += 1) {
    const [cx, cy, cw, ch] = bounds[i];
    const bx = ox + cx * zoom;
    const by = oy + cy * zoom;
    context.fillStyle = i === 1 ? "#6b8751" : "#cb9465";
    context.fillRect(bx, by, cw * zoom, ch * zoom);
    context.strokeStyle = i === 1 ? "#486538" : "#ab794d";
    context.strokeRect(bx, by, cw * zoom, ch * zoom);
    if (cw * zoom >= 16 && ch * zoom >= 18) {
      context.fillStyle = "#ffffff";
      context.font = "12px system-ui, sans-serif";
      context.fillText(i === 1 ? "A" : "B", bx + 5, by + 15);
    }
  }
  context.fillStyle = "#53654c";
  context.font = "10px ui-monospace, monospace";
  context.fillText(`${format(w)} × ${format(h)} pt · fit to view`, 12, rect.height - 12);
  canvas.dataset.bounds = JSON.stringify(bounds);
}

function showFailure(error) {
  $("#diagnostic").hidden = false;
  $("#diagnostic").textContent = `Layout Playground: ${error.message} Reload this page to retry.`;
  $("#runtime").textContent = "Unavailable";
  for (const control of document.querySelectorAll("input, select, button")) control.disabled = true;
}

function render() {
  pending = 0;
  try {
    snapshot = JSON.parse(moon.gpui_layout_snapshot());
    syncControls();
    $("#case-id").textContent = snapshot.id;
    const status = snapshot.comparison.status;
    const full = snapshot.projection === "bounds";
    const projectionLabel = snapshot.projection === "main-origins"
      ? "main-axis origins" : "cross-axis line origins";
    $("#comparison").dataset.status = status;
    $("#comparison").textContent = status === "unmeasured"
      ? "Custom · not compared"
      : status === "match"
        ? (full ? "Matches recorded GPUI" : "Matches recorded GPUI origins")
        : (full ? "Differs from recorded GPUI" : "Differs from recorded GPUI origins");
    $("#comparison-help").textContent = status === "unmeasured"
      ? "Custom inputs have no upstream measurement here. Reset or restore every original input to compare. Saved evidence is never recomputed."
      : full
        ? "All live x/y/width/height coordinates are compared with saved upstream bounds (tolerance 0.0001 pt). GPUI is not running here."
        : "Only the two " + projectionLabel + " are compared (tolerance 0.0001 pt). Complete GPUI rectangles were not published with this excerpt.";
    const dimension = snapshot.config.column ? 3 : 2;
    $("#size-a").textContent = format(snapshot.bounds[1][dimension]) + " pt";
    $("#size-b").textContent = format(snapshot.bounds[2][dimension]) + " pt";
    $("#delta").textContent = snapshot.comparison.maxDelta === null ? "—" : format(snapshot.comparison.maxDelta) + " pt";
    $("#overflow").textContent = snapshot.overflow ? "Overflow remains" : "Within container";
    paint($("#live-canvas"), snapshot.bounds, viewport([snapshot.bounds]));
    $("#live-canvas").dataset.config = JSON.stringify(snapshot.config);
    $("#record-grid").hidden = !full;
    $("#projection-evidence").hidden = full;
    $("#projection-source").hidden = full;
    $("#record-heading").textContent = full ? "A fix you can see." : "An origin-only comparison.";
    $("#bounds-caption").textContent = full
      ? "Exact bounds · [x, y, width, height] · logical points"
      : "Live bounds only · saved GPUI full rectangles are unavailable";
    if (full) {
      const recordedView = viewport([snapshot.upstream, snapshot.before]);
      paint($("#upstream-canvas"), snapshot.upstream, recordedView);
      paint($("#before-canvas"), snapshot.before, recordedView);
      const axis = snapshot.recordedConfig.column ? 3 : 2;
      const pair = (boxes) => boxes.slice(1).map((box) => format(box[axis])).join(" / ");
      const changed = JSON.stringify(snapshot.upstream) !== JSON.stringify(snapshot.before);
      $("#history-explanation").textContent = changed
        ? "Recorded main-axis sizes: before " + pair(snapshot.before) + " pt → GPUI " + pair(snapshot.upstream) + " pt. The old engine clamped once; #79 redistributes remaining space after limits freeze a child."
        : "Preservation control: both recorded engines already returned " + pair(snapshot.upstream) + " pt. Fractional shares, constrained space and unavoidable overflow must retain their measured behavior.";
    } else {
      const origins = (values) => "[" + values.map(format).join(", ") + "] pt";
      $("#projection-evidence").textContent =
        "GPUI published " + projectionLabel + ": " + origins(snapshot.recordedOrigins) + ". " +
        "Live MoonBit " + projectionLabel + ": " + origins(snapshot.liveOrigins) + ". " +
        "Only these origins are saved; no GPUI root/child rectangles or before-fix rectangles are reconstructed.";
      $("#projection-source").href = "https://github.com/" + projections.source_repository +
        "/blob/" + projections.source_revision + "/" + snapshot.recordSource;
      $("#history-explanation").textContent =
        "The cited GPUI comparison ran separately. Selecting this case does not execute Rust/GPUI or replay old code.";
      delete $("#upstream-canvas").dataset.bounds;
      delete $("#before-canvas").dataset.bounds;
    }
    const rows = [1, 2].map((i) => {
      const row = document.createElement("tr");
      const recordedCells = full
        ? [snapshot.upstream, snapshot.before].map((boxes) => "[" + boxes[i].map(format).join(", ") + "]")
        : ["Not recorded (origins only)", "Not recorded"];
      for (const text of [
        i === 1 ? "A" : "B",
        "[" + snapshot.bounds[i].map(format).join(", ") + "]",
        ...recordedCells,
      ]) {
        const cell = document.createElement("td");
        cell.textContent = text;
        row.append(cell);
      }
      return row;
    });
    $("#bounds-table").replaceChildren(...rows);
    $("#runtime").textContent = "● MoonBit JS · running";
  } catch (error) { showFailure(error); }
}

function select(index) {
  if (!moon.gpui_layout_select(index)) throw new Error("Unknown measured case.");
  $("#input-message").textContent = "";
  for (const control of document.querySelectorAll('[aria-invalid="true"]')) {
    control.setAttribute("aria-invalid", "false");
  }
  render();
}

try {
  for (const [i, id] of ids.entries()) {
    const option = document.createElement("option");
    option.value = String(i);
    option.textContent = id.replace(/^limits-/, "").replaceAll("-", " ");
    $("#preset").append(option);
  }
  $("#child-controls").append(childControls(0), childControls(1));
  for (const control of document.querySelectorAll("[disabled]")) control.disabled = false;
  $("#preset").addEventListener("change", (event) => select(Number(event.target.value)));
  $("#reset").addEventListener("click", () => select(snapshot.selected));
  for (const button of document.querySelectorAll("[data-case]")) {
    button.addEventListener("click", () => select(ids.indexOf(button.dataset.case)));
  }
  for (const control of document.querySelectorAll("[data-field]")) {
    control.addEventListener("input", () => {
      const { field, child } = control.dataset;
      const value = field === "maximum" && control.value === "" ? -1 : control.value === "" ? NaN : Number(control.value);
      const accepted = moon.gpui_layout_change(field, Number(child ?? -1), value);
      control.setAttribute("aria-invalid", String(!accepted));
      $("#input-message").textContent = accepted ? "" : "Edit not applied. Use values in range and min ≤ max.";
      if (accepted) schedule();
    });
    control.addEventListener("blur", () => {
      if (control.getAttribute("aria-invalid") === "true") {
        control.setAttribute("aria-invalid", "false");
        schedule();
      }
    });
  }
  const repo = `https://github.com/${evidence.source_repository}/blob/${evidence.source_revision}`;
  $("#evidence-link").href = `${repo}/FLEX_LIMIT_RESULTS.md`;
  $("#record-link").href = `${repo}/${evidence.source_path}`;
  for (const [id, revision] of [["upstream", evidence.upstream_revision], ["candidate", evidence.candidate_revision], ["baseline", evidence.baseline_revision], ["suite", evidence.suite_revision]]) {
    $(`#${id}-revision`).textContent = revision.slice(0, 12);
    $(`#${id}-revision`).title = revision;
  }
  new ResizeObserver(schedule).observe($(".workspace"));
  window.addEventListener("resize", schedule);
  window.addEventListener("pagehide", () => { cancelAnimationFrame(pending); pending = 0; });
  window.addEventListener("pageshow", schedule);
  render();
} catch (error) { showFailure(error); }
