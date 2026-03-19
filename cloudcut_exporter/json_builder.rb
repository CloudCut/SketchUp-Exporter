require 'json'

module EricDesign
  module CNCExporter
    module JsonBuilder

      # Build a JSON string from an array of ExportComponent objects.
      # unit is "mm" or "in".
      def self.build_json(components, unit)
        margin = unit == "mm" ? 25.4 : 1.0
        spacing = unit == "mm" ? 25.4 : 1.0

        # Layout: horizontal strip
        layouts = compute_layout(components, unit, margin, spacing)

        result = {
          "exporterVersion" => "v4-1in-spacing",
          "units"      => Units.unit_label(unit),
          "width"      => round_val(layouts[:total_width], unit),
          "height"     => round_val(layouts[:total_height], unit),
          "components" => []
        }

        layouts[:items].each do |item|
          comp = item[:component]
          offset_x = item[:offset_x]
          offset_y = item[:offset_y]

          comp_json = {
            "name"       => comp.name,
            "sourceGuid" => comp.guid,
            "operations" => []
          }

          comp.operations.each do |op|
            op_json = {
              "type"     => op.op_type.to_s,
              "cutDepth" => round_val(Units.to_unit(op.cut_depth, unit), unit),
              "paths"    => [],
              "circles"  => []
            }

            op.contours.each do |contour|
              segs = contour.segments

              if segs.length == 1 && segs[0].is_a?(CircleSeg)
                circle = segs[0]
                cx = round_val(Units.to_unit(circle.center[0], unit) + offset_x, unit)
                cy = round_val(Units.to_unit(circle.center[1], unit) + offset_y, unit)
                r = round_val(Units.to_unit(circle.radius, unit), unit)
                op_json["circles"] << { "cx" => cx, "cy" => cy, "r" => r }
              else
                d = build_offset_path_d(segs, unit, offset_x, offset_y)
                op_json["paths"] << d if d
              end
            end

            comp_json["operations"] << op_json
          end

          result["components"] << comp_json
        end

        JSON.pretty_generate(result)
      end

      private

      def self.compute_layout(components, unit, margin, spacing)
        items = []
        x_cursor = margin
        max_height = 0.0

        components.each do |comp|
          bbox = compute_component_bbox(comp, unit)
          w = bbox[:width]
          h = bbox[:height]
          max_height = h if h > max_height

          items << {
            component: comp,
            offset_x: x_cursor - bbox[:min_x],
            offset_y: margin - bbox[:min_y],
            width: w,
            height: h
          }

          x_cursor += w + spacing
        end

        total_width = x_cursor - spacing + margin
        total_height = max_height + 2 * margin

        { items: items, total_width: total_width, total_height: total_height }
      end

      def self.compute_component_bbox(comp, unit)
        min_x = Float::INFINITY
        min_y = Float::INFINITY
        max_x = -Float::INFINITY
        max_y = -Float::INFINITY

        comp.operations.each do |op|
          op.contours.each do |contour|
            contour.segments.each do |seg|
              points = segment_points(seg)
              points.each do |pt|
                x = Units.to_unit(pt[0], unit)
                y = Units.to_unit(pt[1], unit)
                min_x = x if x < min_x
                min_y = y if y < min_y
                max_x = x if x > max_x
                max_y = y if y > max_y
              end
            end
          end
        end

        { min_x: min_x, min_y: min_y, max_x: max_x, max_y: max_y,
          width: max_x - min_x, height: max_y - min_y }
      end

      def self.segment_points(seg)
        if seg.is_a?(LineSeg)
          [seg.start_pt, seg.end_pt]
        elsif seg.is_a?(ArcSeg)
          [seg.start_pt, seg.end_pt,
           [seg.center[0] - seg.radius, seg.center[1] - seg.radius],
           [seg.center[0] + seg.radius, seg.center[1] + seg.radius]]
        elsif seg.is_a?(CircleSeg)
          [[seg.center[0] - seg.radius, seg.center[1] - seg.radius],
           [seg.center[0] + seg.radius, seg.center[1] + seg.radius]]
        else
          []
        end
      end

      def self.build_offset_path_d(segments, unit, offset_x, offset_y)
        return nil if segments.empty?

        parts = []
        segments.each_with_index do |seg, idx|
          if seg.is_a?(LineSeg)
            sx = fmt(Units.to_unit(seg.start_pt[0], unit) + offset_x, unit)
            sy = fmt(Units.to_unit(seg.start_pt[1], unit) + offset_y, unit)
            ex = fmt(Units.to_unit(seg.end_pt[0], unit) + offset_x, unit)
            ey = fmt(Units.to_unit(seg.end_pt[1], unit) + offset_y, unit)
            parts << "M#{sx},#{sy}" if idx == 0
            parts << "L#{ex},#{ey}"
          elsif seg.is_a?(ArcSeg)
            sx = fmt(Units.to_unit(seg.start_pt[0], unit) + offset_x, unit)
            sy = fmt(Units.to_unit(seg.start_pt[1], unit) + offset_y, unit)
            parts << "M#{sx},#{sy}" if idx == 0
            r = fmt(Units.to_unit(seg.radius, unit), unit)
            sweep_flag = seg.clockwise ? 1 : 0
            large_arc_flag = seg.large_arc ? 1 : 0
            ex = fmt(Units.to_unit(seg.end_pt[0], unit) + offset_x, unit)
            ey = fmt(Units.to_unit(seg.end_pt[1], unit) + offset_y, unit)
            parts << "A#{r},#{r} 0 #{large_arc_flag},#{sweep_flag} #{ex},#{ey}"
          elsif seg.is_a?(CircleSeg)
            cx = Units.to_unit(seg.center[0], unit) + offset_x
            cy = Units.to_unit(seg.center[1], unit) + offset_y
            r = Units.to_unit(seg.radius, unit)
            left_x = fmt(cx - r, unit)
            right_x = fmt(cx + r, unit)
            cy_s = fmt(cy, unit)
            r_s = fmt(r, unit)
            parts << "M#{left_x},#{cy_s} A#{r_s},#{r_s} 0 1,0 #{right_x},#{cy_s} A#{r_s},#{r_s} 0 1,0 #{left_x},#{cy_s} Z"
          end
        end

        parts << "Z" unless parts.last&.end_with?("Z")
        parts.join(" ")
      end

      def self.fmt(val, unit)
        Units.format_coord(val, unit)
      end

      def self.round_val(val, unit)
        unit == "mm" ? val.round(4) : val.round(6)
      end

    end
  end
end
