module CloudCut
  module Exporter
    module GeometryExtractor

      UNIFORM_SCALE_TOL = 0.0001

      # Find all solid groups/components in the selection, recursively.
      # Returns an array of { entity:, transform:, ancestor_pids: } hashes,
      # where transform maps points from the entity's definition space into
      # world space. Each tuple represents one world-space placement — the
      # same entity reached through multiple parent instances emits one tuple
      # per path, with distinct transforms.
      def self.find_solids_in_selection(selection)
        results = []
        selection.each do |entity|
          collect_solids(entity, results, Geom::Transformation.new, [])
        end
        results
      end

      # Find the non-solid leaf parts in the selection, recursing through
      # nested groups/components the same way find_solids_in_selection does.
      # A "non-solid part" is a group/component that SketchUp won't treat as
      # solid and that holds no nested containers of its own — i.e. a leaf the
      # user likely meant to export but can't. Assemblies (non-solid wrappers
      # around nested parts) are descended into, not flagged, so their solid
      # children still export and only their non-solid children get reported.
      # Returns an array of { entity:, transform: } hashes, where transform
      # maps the entity's definition space into the top-level selection space
      # (matching find_solids_in_selection's convention).
      def self.find_non_solids_in_selection(selection)
        results = []
        selection.each do |entity|
          collect_non_solids(entity, results, Geom::Transformation.new)
        end
        results
      end

      # Return the per-axis scale magnitudes by reading the raw matrix columns.
      # Note: Geom::Transformation#xaxis/yaxis/zaxis return UNIT vectors and so
      # can't be used for scale — their length is always 1 regardless of scale.
      def self.axis_scales(transformation)
        a = transformation.to_a
        sx = Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
        sy = Math.sqrt(a[4] * a[4] + a[5] * a[5] + a[6] * a[6])
        sz = Math.sqrt(a[8] * a[8] + a[9] * a[9] + a[10] * a[10])
        [sx, sy, sz]
      end

      # True iff all three axis scales are equal magnitude. Mirrored transforms
      # still pass because column lengths are magnitudes; handedness is
      # detected separately via mirrored?.
      def self.uniform_scale?(transformation)
        sx, sy, sz = axis_scales(transformation)
        (sx - sy).abs < UNIFORM_SCALE_TOL && (sx - sz).abs < UNIFORM_SCALE_TOL
      end

      def self.mirrored?(transformation)
        a = transformation.to_a
        # Determinant of upper-left 3x3 (column-major): negative means odd flips.
        det = a[0] * (a[5] * a[10] - a[6] * a[9]) -
              a[4] * (a[1] * a[10] - a[2] * a[9]) +
              a[8] * (a[1] * a[6]  - a[2] * a[5])
        det < 0
      end

      # Transform a direction vector (rotation + scale, no translation).
      def self.transform_direction(vec, transform)
        p0 = transform * Geom::Point3d.new(0, 0, 0)
        p1 = transform * Geom::Point3d.new(vec.x, vec.y, vec.z)
        v = Geom::Vector3d.new(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z)
        v.length > 1e-9 ? v.normalize : v
      end

      # Classify faces of a solid into profile, through-hole, and pocket groups.
      # entities is the definition entity list; world_transform maps those
      # entities into world space. Classification runs in world space so that
      # scale and mirror participate in thickness, face areas, and pocket
      # orientation decisions.
      def self.classify_faces(entities, world_transform = Geom::Transformation.new)
        planar_faces = []
        entities.grep(Sketchup::Face).each do |face|
          world_normal = transform_direction(face.normal, world_transform)
          world_origin = world_transform * Exporter.face_centroid(face)
          planar_faces << {
            face:   face,
            normal: [world_normal.x, world_normal.y, world_normal.z],
            origin: [world_origin.x, world_origin.y, world_origin.z],
            # Areas scale uniformly by s^2; only relative ordering matters here.
            area:   face.area
          }
        end
        return nil if planar_faces.empty?

        normal_groups = group_faces_by_normal(planar_faces)

        best_group = normal_groups.max_by { |g| g[:total_area] }
        sheet_normal = best_group[:normal]
        sheet_faces = best_group[:faces]

        sheet_faces.each do |f|
          ox, oy, oz = f[:origin]
          f[:height] = ox * sheet_normal[0] + oy * sheet_normal[1] + oz * sheet_normal[2]
        end

        height_groups = group_by_level(sheet_faces, :height, 0.0001)

        highest = height_groups.map { |h, _| h }.max
        lowest  = height_groups.map { |h, _| h }.min
        thickness = highest - lowest

        if thickness < 0.0001
          return flat_result(sheet_faces, sheet_normal)
        end

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

        pockets_open_toward_high = true
        unless pocket_faces.empty?
          dot_sum = 0.0
          pocket_faces.each do |_level, pf|
            fn = pf[:normal]
            dot_sum += fn[0] * sheet_normal[0] +
                       fn[1] * sheet_normal[1] +
                       fn[2] * sheet_normal[2]
          end
          pockets_open_toward_high = dot_sum > 0
        end

        if pockets_open_toward_high
          machining_top_level = highest
          bottom_faces = low_faces
        else
          machining_top_level = lowest
          bottom_faces = high_faces
        end

        return nil if bottom_faces.empty?

        profile_face_info = bottom_faces.max_by { |f| f[:area] }

        pocket_groups = {}
        pocket_faces.each do |level, f|
          depth = (machining_top_level - level).abs
          key = pocket_groups.keys.find { |k| (k - depth).abs < 0.0001 } || depth
          (pocket_groups[key] ||= []) << f
        end
        pocket_groups = pocket_groups.sort_by { |depth, _| depth }

        {
          profile_face:       profile_face_info[:face],
          profile_normal:     profile_face_info[:normal],
          profile_origin:     profile_face_info[:origin],
          through_hole_faces: bottom_faces,
          thickness:          thickness,
          pocket_faces:       pocket_groups,
          sheet_normal:       sheet_normal
        }
      end

      # Extract contours from classified faces, producing ExportOperation objects.
      # world_transform must match the one passed to classify_faces — all vertex
      # coordinates are transformed into world space before 2D projection.
      def self.extract_contours(classified, world_transform = Geom::Transformation.new)
        return [] unless classified

        profile_face = classified[:profile_face]
        world_normal = Geom::Vector3d.new(*classified[:profile_normal])
        origin = Geom::Point3d.new(*classified[:profile_origin])
        thickness = classified[:thickness]
        through_hole_faces = classified[:through_hole_faces]
        pocket_groups = classified[:pocket_faces]

        u_axis, v_axis = build_axes_from_normal(world_normal)

        operations = []

        # Profile: outer loop of the profile face
        outer_contour = extract_loop(profile_face.outer_loop, origin, u_axis, v_axis, world_transform)
        if outer_contour
          outer_contour.is_outer = true
          operations << ExportOperation.new(:profile, thickness, [outer_contour])
        end

        # Through-holes: inner loops of all bottom-side faces
        drill_contours = []
        profile_contours = []

        through_hole_faces.each do |face_dict|
          face_obj = face_dict[:face]
          face_obj.loops.each do |loop|
            next if loop.outer?
            contour = extract_loop(loop, origin, u_axis, v_axis, world_transform)
            next unless contour
            contour.is_outer = false

            if circle_loop?(contour)
              drill_contours << contour
            else
              profile_contours << contour
            end
          end
        end

        unless drill_contours.empty?
          operations << ExportOperation.new(:drill, thickness, drill_contours)
        end

        unless profile_contours.empty?
          operations << ExportOperation.new(:profile, thickness, profile_contours)
        end

        # Pockets: all loops of intermediate-level faces
        pocket_groups.each do |depth, faces|
          pocket_contours = []
          faces.each do |face_dict|
            face_obj = face_dict[:face]
            face_obj.loops.each do |loop|
              contour = extract_loop(loop, origin, u_axis, v_axis, world_transform)
              next unless contour
              contour.is_outer = loop.outer?
              pocket_contours << contour
            end
          end
          unless pocket_contours.empty?
            operations << ExportOperation.new(:pocket, depth, pocket_contours)
          end
        end

        operations
      end

      # Build a 2D projection frame orthogonal to a world-space normal.
      def self.build_axes_from_normal(normal)
        if normal.z.abs > 0.9
          # For horizontal faces (normal along Z)
          u = Geom::Vector3d.new(1, 0, 0)
          # Looking down (normal.z > 0): standard orientation
          # Looking up (normal.z < 0): flip Y to maintain correct handedness
          v = normal.z > 0 ? Geom::Vector3d.new(0, 1, 0) : Geom::Vector3d.new(0, -1, 0)
        elsif normal.x.abs > 0.9
          # For faces perpendicular to X axis
          if normal.x < 0
            # Looking along -X: Y goes down, Z goes right
            u = Geom::Vector3d.new(0, -1, 0)
            v = Geom::Vector3d.new(0, 0, 1)  # Changed from -1 to 1
          else
            # Looking along +X: Y goes up, Z goes right
            u = Geom::Vector3d.new(0, 1, 0)
            v = Geom::Vector3d.new(0, 0, 1)  # Changed from -1 to 1
          end
        elsif normal.y.abs > 0.9
          # For faces perpendicular to Y axis
          if normal.y < 0
            # Looking along -Y: X goes right, Z goes down
            u = Geom::Vector3d.new(1, 0, 0)
            v = Geom::Vector3d.new(0, 0, 1)  # Changed from -1 to 1
          else
            # Looking along +Y: X goes left, Z goes down
            u = Geom::Vector3d.new(-1, 0, 0)
            v = Geom::Vector3d.new(0, 0, 1)  # Changed from -1 to 1
          end
        else
          # For arbitrary orientations, use cross product
          ref = Geom::Vector3d.new(0, 0, 1)
          u = ref.cross(normal)
          u.normalize!
          v = normal.cross(u)
          v.normalize!
        end

        [u, v]
      end

      # Project a 3D point to 2D using the given origin and axes.
      def self.project_point(point3d, origin, u_axis, v_axis)
        dx = point3d.x - origin.x
        dy = point3d.y - origin.y
        dz = point3d.z - origin.z

        u = dx * u_axis.x + dy * u_axis.y + dz * u_axis.z
        v = dx * v_axis.x + dy * v_axis.y + dz * v_axis.z

        [u, v]
      end

      # Extract a single loop into an ExportContour. All vertex positions are
      # transformed to world space before projection so that scale, mirror, and
      # rotation of the containing instance are baked into the 2D output. Arc
      # radii are derived from the projected 2D points rather than a separate
      # scale factor, so they're correct regardless of how scale is expressed
      # in the transformation matrix.
      def self.extract_loop(loop, origin, u_axis, v_axis, world_transform = Geom::Transformation.new)
        edges = loop.edges
        return nil if edges.empty?

        segments = []
        i = 0

        while i < edges.length
          edge = edges[i]
          curve = edge.curve

          if curve.is_a?(Sketchup::ArcCurve)
            # Collect consecutive edges of this arc
            arc_edges = [edge]
            j = i + 1
            while j < edges.length && edges[j].curve == curve
              arc_edges << edges[j]
              j += 1
            end

            # Full circle?
            if (curve.end_angle - curve.start_angle - 2 * Math::PI).abs < 0.01
              center_world = world_transform * curve.center
              center_2d = project_point(center_world, origin, u_axis, v_axis)
              # Radius = 2D distance from projected center to any point on the circle.
              sample_world = world_transform * arc_edges.first.start.position
              sample_2d = project_point(sample_world, origin, u_axis, v_axis)
              radius_2d = Math.sqrt(
                (sample_2d[0] - center_2d[0])**2 + (sample_2d[1] - center_2d[1])**2
              )
              segments << CircleSeg.new(center_2d, radius_2d)
            else
              # Partial arc
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

              start_world = world_transform * start_pt
              end_world = world_transform * end_pt
              center_world = world_transform * curve.center

              start_2d = project_point(start_world, origin, u_axis, v_axis)
              end_2d = project_point(end_world, origin, u_axis, v_axis)
              center_2d = project_point(center_world, origin, u_axis, v_axis)

              # Radius = 2D distance from projected center to projected start.
              radius_2d = Math.sqrt(
                (start_2d[0] - center_2d[0])**2 + (start_2d[1] - center_2d[1])**2
              )

              # Sample a midpoint on the actual arc to determine sweep direction.
              # Sampled in world space so a mirrored instance correctly flips
              # the computed sweep flag.
              mid_edge = arc_edges[arc_edges.length / 2]
              mid_pt_3d = Geom::Point3d.linear_combination(
                0.5, mid_edge.start.position, 0.5, mid_edge.end.position
              )
              mid_world = world_transform * mid_pt_3d
              mid_2d = project_point(mid_world, origin, u_axis, v_axis)

              subtended_angle = (curve.end_angle - curve.start_angle).abs
              clockwise, large_arc = compute_arc_flags(
                start_2d, end_2d, mid_2d, subtended_angle
              )

              segments << ArcSeg.new(start_2d, end_2d, center_2d, radius_2d, clockwise, large_arc)
            end

            i = j
          else
            # Straight edge or non-arc curve edge
            reversed = edge.reversed_in?(loop.face)
            start_pt = reversed ? edge.end.position : edge.start.position
            end_pt = reversed ? edge.start.position : edge.end.position

            start_world = world_transform * start_pt
            end_world = world_transform * end_pt

            start_2d = project_point(start_world, origin, u_axis, v_axis)
            end_2d = project_point(end_world, origin, u_axis, v_axis)

            segments << LineSeg.new(start_2d, end_2d)
            i += 1
          end
        end

        return nil if segments.empty?
        ExportContour.new(segments, true, true)
      end

      # Compute SVG arc sweep and large-arc flags using a 2D midpoint sample.
      # mid_2d is an actual point on the arc, projected to 2D.
      # subtended_angle is the arc's angle from ArcCurve (always positive).
      def self.compute_arc_flags(start_2d, end_2d, mid_2d, subtended_angle)
        dx_se = end_2d[0] - start_2d[0]
        dy_se = end_2d[1] - start_2d[1]
        dx_sm = mid_2d[0] - start_2d[0]
        dy_sm = mid_2d[1] - start_2d[1]

        cross = dx_se * dy_sm - dy_se * dx_sm

        # For near-semicircular arcs (≈180°), the large-arc flag is ambiguous
        # since both possible arcs are the same size. Floating point can push
        # the angle slightly past π, flipping both flags and producing the
        # wrong arc. Force large_arc=false so only sweep determines direction.
        if (subtended_angle - Math::PI).abs < 0.01
          large_arc = false
          clockwise = cross < 0
        else
          large_arc = subtended_angle > Math::PI
          clockwise = large_arc ? (cross > 0) : (cross < 0)
        end

        [clockwise, large_arc]
      end

      def self.circle_loop?(contour)
        segs = contour.segments
        return true if segs.length == 1 && segs[0].is_a?(CircleSeg)

        if segs.length == 2 && segs.all? { |s| s.is_a?(ArcSeg) }
          c1, c2 = segs
          dist = Math.sqrt((c1.center[0] - c2.center[0])**2 + (c1.center[1] - c2.center[1])**2)
          return dist < 0.001 && (c1.radius - c2.radius).abs < 0.001
        end

        false
      end

      private

      def self.collect_solids(entity, results, parent_transform, ancestor_pids)
        return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        world_transform = parent_transform * entity.transformation

        if entity.manifold?
          results << {
            entity:         entity,
            transform:      world_transform,
            ancestor_pids:  ancestor_pids
          }
        else
          child_ancestors = ancestor_pids + [entity.persistent_id]
          entity.definition.entities.each do |child|
            collect_solids(child, results, world_transform, child_ancestors)
          end
        end
      end

      def self.collect_non_solids(entity, results, parent_transform)
        return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        world_transform = parent_transform * entity.transformation
        return if entity.manifold?

        child_containers = entity.definition.entities.select do |e|
          e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        end

        if child_containers.empty?
          results << { entity: entity, transform: world_transform }
        else
          child_containers.each do |child|
            collect_non_solids(child, results, world_transform)
          end
        end
      end

      def self.group_faces_by_normal(planar_faces)
        groups = []

        planar_faces.each do |face_info|
          n = face_info[:normal]
          matched = groups.find do |g|
            gn = g[:normal]
            dot = n[0] * gn[0] + n[1] * gn[1] + n[2] * gn[2]
            dot.abs > 0.9999
          end

          if matched
            matched[:faces] << face_info
            matched[:total_area] += face_info[:area]
          else
            groups << {
              normal: n,
              faces:  [face_info],
              total_area: face_info[:area]
            }
          end
        end

        groups
      end

      def self.group_by_level(faces, key, tolerance)
        levels = {}

        faces.each do |f|
          val = f[key]
          matched_key = levels.keys.find { |k| (k - val).abs < tolerance }
          if matched_key
            levels[matched_key] << f
          else
            levels[val] = [f]
          end
        end

        levels.sort_by { |k, _| k }
      end

      def self.flat_result(sheet_faces, sheet_normal)
        profile_face_info = sheet_faces.max_by { |f| f[:area] }
        {
          profile_face:       profile_face_info[:face],
          profile_normal:     profile_face_info[:normal],
          profile_origin:     profile_face_info[:origin],
          through_hole_faces: sheet_faces,
          thickness:          0.0,
          pocket_faces:       [],
          sheet_normal:       sheet_normal
        }
      end

    end
  end
end
