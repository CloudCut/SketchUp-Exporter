var partsData = [];
var materialsData = [];
var thicknessesData = [];
var displayUnit = "mm";

function mmToIn(val) {
  return (val / 25.4);
}

function formatThickness(mm) {
  if (displayUnit === "in") {
    return mmToIn(mm).toFixed(3) + '"';
  }
  return mm + " mm";
}

// Part footprint (width x height) in the current display unit.
function formatDims(w, h) {
  if (displayUnit === "in") {
    return mmToIn(w).toFixed(3) + '" &times; ' + mmToIn(h).toFixed(3) + '"';
  }
  return w + " &times; " + h + " mm";
}

function pad2(n) {
  return ("0" + n).slice(-2);
}

// Detail line under each part name: footprint (when known) then thickness.
function partDetailHtml(p) {
  var s = "";
  if (p.width > 0) {
    s += '<span class="dim">' + formatDims(p.width, p.height) + '</span>' +
         '<span class="sep">&middot;</span>';
  }
  s += formatThickness(p.thickness);
  return s;
}

function renderParts() {
  var listEl = document.getElementById("partsList");
  listEl.innerHTML = "";
  for (var i = 0; i < partsData.length; i++) {
    var p = partsData[i];
    var row = document.createElement("div");
    row.className = "part-row";
    row.innerHTML =
      '<div class="part-idx">' + pad2(i + 1) + '</div>' +
      '<div class="part-main">' +
        '<div class="part-name">' + escapeHtml(p.name) + '</div>' +
        '<div class="part-detail">' + partDetailHtml(p) + '</div>' +
      '</div>';
    listEl.appendChild(row);
  }
  var countEl = document.getElementById("partsCount");
  if (countEl) {
    countEl.textContent = partsData.length + (partsData.length === 1 ? " solid" : " solids");
  }
}

// Build one filter chip. filterName is the input name getChecked() reads.
function chipHtml(filterName, value, labelText, checked) {
  return '<label class="chip">' +
    '<input type="checkbox" name="' + filterName + '" value="' + escapeHtml(String(value)) + '"' +
    (checked ? ' checked' : '') + '>' +
    '<span>' + escapeHtml(labelText) + '</span>' +
  '</label>';
}

// Leading "All" chip that bulk-toggles every chip in the group.
function allChipHtml(group, checked) {
  return '<label class="chip chip-all">' +
    '<input type="checkbox"' + (checked ? ' checked' : '') +
    ' onchange="toggleAll(\'' + group + '\', this.checked)">' +
    '<span>All</span>' +
  '</label>';
}

function renderMaterials() {
  var el = document.getElementById("materialFilters");
  el.innerHTML = "";
  var html = allChipHtml("materials", true);
  for (var j = 0; j < materialsData.length; j++) {
    html += chipHtml("material", materialsData[j], materialsData[j], true);
  }
  el.innerHTML = html;
}

function renderThicknesses() {
  var el = document.getElementById("thicknessFilters");
  // Preserve checked state across unit toggles (labels change, values don't).
  var checked = getChecked("thickness");
  var hasState = checked.length > 0 || el.querySelector('input[name="thickness"]') !== null;
  var html = allChipHtml("thicknesses", true);
  for (var k = 0; k < thicknessesData.length; k++) {
    var val = thicknessesData[k];
    var isChecked = !hasState || checked.indexOf(String(val)) !== -1;
    html += chipHtml("thickness", val, formatThickness(val), isChecked);
  }
  el.innerHTML = html;
}

function initDialog(parts, materials, thicknesses, defaultUnit, version) {
  partsData = parts;
  materialsData = materials;
  thicknessesData = thicknesses;
  displayUnit = defaultUnit || "mm";

  if (version) {
    document.getElementById("app-version").textContent = "v" + version;
  }

  if (defaultUnit === "in") {
    document.getElementById("unitIn").checked = true;
  } else {
    document.getElementById("unitMm").checked = true;
  }

  renderParts();
  renderMaterials();
  renderThicknesses();
}

// Units changed: re-render the unit-dependent views (part footprints and
// thickness chip labels). Material chips don't depend on unit.
function refreshDisplay() {
  displayUnit = document.querySelector('input[name="units"]:checked').value;
  renderParts();
  renderThicknesses();
}

function toggleAll(groupName, checked) {
  var name = groupName === "materials" ? "material" : "thickness";
  var boxes = document.querySelectorAll('input[name="' + name + '"]');
  for (var i = 0; i < boxes.length; i++) {
    boxes[i].checked = checked;
  }
}

function getChecked(name) {
  var boxes = document.querySelectorAll('input[name="' + name + '"]:checked');
  var vals = [];
  for (var i = 0; i < boxes.length; i++) {
    vals.push(boxes[i].value);
  }
  return vals;
}

function doExport() {
  var units = document.querySelector('input[name="units"]:checked').value;
  var materials = getChecked("material");
  var thicknesses = getChecked("thickness");

  if (materials.length === 0) {
    alert("Please select at least one material.");
    return;
  }
  if (thicknesses.length === 0) {
    alert("Please select at least one thickness.");
    return;
  }

  var options = {
    format: "json",
    units: units,
    materials: materials,
    thicknesses: thicknesses
  };

  sketchup.doExport(JSON.stringify(options));
}

function doCancel() {
  sketchup.doCancel();
}

function escapeHtml(str) {
  var div = document.createElement("div");
  div.appendChild(document.createTextNode(str));
  return div.innerHTML;
}

// Request initial data from Ruby
document.addEventListener("DOMContentLoaded", function() {
  sketchup.initData();
});
