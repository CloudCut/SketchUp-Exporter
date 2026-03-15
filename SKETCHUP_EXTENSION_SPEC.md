# SketchUp CNC Exporter — Extension Specification

## What this document is

This is a complete specification for building a SketchUp Ruby extension that extracts 2D CNC toolpath geometry from 3D solid parts and exports it as SVG and JSON files. It is a port of an existing Fusion 360 add-in ("Fusion Exporter") to the SketchUp platform.

If you've never heard of any of this before, read on — everything is explained from scratch.

---

## Table of Contents

1. [The Problem We're Solving](#1-the-problem-were-solving)
2. [How the Fusion 360 Version Works](#2-how-the-fusion-360-version-works)
3. [SketchUp vs. Fusion 360 — Key Differences](#3-sketchup-vs-fusion-360--key-differences)
4. [SketchUp Ruby API Primer](#4-sketchup-ruby-api-primer)
5. [Extension Architecture](#5-extension-architecture)
6. [The Core Algorithm](#6-the-core-algorithm)
7. [Edge Geometry Conversion (3D to 2D)](#7-edge-geometry-conversion-3d-to-2d)
8. [SVG Output Format](#8-svg-output-format)
9. [JSON Output Format](#9-json-output-format)
10. [UI and Dialog Design](#10-ui-and-dialog-design)
11. [File and Folder Structure](#11-file-and-folder-structure)
12. [Unit Handling](#12-unit-handling)
13. [SketchUp Extension Best Practices](#13-sketchup-extension-best-practices)
14. [Development and Testing](#14-development-and-testing)
15. [Appendix: SketchUp API Quick Reference](#appendix-sketchup-api-quick-reference)

---

## 1. The Problem We're Solving

### Background

CNC routers cut flat stock material (plywood, acrylic, aluminum plate, etc.) by following 2D toolpaths. A designer models 3D parts in CAD software, but the CNC machine needs a 2D representation of those parts — specifically:

- **The outer profile** — the boundary shape to cut the part out of the stock
- **Through-holes** — holes that go all the way through the material
- **Drill holes** — circular through-holes (optimized with a drill cycle)
- **Pockets** — areas milled to a partial depth (like a recess or shelf)

Each of these operations has a **cut depth** — how deep the tool needs to go. The outer profile and through-holes cut at full material thickness. Pockets cut at some intermediate depth.

### What the exporter does

The exporter takes 3D solid parts modeled in CAD and automatically:

1. Detects which faces form the top and bottom of the flat part
2. Identifies the material thickness
3. Classifies every feature as a profile, through-hole, drill, or pocket
4. Measures the cut depth for each feature
5. Projects everything down to 2D
6. Outputs SVG and/or JSON files with all the geometry and metadata a CNC toolpath generator needs

### Why SketchUp?

SketchUp is a popular 3D modeler. Many makers design their CNC projects in SketchUp. This extension would let them go directly from their SketchUp model to CNC-ready SVG/JSON without an intermediate export/import step.

---

## 2. How the Fusion 360 Version Works

This section describes the existing Fusion 360 add-in's algorithm in detail. The SketchUp version will replicate this logic using SketchUp's API.

### 2.1 Input

The user selects one or more **solid bodies** in Fusion 360. Each body represents a flat part (a panel, bracket, shelf, etc.) made from sheet stock.

### 2.2 Face Classification Algorithm

This is the core of the exporter. For each body:

**Step 1 — Collect planar faces.** Iterate every face on the body. Keep only faces whose underlying geometry is a flat plane. Record each face's normal vector, origin point, and area.

**Step 2 — Group faces by normal direction.** Faces whose normals are parallel (pointing the same way or exactly opposite) belong to the same group. The test is: `|dot(normal_A, normal_B)| > 0.9999`. This groups all the top/bottom/pocket-bottom faces together (they all face "up" or "down" relative to the sheet).

**Step 3 — Identify the sheet plane.** The normal group with the **largest total face area** is the sheet plane. Its normal direction is the "sheet normal" — the direction perpendicular to the flat stock. For a typical horizontal part, this is the Z axis, but the algorithm works for any orientation.

**Step 4 — Compute height levels.** For each face in the sheet-plane group, project its origin onto the sheet normal to get a scalar "height" value. Group faces by height (within a tolerance of 0.001mm). Sort groups by height.

**Step 5 — Identify top, bottom, and pockets.**
- The **highest** height level = one surface of the sheet
- The **lowest** height level = the other surface
- **Material thickness** = highest − lowest
- Everything in between = **pocket bottoms** at various depths

**Step 6 — Determine machining direction.** If there are pockets, examine which direction their bottom faces point. The outward normal of a pocket bottom face points into the cavity (toward where the cutter enters). This tells us which side of the sheet the pockets open from — that's the "machining top."

**Step 7 — Choose the profile face.** Always use the **bottom face** (opposite from the machining top) for extracting the outer profile and through-holes. Why? The bottom face's outer boundary is the true part outline. The top face (machining side) can be split into multiple faces where pockets intersect the edges.

### 2.3 Contour Extraction

From the classified faces, extract contours (closed loops of edges):

| Source | What to extract | Operation type | Cut depth |
|--------|----------------|---------------|-----------|
| Profile face's outer loop | Part boundary | `profile` | Full thickness |
| Profile face's inner loops | Through-features | `drill` if circular, else `profile` | Full thickness |
| All bottom-side faces' inner loops | Through-features | `drill` if circular, else `profile` | Full thickness |
| Intermediate-level faces' all loops | Pocket boundaries and islands | `pocket` | Distance from machining top to that level |

**Circular detection:** A through-hole is classified as a `drill` operation if its loop consists of a single full circle or two semicircular arcs with the same center and radius.

### 2.4 2D Projection

All 3D geometry is projected onto a 2D coordinate system:

1. Build an orthonormal frame (U, V) from the profile face's plane
2. For horizontal faces: U = +X, V = −Y (the Y flip gives SVG-compatible Y-down coordinates)
3. For non-horizontal faces: compute U and V from cross products with a reference direction
4. Project every 3D point: `u = dot(point − origin, U_axis)`, `v = dot(point − origin, V_axis)`

Edge types are converted:
- **Straight lines** → `LineSeg(start, end)` in 2D
- **Circular arcs** → `ArcSeg` with center, radius, clockwise flag, and large-arc flag (for SVG arc commands)
- **Full circles** → `CircleSeg(center, radius)`
- **Complex curves (NURBS, splines)** → tessellated into a chain of `LineSeg`s

### 2.5 Layout

When exporting multiple parts, they are arranged side-by-side in a horizontal strip with 1cm margins and 1cm spacing between parts.

### 2.6 Grouping by Thickness

Parts are grouped by material thickness. Each thickness group produces a separate output file (e.g., `project_6.35mm.svg`, `project_3.175mm.svg`). This lets the user set up their CNC for one stock thickness at a time.

### 2.7 Appearance (Material) Filtering

The user can filter which parts to export by their visual appearance/material. A checkbox dropdown lists all unique appearances; unchecked appearances are excluded.

---

## 3. SketchUp vs. Fusion 360 — Key Differences

| Concept | Fusion 360 | SketchUp |
|---------|-----------|----------|
| **Geometry model** | B-Rep (boundary representation) with typed surfaces (Plane, Cylinder, Cone, NURBS, etc.) | Face/edge mesh — all faces are planar triangles or polygons |
| **Solid detection** | Bodies are inherently solid or surface | `group.manifold?` or `component.manifold?` returns true if the group is a closed solid |
| **Face normals** | `face.geometry` gives typed surface; `Plane` has `.normal` | `face.normal` returns a `Geom::Vector3d` — always works since all faces are planar |
| **Edge curves** | `edge.geometry` returns `Line3D`, `Arc3D`, `Circle3D`, `NurbsCurve3D` | `edge.curve` returns `nil` (straight edge) or `Sketchup::Curve` / `Sketchup::ArcCurve` |
| **Loops** | `face.loops` → `BRepLoop` with `isOuter` flag, contains `coEdges` | `face.loops` → `Sketchup::Loop` with `outer?` method, contains ordered edges |
| **Edge direction in loop** | `coEdge.isOpposedToEdge` | `edge.reversed_in?(face)` |
| **Internal units** | Centimeters | Inches |
| **Part naming** | `body.name` or `parentComponent.name` | `group.name`, `component.definition.name`, `component.name` (instance name) |
| **Unique identifier** | `body.entityToken` | `group.guid` or `component.guid` (persistent across sessions) |
| **Material/appearance** | `body.appearance.name` | `group.material.display_name` or `face.material.display_name` |
| **Volume** | Must compute from geometry | `group.volume` / `component.volume` — returns positive for manifold, negative for non-manifold |
| **Plugin language** | Python | Ruby |
| **Plugin packaging** | Folder in `AddIns/` directory | `.rbz` file (renamed `.zip`) installed via Extension Manager |

### Critical difference: All faces are planar in SketchUp

In Fusion, you must check `isinstance(face.geometry, Plane)` because faces can be curved surfaces (cylinders, spheres, etc.). In SketchUp, **every face is already planar** — it's a polygon defined by straight edges. Curved surfaces in SketchUp are approximated by many small flat faces.

This simplifies Step 1 of the algorithm (collect planar faces) — in SketchUp, every face qualifies. However, it means that what looks like a "cylinder" (the side of a drilled hole) is actually a ring of narrow rectangular faces. These side faces will have normals pointing radially outward, not along the sheet normal, so they'll naturally be excluded from the sheet-plane normal group in Step 3 — which is exactly what we want.

### Critical difference: Arcs in SketchUp

In Fusion, an edge's geometry can be `Arc3D` with an explicit center, radius, start angle, and end angle. In SketchUp, arcs are represented as a series of short straight edges that share a common `Sketchup::ArcCurve` object. The `ArcCurve` provides:

```ruby
arc_curve = edge.curve
if arc_curve.is_a?(Sketchup::ArcCurve)
  arc_curve.center    # => Geom::Point3d
  arc_curve.radius    # => Length (in inches)
  arc_curve.start_angle  # => Float (radians)
  arc_curve.end_angle    # => Float (radians)
  arc_curve.normal    # => Geom::Vector3d (axis of the arc)
end
```

**Strategy:** When iterating edges in a loop, check if consecutive edges belong to the same `ArcCurve`. If so, treat the entire arc as a single `ArcSeg` using the curve's center, radius, and angles rather than emitting individual line segments. This preserves arc fidelity in the SVG output. Edges that are part of a plain `Sketchup::Curve` (not `ArcCurve`) should be emitted as line segments.

### Critical difference: Circles in SketchUp

A full circle in SketchUp is also an `ArcCurve` where `end_angle - start_angle ≈ 2π`. Detect this and emit a `CircleSeg` instead.

---

## 4. SketchUp Ruby API Primer

### 4.1 The Model Tree

```
Sketchup.active_model
  └── .entities (Sketchup::Entities — root-level entities)
        ├── Sketchup::Group
        │     ├── .name          → String (user-assigned, may be empty)
        │     ├── .manifold?     → true if watertight solid
        │     ├── .volume        → Float (cubic inches, positive if manifold)
        │     ├── .material      → Sketchup::Material or nil
        │     ├── .bounds        → Geom::BoundingBox (world space)
        │     ├── .definition    → Sketchup::ComponentDefinition
        │     │     ├── .name    → String (auto-generated like "Group#1")
        │     │     ├── .bounds  → Geom::BoundingBox (local space)
        │     │     └── .entities → Sketchup::Entities (contents of the group)
        │     │           ├── Sketchup::Face
        │     │           ├── Sketchup::Edge
        │     │           └── (nested Groups/ComponentInstances...)
        │     └── .transformation → Geom::Transformation (position/rotation/scale in parent)
        │
        └── Sketchup::ComponentInstance
              ├── .name          → String (instance name, may be empty)
              ├── .definition    → Sketchup::ComponentDefinition
              │     ├── .name    → String (component type name, e.g., "Shelf")
              │     └── .entities → Sketchup::Entities (shared by all instances)
              ├── .manifold?     → true if watertight solid
              ├── .volume        → Float (cubic inches)
              ├── .material      → Sketchup::Material or nil
              ├── .bounds        → Geom::BoundingBox (world space)
              └── .transformation → Geom::Transformation
```

### 4.2 Faces, Loops, and Edges

```ruby
face = some_face  # Sketchup::Face

face.normal        # => Geom::Vector3d — perpendicular to face, front-side direction
face.area          # => Float — square inches
face.plane         # => [a, b, c, d] — plane equation coefficients
face.vertices      # => Array<Sketchup::Vertex>
face.loops         # => Array<Sketchup::Loop> — all loops
face.outer_loop    # => Sketchup::Loop — just the outer boundary
face.material      # => Sketchup::Material or nil (front-side)

loop = face.outer_loop
loop.outer?        # => true for outer boundary, false for holes
loop.edges         # => Array<Sketchup::Edge> — ordered sequence
loop.vertices      # => Array<Sketchup::Vertex> — ordered sequence

edge = some_edge  # Sketchup::Edge
edge.start.position  # => Geom::Point3d
edge.end.position    # => Geom::Point3d
edge.length          # => Length (inches)
edge.curve           # => nil, Sketchup::Curve, or Sketchup::ArcCurve
edge.reversed_in?(face)  # => true if edge direction is reversed in this face's loop
edge.faces           # => Array<Sketchup::Face> — adjacent faces
```

### 4.3 Materials

```ruby
material = group.material  # Sketchup::Material or nil

material.display_name   # => String — human-readable name for UI
material.name           # => String — internal unique name
material.color          # => Sketchup::Color
material.alpha          # => Float (0.0 = transparent, 1.0 = opaque)
material.texture        # => Sketchup::Texture or nil

# All materials in the model:
Sketchup.active_model.materials  # => Sketchup::Materials collection
```

### 4.4 Bounding Box

```ruby
bb = group.bounds           # World-space AABB
bb = group.definition.bounds  # Local-space AABB (preferred for dimensions)

bb.width    # => Length — X extent
bb.height   # => Length — Y extent
bb.depth    # => Length — Z extent (SketchUp is Z-up, so this is vertical)
bb.min      # => Geom::Point3d
bb.max      # => Geom::Point3d
bb.center   # => Geom::Point3d
```

**Warning:** SketchUp naming is confusing. `width` = X, `height` = Y, `depth` = Z. Since SketchUp is Z-up, `depth` is actually the vertical extent.

### 4.5 Transformations

Groups and components have a `transformation` that positions them in their parent's coordinate space. When extracting face geometry, you need the face coordinates in the group/component's **local** coordinate system (which is what you get when iterating `definition.entities`). The transformation is only needed if you want world-space coordinates.

For our purposes, we work entirely in local coordinates — the faces inside the group are already in a consistent local frame. The transformation doesn't matter for the 2D projection because we're looking at the part in isolation.

### 4.6 Extension Registration

The root `.rb` file **must only register the extension** — no other code, no `require` calls, no application logic. If the user disables the extension, nothing else should load.

**Critical rules:**
- Use `Sketchup.require` (not Ruby's `require` or `require_relative`) for all file loading
- **Omit file extensions** in the loader path — this ensures compatibility with `.rb`, `.rbe` (encrypted), and `.rbs` (scrambled) formats when distributed via Extension Warehouse
- Use `__dir__` to build paths, and call `.force_encoding('UTF-8')` on it to prevent path errors on Windows with non-English usernames

```ruby
# ed_cnc_exporter.rb (loader file — THIS IS THE ONLY FILE AT THE ROOT)
# This file must ONLY register the extension. All other code lives in
# the ed_cnc_exporter/ support folder and is loaded on demand.

module EricDesign
  module CNCExporter
    root = File.dirname(__FILE__).force_encoding('UTF-8')
    loader = File.join(root, "ed_cnc_exporter", "main")  # NO .rb extension!

    EXTENSION = SketchupExtension.new("CNC Exporter", loader)
    EXTENSION.creator     = "Your Name"
    EXTENSION.description = "Export selected solid groups and components " \
                            "as CNC-ready SVG and JSON files with automatic " \
                            "profile, pocket, drill, and through-hole detection."
    EXTENSION.version     = "1.0.0"
    EXTENSION.copyright   = "2026"
    Sketchup.register_extension(EXTENSION, true)
  end
end
```

---

## 5. Extension Architecture

### Module Layout

All SketchUp extensions share a single Ruby interpreter. Without proper namespacing, extensions will collide. Every constant, method, and class must live inside a unique module namespace.

```ruby
module EricDesign
  module CNCExporter
    # ALL code lives inside this namespace — no exceptions.
    # Never define global methods, global constants, or global variables.
    # Never include mix-in modules at the global scope.
    # Never monkey-patch SketchUp API classes or Ruby core classes.
  end
end
```

### Components (Ruby files)

| File | Responsibility |
|------|---------------|
| `main.rb` | Entry point — loaded by SketchUp when extension is enabled. Sets up menus, toolbar, and the export command. Loads all other files via `Sketchup.require`. |
| `geometry_extractor.rb` | Face classification algorithm, contour extraction, 2D projection |
| `svg_builder.rb` | Builds SVG document strings from intermediate geometry |
| `json_builder.rb` | Builds JSON document strings from intermediate geometry |
| `path_converter.rb` | Converts edge geometry to SVG path commands (M, L, A, Z) |
| `utils.rb` | Unit conversion, coordinate formatting helpers (no `puts` in production!) |
| `dialog.rb` | HtmlDialog setup and callbacks |

### Data Flow

```
User selects solid groups/components
  → Filter by manifold? == true
  → Collect material names for filter UI
  → Show export dialog
  → User picks options (units, format, material filter, thickness filter)
  → For each selected solid:
      → geometry_extractor.classify_faces(entities)
      → geometry_extractor.extract_contours(classified_faces)
      → Produces intermediate ExportComponent objects
  → Group components by thickness
  → For each thickness group:
      → svg_builder.build_svg(components, unit) or json_builder.build_json(...)
      → Write to file
```

### Intermediate Data Structures

These are plain Ruby classes/structs mirroring the Fusion version:

```ruby
module EricDesign
  module CNCExporter

    # A 2D straight line segment
    LineSeg = Struct.new(:start_pt, :end_pt)
    # start_pt, end_pt are [x, y] arrays in inches (SketchUp internal units)

    # A 2D circular arc segment
    ArcSeg = Struct.new(:start_pt, :end_pt, :center, :radius, :clockwise, :large_arc)
    # center is [x, y], radius is Float (inches)

    # A 2D full circle
    CircleSeg = Struct.new(:center, :radius)

    # A closed contour (edge loop)
    ExportContour = Struct.new(:segments, :is_closed, :is_outer)
    # segments is Array of LineSeg/ArcSeg/CircleSeg

    # A group of contours with the same operation type and cut depth
    ExportOperation = Struct.new(:op_type, :cut_depth, :contours)
    # op_type is :profile, :pocket, :drill, or :engrave
    # cut_depth is Float in inches (internal units)

    # A named part containing operations
    ExportComponent = Struct.new(:name, :guid, :operations, :bbox)
    # bbox is [min_x, min_y, max_x, max_y] in inches, or nil

  end
end
```

---

## 6. The Core Algorithm

This section describes the face classification algorithm adapted for SketchUp. The logic is identical to the Fusion version; only the API calls differ.

### 6.1 Input: A Solid Group or Component

The algorithm operates on the `entities` collection inside a single group or component that has `manifold? == true`.

### 6.2 Step-by-Step

```ruby
def classify_faces(entities)
  # ------------------------------------------------------------------
  # Step 1: Collect ALL faces and their normals
  # ------------------------------------------------------------------
  # In SketchUp, every face is planar, so we collect them all.
  # (Side faces of holes/pockets will have radial normals and will
  # naturally fall into different normal groups — they'll be ignored.)

  planar_faces = []
  entities.grep(Sketchup::Face).each do |face|
    normal = face.normal
    # Use the centroid of the face as its "origin" point
    origin = face_centroid(face)
    planar_faces << {
      face:   face,
      normal: [normal.x, normal.y, normal.z],
      origin: [origin.x, origin.y, origin.z],
      area:   face.area   # square inches
    }
  end

  return nil if planar_faces.empty?

  # ------------------------------------------------------------------
  # Step 2: Group faces by normal direction
  # ------------------------------------------------------------------
  # Two faces belong to the same group if their normals are parallel
  # (same or opposite direction). Test: |dot(n1, n2)| > 0.9999

  normal_groups = group_faces_by_normal(planar_faces)

  # ------------------------------------------------------------------
  # Step 3: The sheet plane = the group with the largest total area
  # ------------------------------------------------------------------

  best_group = normal_groups.max_by { |g| g[:total_area] }
  sheet_normal = best_group[:normal]
  sheet_faces = best_group[:faces]

  # ------------------------------------------------------------------
  # Step 4: Project each face's origin along the sheet normal
  # ------------------------------------------------------------------

  sheet_faces.each do |f|
    ox, oy, oz = f[:origin]
    f[:height] = ox * sheet_normal[0] + oy * sheet_normal[1] + oz * sheet_normal[2]
  end

  # ------------------------------------------------------------------
  # Step 5: Group by height level (tolerance: ~0.001")
  # ------------------------------------------------------------------

  height_groups = group_by_level(sheet_faces, :height, tolerance: 0.0001) # inches

  highest = height_groups.map { |h, _| h }.max
  lowest  = height_groups.map { |h, _| h }.min
  thickness = highest - lowest  # in inches

  # If all faces at same level, it's a flat shape with no thickness
  return flat_result(sheet_faces, sheet_normal) if thickness < 0.0001

  # Separate into high, low, and intermediate (pocket) faces
  high_faces   = []
  low_faces    = []
  pocket_faces = []

  height_groups.each do |level, faces|
    if (level - highest).abs < 0.0001
      high_faces.concat(faces)
    elsif (level - lowest).abs < 0.0001
      low_faces.concat(faces)
    else
      pocket_faces.concat(faces.map { |f| [level, f] })
    end
  end

  # ------------------------------------------------------------------
  # Step 6: Determine which side pockets open from
  # ------------------------------------------------------------------

  pockets_open_toward_high = true  # default
  unless pocket_faces.empty?
    dot_sum = 0.0
    pocket_faces.each do |_level, pf|
      face_obj = pf[:face]
      fn = pf[:normal]
      # SketchUp face.normal always points to the "front" side.
      # For our purposes, this IS the outward normal — no need to
      # check isParamReversed (that's a Fusion concept).
      dot_sum += fn[0] * sheet_normal[0] +
                 fn[1] * sheet_normal[1] +
                 fn[2] * sheet_normal[2]
    end
    pockets_open_toward_high = dot_sum > 0
  end

  # ------------------------------------------------------------------
  # Step 7: Profile face = bottom side (opposite from pocket openings)
  # ------------------------------------------------------------------

  if pockets_open_toward_high
    machining_top_level = highest
    bottom_faces = low_faces
  else
    machining_top_level = lowest
    bottom_faces = high_faces
  end

  # The profile face is the largest bottom-side face
  profile_face = bottom_faces.max_by { |f| f[:area] }[:face]

  # Through-hole detection uses ALL bottom-side faces
  through_hole_faces = bottom_faces

  # Pocket groups: (depth_from_machining_top, [face_dicts])
  pocket_groups = {}
  pocket_faces.each do |level, f|
    depth = (machining_top_level - level).abs
    key = pocket_groups.keys.find { |k| (k - depth).abs < 0.0001 } || depth
    (pocket_groups[key] ||= []) << f
  end
  pocket_groups = pocket_groups.sort_by { |depth, _| depth }

  {
    profile_face:       profile_face,
    through_hole_faces: through_hole_faces,
    thickness:          thickness,         # inches
    pocket_faces:       pocket_groups,     # [(depth, [face_dicts]), ...]
    sheet_normal:       sheet_normal
  }
end
```

### 6.3 Face Centroid Helper

SketchUp faces don't have a simple `.origin` like Fusion planes. Compute the centroid from vertices:

```ruby
def face_centroid(face)
  pts = face.vertices.map(&:position)
  cx = pts.sum { |p| p.x } / pts.length.to_f
  cy = pts.sum { |p| p.y } / pts.length.to_f
  cz = pts.sum { |p| p.z } / pts.length.to_f
  Geom::Point3d.new(cx, cy, cz)
end
```

### 6.4 isParamReversed — Not Needed in SketchUp

In Fusion, `face.isParamReversed` indicates that the face's parametric normal is flipped relative to the surface normal. SketchUp doesn't have this concept — `face.normal` always returns the front-side normal directly. This simplifies Step 6.

---

## 7. Edge Geometry Conversion (3D to 2D)

### 7.1 Building the Projection Frame

Same logic as Fusion, adapted for SketchUp's `Geom::Vector3d`:

```ruby
def build_face_axes(face)
  normal = face.normal

  if normal.z.abs > 0.9
    # Horizontal face — U = +X, V = -Y (Y-down for SVG)
    u = Geom::Vector3d.new(1, 0, 0)
    v = Geom::Vector3d.new(0, -1, 0)
  else
    # Non-horizontal — compute from cross products
    ref = Geom::Vector3d.new(0, 0, 1)
    u = ref.cross(normal)
    u.normalize!
    v = normal.cross(u)
    v.reverse!  # Negate for SVG Y-down
    v.normalize!
  end

  [u, v]
end
```

### 7.2 Point Projection

```ruby
def project_point(point3d, origin, u_axis, v_axis)
  dx = point3d.x - origin.x
  dy = point3d.y - origin.y
  dz = point3d.z - origin.z

  u = dx * u_axis.x + dy * u_axis.y + dz * u_axis.z
  v = dx * v_axis.x + dy * v_axis.y + dz * v_axis.z

  [u, v]  # 2D coordinates in inches
end
```

### 7.3 Extracting Loops

```ruby
def extract_loop(loop, origin, u_axis, v_axis)
  edges = loop.edges
  return nil if edges.empty?

  segments = []

  # Group consecutive edges that share the same ArcCurve
  i = 0
  while i < edges.length
    edge = edges[i]
    curve = edge.curve

    if curve.is_a?(Sketchup::ArcCurve)
      # Collect all consecutive edges belonging to this same curve
      arc_edges = [edge]
      j = i + 1
      while j < edges.length && edges[j].curve == curve
        arc_edges << edges[j]
        j += 1
      end

      # Is it a full circle? (2π arc)
      if (curve.end_angle - curve.start_angle - 2 * Math::PI).abs < 0.01
        center_2d = project_point(curve.center, origin, u_axis, v_axis)
        segments << CircleSeg.new(center_2d, curve.radius)
      else
        # Partial arc — emit as ArcSeg
        # Determine start and end points from the first/last edge
        # in loop traversal order
        first_edge = arc_edges.first
        last_edge = arc_edges.last

        reversed = first_edge.reversed_in?(loop.face)

        if reversed
          start_pt = first_edge.end.position
          end_pt = last_edge.start.position
        else
          start_pt = first_edge.start.position
          end_pt = last_edge.end.position
        end

        start_2d = project_point(start_pt, origin, u_axis, v_axis)
        end_2d = project_point(end_pt, origin, u_axis, v_axis)
        center_2d = project_point(curve.center, origin, u_axis, v_axis)
        radius = curve.radius  # already in inches

        # Determine clockwise/large_arc flags (same math as Fusion version)
        clockwise, large_arc = compute_arc_flags(
          start_2d, end_2d, center_2d,
          curve.normal, u_axis, v_axis, reversed
        )

        segments << ArcSeg.new(start_2d, end_2d, center_2d, radius, clockwise, large_arc)
      end

      i = j  # Skip past all edges in this arc
    else
      # Straight edge (or non-arc curve edge — treat as line)
      reversed = edge.reversed_in?(loop.face)
      start_pt = reversed ? edge.end.position : edge.start.position
      end_pt = reversed ? edge.start.position : edge.end.position

      start_2d = project_point(start_pt, origin, u_axis, v_axis)
      end_2d = project_point(end_pt, origin, u_axis, v_axis)

      segments << LineSeg.new(start_2d, end_2d)
      i += 1
    end
  end

  return nil if segments.empty?
  ExportContour.new(segments, true, true)
end
```

### 7.4 Arc Flag Computation

The SVG arc command (`A`) needs two flags: `large-arc-flag` and `sweep-flag`. This is the same math as the Fusion version:

```ruby
def compute_arc_flags(start_2d, end_2d, center_2d, arc_normal_3d, u_axis, v_axis, reversed)
  # Compute the view-plane normal (u × v)
  view_z = u_axis.cross(v_axis)

  # If arc normal aligns with view normal, arc is CCW in 2D
  dot_normal = arc_normal_3d.x * view_z.x +
               arc_normal_3d.y * view_z.y +
               arc_normal_3d.z * view_z.z

  arc_is_ccw = dot_normal > 0
  arc_is_ccw = !arc_is_ccw if reversed

  # In SVG Y-down, math-CCW = visual-CW. sweep_flag=1 means CW in SVG.
  clockwise = arc_is_ccw

  # Compute sweep angle for large-arc determination
  cs = [start_2d[0] - center_2d[0], start_2d[1] - center_2d[1]]
  ce = [end_2d[0] - center_2d[0], end_2d[1] - center_2d[1]]
  angle_start = Math.atan2(cs[1], cs[0])
  angle_end = Math.atan2(ce[1], ce[0])

  sweep = angle_end - angle_start
  if arc_is_ccw
    sweep += 2 * Math::PI if sweep <= 0
  else
    sweep -= 2 * Math::PI if sweep >= 0
  end

  large_arc = sweep.abs > Math::PI

  [clockwise, large_arc]
end
```

---

## 8. SVG Output Format

The SVG output is a self-contained vector graphics file with custom data attributes that a CNC toolpath generator can parse.

### 8.1 Document Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     width="150.0mm" height="80.0mm"
     viewBox="0 0 150.0 80.0">

  <!-- Component: Shelf -->
  <g data-component="Shelf" id="component-1" data-source-guid="abc123">

    <g id="PROFILE: 6.35" data-operation="profile" data-cut-depth="6.35">
      <path d="M10.0,10.0 L100.0,10.0 L100.0,60.0 L10.0,60.0 Z"
            fill="none" stroke="black" stroke-width="0.18"/>
    </g>

    <g id="DRILL: 6.35" data-operation="drill" data-cut-depth="6.35">
      <circle cx="30.0" cy="30.0" r="2.5"
              fill="black" stroke="none" stroke-width="0.18"/>
    </g>

    <g id="POCKET: 3.0" data-operation="pocket" data-cut-depth="3.0">
      <path d="M50.0,20.0 L80.0,20.0 L80.0,50.0 L50.0,50.0 Z"
            fill="gray" stroke="none" stroke-width="0.18"/>
    </g>

  </g>

</svg>
```

### 8.2 Style Conventions

| Operation | Fill | Stroke | Meaning |
|-----------|------|--------|---------|
| `profile` | none | black | Outline — cut through at full depth |
| `drill` | black | none | Filled circle — drill operation |
| `pocket` | gray | none | Filled area — mill to partial depth |
| `engrave` | none | blue | Outline — surface marking (V-bit) |

Stroke width: `0.18` for mm output, `0.007` for inch output (hairline).

### 8.3 Data Attributes

- `data-component` — part name (from group/component name)
- `data-source-guid` — unique identifier for traceability
- `data-operation` — operation type: `profile`, `drill`, `pocket`, `engrave`
- `data-cut-depth` — how deep to cut, in the output unit

### 8.4 SVG Path Commands Used

- `M x,y` — move to (start of contour)
- `L x,y` — line to
- `A rx,ry rotation large-arc-flag,sweep-flag x,y` — elliptical arc (always circular: rx=ry=radius, rotation=0)
- `Z` — close path

Full circles use two semicircular arcs:
```
M(cx-r, cy) A(r,r 0 1,0 cx+r,cy) A(r,r 0 1,0 cx-r,cy) Z
```

---

## 9. JSON Output Format

The JSON output contains the same information as SVG but in a machine-readable structure:

```json
{
  "units": "mm",
  "width": 150.0,
  "height": 80.0,
  "components": [
    {
      "name": "Shelf",
      "sourceGuid": "abc123",
      "operations": [
        {
          "type": "profile",
          "cutDepth": 6.35,
          "paths": ["M10.0,10.0 L100.0,10.0 L100.0,60.0 L10.0,60.0 Z"],
          "circles": []
        },
        {
          "type": "drill",
          "cutDepth": 6.35,
          "paths": [],
          "circles": [{"cx": 30.0, "cy": 30.0, "r": 2.5}]
        },
        {
          "type": "pocket",
          "cutDepth": 3.0,
          "paths": ["M50.0,20.0 L80.0,20.0 L80.0,50.0 L50.0,50.0 Z"],
          "circles": [{"cx": 65.0, "cy": 35.0, "r": 4.0}]
        }
      ]
    }
  ]
}
```

Each operation has both `paths` (SVG path d-strings) and `circles` (center/radius objects). Full-circle drills and pockets go into `circles`; everything else goes into `paths`.

Numeric precision: 4 decimal places for mm, 6 for inches.

---

## 10. UI and Dialog Design

### 10.1 Menu and Toolbar

Per SketchUp best practices:
- All commands go in the **Extensions** menu (not "Plugins" — it was renamed)
- Group entries in a submenu named after the extension
- All toolbar commands **must also appear in menus** (users can only assign keyboard shortcuts to menu items)
- Reuse the same `UI::Command` object for both menu and toolbar
- **Never include version numbers** in menu entry or toolbar names (breaks shortcuts and toolbar positions on update)
- Use **title case** for command names ("Export SVG/JSON" not "export svg/json")
- Toolbar description should be a full sentence explaining what the command does

```ruby
# Create a single UI::Command — shared by both menu and toolbar
cmd_export = UI::Command.new("Export SVG/JSON") { show_export_dialog }
cmd_export.small_icon = File.join(__dir__, "icons", "icon_16.png")
cmd_export.large_icon = File.join(__dir__, "icons", "icon_24.png")
cmd_export.tooltip = "Export SVG/JSON"
cmd_export.status_bar_text = "Export selected solid groups/components as CNC-ready SVG or JSON files."

# Menu — under Extensions, in a submenu
menu = UI.menu("Extensions")
submenu = menu.add_submenu("CNC Exporter")
submenu.add_item(cmd_export)

# Toolbar — compact, only the export button (no Help/About here)
toolbar = UI::Toolbar.new("CNC Exporter")
toolbar.add_item(cmd_export)
toolbar.restore  # Remembers show/hide state from previous session
```

### 10.2 Pre-flight Check

Before showing the dialog, validate the selection:

```ruby
def show_export_dialog
  model = Sketchup.active_model
  selection = model.selection

  # Find all solid groups/components in the selection
  solids = find_solids_in_selection(selection)

  if solids.empty?
    UI.messagebox(
      "No solid groups or components selected.\n\n" \
      "Select one or more groups/components that SketchUp considers 'solid' " \
      "(shown in Entity Info), then try again."
    )
    return
  end

  # Proceed to show dialog...
end
```

### 10.3 Finding Solids in Selection

Walk the selection recursively. A selected group/component that is manifold is a solid. If a selected group/component is NOT manifold but contains manifold children, include those children.

```ruby
def find_solids_in_selection(selection)
  solids = []

  selection.each do |entity|
    collect_solids(entity, solids)
  end

  solids
end

def collect_solids(entity, solids)
  if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    if entity.manifold?
      solids << entity
    else
      # Not solid itself — check children
      defn = entity.is_a?(Sketchup::Group) ? entity.definition : entity.definition
      defn.entities.each do |child|
        collect_solids(child, solids)
      end
    end
  end
end
```

### 10.4 Part Naming Strategy

```ruby
def part_name(entity)
  if entity.is_a?(Sketchup::ComponentInstance)
    # Prefer instance name, fall back to definition name
    name = entity.name
    name = entity.definition.name if name.nil? || name.empty?
    name
  elsif entity.is_a?(Sketchup::Group)
    name = entity.name
    if name.nil? || name.empty?
      # Auto-generate: "Solid_001", "Solid_002", etc.
      nil  # Caller assigns sequential name
    else
      name
    end
  end
end
```

Unnamed groups get auto-generated names like `"Solid_001"`, `"Solid_002"`, etc.

### 10.5 HTML Dialog

Use `UI::HtmlDialog` for the export options dialog. This gives a full HTML/CSS/JS interface inside SketchUp.

**Dialog contents:**

- **Detected solids list** — shows the name and thickness of each solid found in the selection (read-only, for confirmation)
- **Output format** — radio buttons: SVG / JSON
- **Output units** — radio buttons: Millimeters / Inches (default based on model units)
- **Material filter** — checkboxes for each unique material, with an "All" toggle
- **Thickness filter** — checkboxes for each unique thickness, with an "All" toggle
- **Export button** — triggers the export

**Communication between HTML and Ruby:**

```ruby
# Ruby side
dialog.add_action_callback("doExport") do |_ctx, options_json|
  options = JSON.parse(options_json)
  perform_export(options, solids)
end

# JavaScript side (in the HTML)
document.getElementById("exportBtn").addEventListener("click", function() {
  var options = {
    format: document.querySelector('input[name="format"]:checked').value,
    units: document.querySelector('input[name="units"]:checked').value,
    materials: getCheckedMaterials(),
    thicknesses: getCheckedThicknesses()
  };
  sketchup.doExport(JSON.stringify(options));
});
```

### 10.6 Save Dialog

After the HTML dialog, show a native save dialog:

```ruby
# For SVG
path = UI.savepanel("Save SVG File", "", "export.svg")
# For JSON
path = UI.savepanel("Save JSON File", "", "export.json")
```

Returns `nil` if user cancels, otherwise the full file path.

---

## 11. File and Folder Structure

### 11.1 Extension Layout

Per SketchUp requirements, the RBZ root must contain **exactly two items**: one `.rb` loader file and one support folder with the **same base name**. File names are prefixed with a short identifier (`ed_`) to avoid clashes with other extensions.

```
ed_cnc_exporter.rb                    ← Loader file (extension registration ONLY)
ed_cnc_exporter/                      ← Support folder (same name, no .rb)
  ├── main.rb                         ← Entry point: menus, toolbar, command
  ├── geometry_extractor.rb           ← Face classification, contour extraction
  ├── svg_builder.rb                  ← SVG document assembly
  ├── json_builder.rb                 ← JSON document assembly
  ├── path_converter.rb               ← Segment → SVG path command conversion
  ├── utils.rb                        ← Unit conversion, formatting, helpers
  ├── dialog.rb                       ← HtmlDialog setup and callbacks
  ├── html/
  │   ├── export_dialog.html          ← Export options dialog
  │   ├── style.css                   ← Dialog styling
  │   └── dialog.js                   ← Dialog logic
  └── icons/
      ├── icon_16.png                 ← Small toolbar icon
      └── icon_24.png                 ← Large toolbar icon
```

**Important file loading rules:**
- The loader file (`ed_cnc_exporter.rb`) must **only** register the extension — no `Sketchup.require` calls, no application logic
- `main.rb` is loaded automatically by SketchUp when the extension is enabled
- Inside `main.rb` and other support files, use `Sketchup.require` to load sibling files
- **Always omit file extensions** in `Sketchup.require` paths — this ensures compatibility when Extension Warehouse encrypts your files to `.rbe`/`.rbs`
- **Never modify `$LOAD_PATH`** — use explicit paths relative to `__dir__` instead

```ruby
# Inside main.rb — loading sibling files:
dir = __dir__.force_encoding('UTF-8')
Sketchup.require(File.join(dir, "utils"))                # NOT "utils.rb"
Sketchup.require(File.join(dir, "geometry_extractor"))
Sketchup.require(File.join(dir, "path_converter"))
Sketchup.require(File.join(dir, "svg_builder"))
Sketchup.require(File.join(dir, "json_builder"))
Sketchup.require(File.join(dir, "dialog"))
```

### 11.2 Packaging as .rbz

An `.rbz` is just a renamed `.zip`. The ZIP must contain the loader file and support folder at the root level:

```bash
cd /path/to/extension/parent/
zip -r ed_cnc_exporter.rbz \
  ed_cnc_exporter.rb \
  ed_cnc_exporter/
```

**Do not pre-encrypt** before submitting to Extension Warehouse — it applies encryption automatically.

Users install via: **SketchUp → Window → Extension Manager → Install Extension**

### 11.3 Development Installation

For development, copy (or symlink) the files directly into SketchUp's Plugins folder:

- **macOS:** `~/Library/Application Support/SketchUp 20XX/SketchUp/Plugins/`
- **Windows:** `%APPDATA%\SketchUp\SketchUp 20XX\SketchUp\Plugins\`

Both the `ed_cnc_exporter.rb` file and the `ed_cnc_exporter/` folder go directly inside `Plugins/`.

---

## 12. Unit Handling

### Internal Units

SketchUp uses **inches** internally (Fusion uses centimeters). All `Length` values, coordinates, areas, and volumes are in inches/square inches/cubic inches.

### Conversion Functions

```ruby
module EricDesign
  module CNCExporter
    module Units
      def self.inches_to_mm(val)
        val * 25.4
      end

      def self.inches_to_in(val)
        val  # identity
      end

      def self.to_unit(val, unit)
        unit == "mm" ? inches_to_mm(val) : inches_to_in(val)
      end

      def self.format_coord(val, unit)
        unit == "mm" ? "%.4f" % val : "%.6f" % val
      end

      def self.format_depth(val, unit)
        formatted = format_coord(val, unit)
        # Strip trailing zeros but keep at least one decimal
        formatted.sub(/0+$/, '').sub(/\.$/, '.0')
      end
    end
  end
end
```

### Detecting Model Units

```ruby
model = Sketchup.active_model
options = model.options["UnitsOptions"]
unit_format = options["LengthFormat"]
# 0 = Decimal, 1 = Architectural, 2 = Engineering, 3 = Fractional
# For decimal: options["LengthUnit"] → 0=inches, 1=feet, 2=mm, 3=cm, 4=m

length_unit = options["LengthUnit"]
is_metric = [2, 3, 4].include?(length_unit)
default_output = is_metric ? "mm" : "in"
```

---

## 13. SketchUp Extension Best Practices

This section summarizes the official SketchUp extension development guidelines from [SketchUp's documentation](https://ruby.sketchup.com/file.extension_requirements.html) and the [Extension UX Guidelines](https://sketchup.github.io/sketchup-extension-ux-guidelines/). The Extension Warehouse review team uses the [RuboCop-SketchUp](https://rubocop-sketchup.readthedocs.io/) static analyzer to enforce these rules.

### 13.1 Namespace Isolation (Mandatory)

- **Wrap all code in a unique two-level module** (e.g., `EricDesign::CNCExporter`)
- **Never** define global methods, constants, or variables
- **Never** `include` mix-in modules at the global scope
- **Never** monkey-patch SketchUp API classes (`Sketchup::`, `UI::`, etc.)
- **Never** modify Ruby core/stdlib classes (`String`, `Array`, `Hash`, etc.)

### 13.2 File Loading (Mandatory)

- Use `Sketchup.require` instead of Ruby's `require` or `require_relative`
- **Always omit file extensions** — `Sketchup.require("path/to/file")` not `"path/to/file.rb"`. This is required for compatibility with Extension Warehouse encryption (`.rbe`/`.rbs`)
- Use `__dir__.force_encoding('UTF-8')` to prevent path errors on Windows
- **Never modify `$LOAD_PATH`** — use explicit relative paths

### 13.3 Startup Performance (Mandatory)

- The root `.rb` loader file must **only** register the extension — no code loading, no application logic
- **Never use `Kernel.sleep`** — it freezes the entire SketchUp UI. Use `UI.start_timer` if timing is needed
- **Never install gems at runtime** (`Gem.install`) — copy needed code into your extension folder

### 13.4 Menu and Toolbar Rules

- Place commands under **Extensions** menu (not "Plugins" — renamed)
- Group multiple entries in a **submenu** named after your extension
- **All toolbar commands must also appear in menus** — users can only assign keyboard shortcuts to menu items
- Reuse the same `UI::Command` object for both menu and toolbar
- **Never include version numbers** in menu/toolbar names (breaks shortcuts on update)
- Use **title case** for command names
- Use `toolbar.restore` — no need for `UI.start_timer` workarounds

### 13.5 Console Output (Mandatory for Distribution)

- **Remove all `puts`, `print`, and `p` statements** before publishing — they clutter the shared Ruby Console
- **Never call `exit` or `exit!`** — `exit!` terminates SketchUp immediately
- Handle errors gracefully with user-facing messages (`UI.messagebox`) instead of console output

### 13.6 UI Guidelines

- Use **friendly, non-technical language** (e.g., "Endpoint" not "Vertex")
- Error messages should be helpful ("The selection contains no solid parts — select groups or components that show as 'Solid' in Entity Info")
- Add full-sentence tooltips/descriptions to commands
- Use `UI::HtmlDialog` (not the deprecated `UI::WebDialog` or `UI.inputbox`) for dialogs
- **Keep a Ruby reference** to `HtmlDialog` objects in a module variable — otherwise garbage collection will close the window

### 13.7 Dependency Management

- **Do not depend on other extensions** — duplicate shared logic into your own namespace
- **Do not install gems** — copy needed source code into your extension folder
- No external dependencies at all if possible

### 13.8 Undo Stack

Our extension is read-only (exports data, doesn't modify the model), so undo management doesn't apply. But if you ever add model-modifying features:
- Wrap multi-step changes in `model.start_operation` / `model.commit_operation`
- One user action = one undo step

### 13.9 Extension Warehouse Submission Checklist

Extensions are **rejected** if they:
- Cause other extensions to crash
- Exhibit obvious bugs
- Use undocumented APIs
- Cause SketchUp to crash or perform slowly
- Cause damage to user data

Before submitting:
- [ ] Run [RuboCop-SketchUp](https://rubocop-sketchup.readthedocs.io/) and fix all warnings
- [ ] Test on both macOS and Windows
- [ ] Test with SketchUp 2017+ (minimum version for `HtmlDialog`)
- [ ] Remove all `puts`/`print`/`p` debug output
- [ ] Verify the extension loads cleanly when disabled then re-enabled
- [ ] Verify no `$LOAD_PATH` modification
- [ ] Verify no global namespace pollution

---

## 14. Development and Testing

### 14.1 Ruby Console

SketchUp has a built-in Ruby Console (**Window → Ruby Console**). Use it for interactive development:

```ruby
# Reload your extension after code changes
load "sketchup_cnc_exporter/main.rb"

# Test solid detection
model = Sketchup.active_model
model.selection.each do |e|
  puts "#{e.class}: manifold=#{e.manifold?}" if e.respond_to?(:manifold?)
end

# Test face classification on the first selected solid
solid = model.selection.first
entities = solid.definition.entities
faces = entities.grep(Sketchup::Face)
puts "Found #{faces.length} faces"
faces.each { |f| puts "  normal: #{f.normal}, area: #{f.area}" }
```

### 14.2 Test Models

Create simple test models in SketchUp to validate each feature:

1. **Simple box** — a rectangular solid (6 faces). Should produce a rectangular profile at box height, no pockets or holes.
2. **Box with a hole** — a box with a circle pushed through. Should produce a profile + one drill hole.
3. **Box with a pocket** — a box with a rectangle pushed partway in. Should produce a profile + one pocket.
4. **Box with pocket + hole** — combines both features.
5. **Multiple thicknesses** — two boxes of different heights. Should produce two separate output files.
6. **Non-axis-aligned** — a rotated box. Tests the arbitrary-orientation face classification.
7. **Complex part** — multiple pockets at different depths, holes of various sizes, non-rectangular outline.

### 14.3 Debugging Tips

- During development, use `puts` to print to the Ruby Console — but **remove all `puts`/`print`/`p` before distributing** (they clutter the shared console for all extensions)
- Keep a reference to your `HtmlDialog` in a module-level variable — otherwise Ruby's garbage collector will close the window
- Test with both groups and components — they have slightly different APIs but both support `manifold?`
- Run [RuboCop-SketchUp](https://rubocop-sketchup.readthedocs.io/) regularly during development to catch guideline violations early

### 14.4 Minimum SketchUp Version

- `manifold?` — available since SketchUp 8 (2010)
- `UI::HtmlDialog` — available since SketchUp 2017
- `group.definition` — available since SketchUp 2015
- `component.guid` — available since SketchUp 2014

**Recommended minimum: SketchUp 2017** (for `HtmlDialog` support).

---

## Appendix: SketchUp API Quick Reference

### Key Classes and Methods Used

```ruby
# Model access
model = Sketchup.active_model
model.selection              # current selection
model.entities               # root-level entities
model.materials              # all materials
model.options["UnitsOptions"] # unit settings

# Group / ComponentInstance (shared interface)
entity.manifold?             # => Boolean — is it a solid?
entity.volume                # => Float — cubic inches (positive if manifold)
entity.definition            # => ComponentDefinition
entity.definition.entities   # => Entities inside the group/component
entity.definition.bounds     # => BoundingBox (local space)
entity.name                  # => String
entity.guid                  # => String (persistent ID)
entity.material              # => Material or nil
entity.transformation        # => Transformation (position in parent)

# Face
face.normal                  # => Vector3d
face.area                    # => Float (square inches)
face.loops                   # => Array<Loop>
face.outer_loop              # => Loop
face.vertices                # => Array<Vertex>
face.material                # => Material or nil

# Loop
loop.outer?                  # => Boolean
loop.edges                   # => Array<Edge> (ordered)
loop.vertices                # => Array<Vertex> (ordered)

# Edge
edge.start.position          # => Point3d
edge.end.position            # => Point3d
edge.curve                   # => nil, Curve, or ArcCurve
edge.reversed_in?(face)      # => Boolean or nil
edge.length                  # => Length

# ArcCurve (subclass of Curve)
arc.center                   # => Point3d
arc.radius                   # => Length
arc.start_angle              # => Float (radians)
arc.end_angle                # => Float (radians)
arc.normal                   # => Vector3d

# BoundingBox
bb.width                     # => Length (X)
bb.height                    # => Length (Y)
bb.depth                     # => Length (Z)
bb.min                       # => Point3d
bb.max                       # => Point3d

# Material
mat.display_name             # => String
mat.color                    # => Color
mat.alpha                    # => Float

# UI
UI.savepanel(title, dir, filename)  # => String or nil
UI.messagebox(message)              # => Integer (button pressed)
UI::HtmlDialog.new(properties)      # => HtmlDialog
dialog.set_file(path)
dialog.add_action_callback(name) { |ctx, args| ... }
dialog.show
dialog.execute_script(js_string)
```

### Geometry Math

```ruby
# Vector operations
v1.dot(v2)          # dot product
v1.cross(v2)        # cross product → new Vector3d
v1.normalize!       # normalize in place
v1.reverse!         # negate in place
v1.length           # magnitude
v1.x, v1.y, v1.z   # components

# Point operations
p1.x, p1.y, p1.z   # coordinates (in inches)
p1.distance(p2)     # distance between points
p1.vector_to(p2)    # => Vector3d from p1 to p2

# Transformation
t = Geom::Transformation.new(point)      # translation
t = Geom::Transformation.rotation(origin, axis, angle)
point.transform(t)   # apply transformation → new Point3d
```
