module CloudCut
  module Exporter
    module PathConverter

      # Convert an array of segments to an SVG path d-string.
      # Returns the d attribute value, or nil for circles (handled separately).
      def self.segments_to_path_d(segments, unit)
        return nil if segments.empty?

        # Single full circle — use two semicircular arcs
        if segments.length == 1 && segments[0].is_a?(CircleSeg)
          return circle_to_path_d(segments[0], unit)
        end

        parts = []
        segments.each_with_index do |seg, idx|
          if seg.is_a?(CircleSeg)
            # Circle embedded in a path (shouldn't normally happen)
            parts << circle_to_path_d(seg, unit)
          elsif seg.is_a?(LineSeg)
            if idx == 0
              parts << "M#{fmt(seg.start_pt[0], unit)},#{fmt(seg.start_pt[1], unit)}"
            end
            parts << "L#{fmt(seg.end_pt[0], unit)},#{fmt(seg.end_pt[1], unit)}"
          elsif seg.is_a?(ArcSeg)
            if idx == 0
              parts << "M#{fmt(seg.start_pt[0], unit)},#{fmt(seg.start_pt[1], unit)}"
            end
            r = fmt(Units.to_unit(seg.radius, unit), unit)
            sweep_flag = seg.clockwise ? 1 : 0
            large_arc_flag = seg.large_arc ? 1 : 0
            ex = fmt(seg.end_pt[0], unit)
            ey = fmt(seg.end_pt[1], unit)
            parts << "A#{r},#{r} 0 #{large_arc_flag},#{sweep_flag} #{ex},#{ey}"
          end
        end

        parts << "Z"
        parts.join(" ")
      end

      # Convert a CircleSeg to two semicircular arcs for SVG.
      def self.circle_to_path_d(circle, unit)
        cx = Units.to_unit(circle.center[0], unit)
        cy = Units.to_unit(circle.center[1], unit)
        r = Units.to_unit(circle.radius, unit)

        left_x = fmt_val(cx - r, unit)
        right_x = fmt_val(cx + r, unit)
        cy_s = fmt_val(cy, unit)
        r_s = fmt_val(r, unit)

        "M#{left_x},#{cy_s} A#{r_s},#{r_s} 0 1,0 #{right_x},#{cy_s} A#{r_s},#{r_s} 0 1,0 #{left_x},#{cy_s} Z"
      end

      private

      # Format a coordinate value: convert from inches to output unit, then format.
      def self.fmt(val_inches, unit)
        Units.format_coord(Units.to_unit(val_inches, unit), unit)
      end

      # Format a value already in the output unit.
      def self.fmt_val(val, unit)
        Units.format_coord(val, unit)
      end

    end
  end
end
