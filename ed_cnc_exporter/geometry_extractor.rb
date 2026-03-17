module EricDesign
  module CNCExporter
    module GeometryExtractor

      # Find all solid groups/components in the selection, recursively.
      def self.find_solids_in_selection(selection)
        solids = []
        selection.each { |entity| collect_solids(entity, solids) }
        solids
      end

      # Classify faces of a solid into profile, through-hole, and pocket groups.
      # Returns a hash with :profile_face, :through_hole_faces, :thickness,
      # :pocket_faces, :sheet_normal, or nil if classification fails.
      def self.classify_faces(entities)
        # Step 1: Collect all faces
        planar_faces = []
        entities.grep(Sketchup::Face).each do |face|
          normal = face.normal
          origin = CNCExporter.face_centroid(face)
          planar_faces << {
            face:   face,
            normal: [normal.x, normal.y, normal.z],
            origin: [origin.x, origin.y, origin.z],
            area:   face.area
          }
        end
        return nil if planar_faces.empty?

        # Step 2: Group faces by normal direction
        normal_groups = group_faces_by_normal(planar_faces)

        # Step 3: Sheet plane = group with largest total area
        best_group = normal_groups.max_by { |g| g[:total_area] }
        sheet_normal = best_group[:normal]
        sheet_faces = best_group[:faces]

        # Step 4: Project each face origin along sheet normal to get height
        sheet_faces.each do |f|
          ox, oy, oz = f[:origin]
          f[:height] = ox * sheet_normal[0] + oy * sheet_normal[1] + oz * sheet_normal[2]
        end

        # Step 5: Group by height level
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

        # Step 6: Determine which side pockets open from
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

        # Step 7: Profile face = bottom side (opposite from pocket openings)
        if pockets_open_toward_high
          machining_top_level = highest
          bottom_faces = low_faces
        else
          machining_top_level = lowest
          bottom_faces = high_faces
        end

        return nil if bottom_faces.empty?

        profile_face = bottom_faces.max_by { |f| f[:area] }[:face]

        pocket_groups = {}
        pocket_faces.each do |level, f|
          depth = (machining_top_level - level).abs
          key = pocket_groups.keys.find { |k| (k - depth).abs < 0.0001 } || depth
          (pocket_groups[key] ||= []) << f
        end
        pocket_groups = pocket_groups.sort_by { |depth, _| depth }

        {
          profile_face:       profile_face,
          through_hole_faces: bottom_faces,
          thickness:          thickness,
          pocket_faces:       pocket_groups,
          sheet_normal:       sheet_normal
        }
      end

      # Extract contours from classified faces, producing ExportOperation objects.
      def self.extract_contours(classified)
        return [] unless classified

        profile_face = classified[:profile_face]
        through_hole_faces = classified[:through_hole_faces]
        thickness = classified[:thickness]
        pocket_groups = classified[:pocket_faces]

        u_axis, v_axis = build_face_axes(profile_face)
        origin = CNCExporter.face_centroid(profile_face)

        operations = []

        # Profile: outer loop of the profile face
        outer_contour = extract_loop(profile_face.outer_loop, origin, u_axis, v_axis)
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
            contour = extract_loop(loop, origin, u_axis, v_axis)
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
              contour = extract_loop(loop, origin, u_axis, v_axis)
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

      # Build a 2D projection frame from a face.
      def self.build_face_axes(face)
        normal = face.normal

        if normal.z.abs > 0.9
          u = Geom::Vector3d.new(1, 0, 0)
          v = Geom::Vector3d.new(0, -1, 0)
        else
          ref = Geom::Vector3d.new(0, 0, 1)
          u = ref.cross(normal)
          u.normalize!
          v = normal.cross(u)
          v.reverse!
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

      # Extract a single loop into an ExportContour.
      def self.extract_loop(loop, origin, u_axis, v_axis)
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
              center_2d = project_point(curve.center, origin, u_axis, v_axis)
              segments << CircleSeg.new(center_2d, curve.radius)
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

              start_2d = project_point(start_pt, origin, u_axis, v_axis)
              end_2d = project_point(end_pt, origin, u_axis, v_axis)
              center_2d = project_point(curve.center, origin, u_axis, v_axis)
              radius = curve.radius

              # Sample a midpoint on the actual arc to determine sweep direction
              mid_edge = arc_edges[arc_edges.length / 2]
              mid_pt_3d = Geom::Point3d.linear_combination(
                0.5, mid_edge.start.position, 0.5, mid_edge.end.position
              )
              mid_2d = project_point(mid_pt_3d, origin, u_axis, v_axis)

              subtended_angle = (curve.end_angle - curve.start_angle).abs
              clockwise, large_arc = compute_arc_flags(
                start_2d, end_2d, mid_2d, subtended_angle
              )

              segments << ArcSeg.new(start_2d, end_2d, center_2d, radius, clockwise, large_arc)
            end

            i = j
          else
            # Straight edge or non-arc curve edge
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

      # Compute SVG arc sweep and large-arc flags using a 2D midpoint sample.
      # mid_2d is an actual point on the arc, projected to 2D.
      # subtended_angle is the arc's angle from ArcCurve (always positive).
      def self.compute_arc_flags(start_2d, end_2d, mid_2d, subtended_angle)
        # Cross product of (start→end) × (start→mid) determines which side
        # of the chord the arc bulges toward.
        dx_se = end_2d[0] - start_2d[0]
        dy_se = end_2d[1] - start_2d[1]
        dx_sm = mid_2d[0] - start_2d[0]
        dy_sm = mid_2d[1] - start_2d[1]

        cross = dx_se * dy_sm - dy_se * dx_sm

        large_arc = subtended_angle > Math::PI

        # The cross product tells us which side of the chord the arc bows toward.
        # For small arcs (<180°), the arc bows AWAY from center:
        #   cross > 0 (bows right in Y-down) → center is left → CCW (sweep=0)
        #   cross < 0 (bows left) → center is right → CW (sweep=1)
        # For large arcs (>180°), the relationship inverts.
        clockwise = large_arc ? (cross > 0) : (cross < 0)

        [clockwise, large_arc]
      end

      # Check if a contour is a single circle (drill candidate).
      def self.circle_loop?(contour)
        segs = contour.segments
        return true if segs.length == 1 && segs[0].is_a?(CircleSeg)

        # Two semicircular arcs with same center and radius
        if segs.length == 2 && segs.all? { |s| s.is_a?(ArcSeg) }
          c1, c2 = segs
          dist = Math.sqrt((c1.center[0] - c2.center[0])**2 + (c1.center[1] - c2.center[1])**2)
          return dist < 0.001 && (c1.radius - c2.radius).abs < 0.001
        end

        false
      end

      private

      def self.collect_solids(entity, solids)
        if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          if entity.manifold?
            solids << entity
          else
            entity.definition.entities.each do |child|
              collect_solids(child, solids)
            end
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
        profile_face = sheet_faces.max_by { |f| f[:area] }[:face]
        {
          profile_face:       profile_face,
          through_hole_faces: sheet_faces,
          thickness:          0.0,
          pocket_faces:       [],
          sheet_normal:       sheet_normal
        }
      end

    end
  end
end
