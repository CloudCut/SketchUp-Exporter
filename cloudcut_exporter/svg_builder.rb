module CloudCut
  module Exporter
    module SvgBuilder

      MARGIN_MM = 25.4   # 1 inch margin
      SPACING_MM = 25.4  # 1 inch between parts

      # Build an SVG string from an array of ExportComponent objects.
      # unit is "mm" or "in".
      def self.build_svg(components, unit, thickness_mm = nil)
        margin = margin_in_unit(unit)
        spacing = spacing_in_unit(unit)

        # Compute bounding boxes and layout positions
        layouts = compute_layout(components, unit, margin, spacing)
        total_width = layouts[:total_width]
        total_height = layouts[:total_height]

        sw = Units.stroke_width(unit)
        unit_label = Units.unit_label(unit)

        lines = []
        lines << '<?xml version="1.0" encoding="UTF-8"?>'
        lines << '<!-- CNC Exporter v4 - 1in spacing -->'
        stock_thickness_attr = if thickness_mm
          thickness_val = unit == "mm" ? thickness_mm : thickness_mm / 25.4
          " data-stock-thickness=\"#{fmt(thickness_val, unit)}\""
        else
          ""
        end
        lines << "<svg xmlns=\"http://www.w3.org/2000/svg\""
        lines << "     width=\"#{fmt(total_width, unit)}#{unit_label}\" height=\"#{fmt(total_height, unit)}#{unit_label}\""
        lines << "     viewBox=\"0 0 #{fmt(total_width, unit)} #{fmt(total_height, unit)}\"#{stock_thickness_attr}>"
        lines << ""

        layouts[:items].each_with_index do |item, comp_idx|
          comp = item[:component]
          offset_x = item[:offset_x]
          offset_y = item[:offset_y]

          lines << "  <!-- Component: #{xml_escape(comp.name)} -->"
          lines << "  <g data-component=\"#{xml_escape(comp.name)}\" id=\"component-#{comp_idx + 1}\" data-source-guid=\"#{xml_escape(comp.guid)}\">"
          lines << ""

          comp.operations.each do |op|
            depth_str = Units.format_depth(Units.to_unit(op.cut_depth, unit), unit)
            op_label = op.op_type.to_s.upcase
            op_id = "#{op_label}: #{depth_str}"

            lines << "    <g id=\"#{xml_escape(op_id)}\" data-operation=\"#{op.op_type}\" data-cut-depth=\"#{depth_str}\">"

            op.contours.each do |contour|
              segs = contour.segments

              # Check for single circle (drill/pocket circle)
              if segs.length == 1 && segs[0].is_a?(CircleSeg)
                circle = segs[0]
                cx = fmt(Units.to_unit(circle.center[0], unit) + offset_x, unit)
                cy = fmt(Units.to_unit(circle.center[1], unit) + offset_y, unit)
                r = fmt(Units.to_unit(circle.radius, unit), unit)
                fill, stroke = style_for_op(op.op_type)
                lines << "      <circle cx=\"#{cx}\" cy=\"#{cy}\" r=\"#{r}\" fill=\"#{fill}\" stroke=\"#{stroke}\" stroke-width=\"#{sw}\"/>"
              else
                # Build path d-string with offset applied
                d = build_offset_path_d(segs, unit, offset_x, offset_y)
                if d
                  fill, stroke = style_for_op(op.op_type)
                  lines << "      <path d=\"#{d}\" fill=\"#{fill}\" stroke=\"#{stroke}\" stroke-width=\"#{sw}\"/>"
                end
              end
            end

            lines << "    </g>"
            lines << ""
          end

          lines << "  </g>"
          lines << ""
        end

        lines << "</svg>"
        lines.join("\n")
      end

      private

      def self.margin_in_unit(unit)
        unit == "mm" ? MARGIN_MM : MARGIN_MM / 25.4
      end

      def self.spacing_in_unit(unit)
        unit == "mm" ? SPACING_MM : SPACING_MM / 25.4
      end

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
            height: h,
            bbox: bbox
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
          # Include start, end, and approximate extent via center +/- radius
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

        # Single circle
        if segments.length == 1 && segments[0].is_a?(CircleSeg)
          circle = segments[0]
          cx = Units.to_unit(circle.center[0], unit) + offset_x
          cy = Units.to_unit(circle.center[1], unit) + offset_y
          r = Units.to_unit(circle.radius, unit)
          left_x = fmt(cx - r, unit)
          right_x = fmt(cx + r, unit)
          cy_s = fmt(cy, unit)
          r_s = fmt(r, unit)
          return "M#{left_x},#{cy_s} A#{r_s},#{r_s} 0 1,0 #{right_x},#{cy_s} A#{r_s},#{r_s} 0 1,0 #{left_x},#{cy_s} Z"
        end

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
          end
        end

        parts << "Z"
        parts.join(" ")
      end

      def self.style_for_op(op_type)
        case op_type
        when :profile
          ["none", "black"]
        when :drill
          ["black", "none"]
        when :pocket
          ["gray", "none"]
        when :engrave
          ["none", "blue"]
        else
          ["none", "black"]
        end
      end

      def self.fmt(val, unit)
        Units.format_coord(val, unit)
      end

      def self.xml_escape(str)
        str.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("\"", "&quot;")
      end

    end
  end
end
