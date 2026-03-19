module EricDesign
  module CNCExporter
    module Units
      def self.inches_to_mm(val)
        val * 25.4
      end

      def self.inches_to_in(val)
        val
      end

      def self.to_unit(val, unit)
        unit == "mm" ? inches_to_mm(val) : inches_to_in(val)
      end

      def self.format_coord(val, unit)
        unit == "mm" ? "%.4f" % val : "%.6f" % val
      end

      def self.format_depth(val, unit)
        formatted = format_coord(val, unit)
        formatted.sub(/0+$/, '').sub(/\.$/, '.0')
      end

      def self.unit_label(unit)
        unit == "mm" ? "mm" : "in"
      end

      def self.stroke_width(unit)
        unit == "mm" ? "0.18" : "0.007"
      end
    end

    def self.face_centroid(face)
      pts = face.vertices.map(&:position)
      cx = pts.sum { |p| p.x } / pts.length.to_f
      cy = pts.sum { |p| p.y } / pts.length.to_f
      cz = pts.sum { |p| p.z } / pts.length.to_f
      Geom::Point3d.new(cx, cy, cz)
    end

    def self.part_name(entity)
      if entity.is_a?(Sketchup::ComponentInstance)
        name = entity.name
        name = entity.definition.name if name.nil? || name.empty?
        name
      elsif entity.is_a?(Sketchup::Group)
        name = entity.name
        (name.nil? || name.empty?) ? nil : name
      end
    end

    def self.default_output_unit
      model = Sketchup.active_model
      return "mm" unless model
      options = model.options["UnitsOptions"]
      return "mm" unless options
      length_unit = options["LengthUnit"]
      [2, 3, 4].include?(length_unit) ? "mm" : "in"
    end
  end
end
