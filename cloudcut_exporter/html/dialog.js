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

function initDialog(parts, materials, thicknesses, defaultUnit, version) {
  partsData = parts;
  materialsData = materials;
  thicknessesData = thicknesses;
  displayUnit = defaultUnit || "mm";

  // Set version in header
  if (version) {
    document.getElementById("app-title").textContent = "CloudCut v" + version;
  }

  // Set default unit
  if (defaultUnit === "in") {
    document.getElementById("unitIn").checked = true;
  } else {
    document.getElementById("unitMm").checked = true;
  }

  // Populate parts list
  var listEl = document.getElementById("partsList");
  listEl.innerHTML = "";
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i];
    var row = document.createElement("div");
    row.className = "part-row";
    row.innerHTML = '<span class="part-name">' + escapeHtml(p.name) + '</span>' +
      '<span class="part-detail">' + formatThickness(p.thickness) +
      (p.material !== "(none)" ? ' — ' + escapeHtml(p.material) : '') +
      '</span>';
    listEl.appendChild(row);
  }

  // Populate material filters
  var matEl = document.getElementById("materialFilters");
  matEl.innerHTML = "";
  for (var j = 0; j < materials.length; j++) {
    var lbl = document.createElement("label");
    lbl.innerHTML = '<input type="checkbox" name="material" value="' +
      escapeHtml(materials[j]) + '" checked> ' + escapeHtml(materials[j]);
    matEl.appendChild(lbl);
  }

  // Populate thickness filters
  var thkEl = document.getElementById("thicknessFilters");
  thkEl.innerHTML = "";
  for (var k = 0; k < thicknesses.length; k++) {
    var lbl2 = document.createElement("label");
    lbl2.innerHTML = '<input type="checkbox" name="thickness" value="' +
      thicknesses[k] + '" checked> ' + formatThickness(thicknesses[k]);
    thkEl.appendChild(lbl2);
  }
}

function refreshDisplay() {
  displayUnit = document.querySelector('input[name="units"]:checked').value;

  // Update parts list
  var listEl = document.getElementById("partsList");
  listEl.innerHTML = "";
  for (var i = 0; i < partsData.length; i++) {
    var p = partsData[i];
    var row = document.createElement("div");
    row.className = "part-row";
    row.innerHTML = '<span class="part-name">' + escapeHtml(p.name) + '</span>' +
      '<span class="part-detail">' + formatThickness(p.thickness) +
      (p.material !== "(none)" ? ' — ' + escapeHtml(p.material) : '') +
      '</span>';
    listEl.appendChild(row);
  }

  // Update thickness filters (preserve checked state)
  var checkedThicknesses = getChecked("thickness");
  var thkEl = document.getElementById("thicknessFilters");
  thkEl.innerHTML = "";
  for (var k = 0; k < thicknessesData.length; k++) {
    var val = thicknessesData[k];
    var isChecked = checkedThicknesses.indexOf(String(val)) !== -1;
    var lbl = document.createElement("label");
    lbl.innerHTML = '<input type="checkbox" name="thickness" value="' +
      val + '"' + (isChecked ? ' checked' : '') + '> ' + formatThickness(val);
    thkEl.appendChild(lbl);
  }
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
  var format = document.querySelector('input[name="format"]:checked').value;
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
    format: format,
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
