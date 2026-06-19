module CloudCut
  module Exporter

    # A transient view tool that paints a set of entities red. Used to point
    # out non-solid parts that can't be exported: each part's faces are filled
    # with translucent red and its edges outlined in solid red, so the whole
    # component clearly reads as flagged. The overlay is purely visual (no
    # geometry is added to the model) and stays visible until the user clicks
    # in the model, presses Escape, or switches to another tool.
    class NonSolidHighlightTool
      RED  = Sketchup::Color.new(255, 0, 0)        # opaque, for edges
      FILL = Sketchup::Color.new(255, 0, 0, 128)   # translucent, for faces

      # parts is an array of { entity:, transform: } hashes, where transform
      # already maps the entity's definition space into world space (the caller
      # folds in any parent and edit-context transforms). This is what makes
      # deeply nested non-solid parts land in the right place.
      def initialize(parts)
        @triangles = []   # flat list of world points, 3 per triangle (GL_TRIANGLES)
        @edges     = []   # flat list of world points, 2 per segment (GL_LINES)
        parts.each do |part|
          collect_mesh(part[:entity], part[:transform])
        end
      end

      def activate
        Sketchup.status_text =
          "Non-solid parts shown in red — click in the model to dismiss."
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        Sketchup.status_text = ""
        view.invalidate
      end

      def draw(view)
        unless @triangles.empty?
          view.drawing_color = FILL
          view.draw(GL_TRIANGLES, @triangles)
        end
        unless @edges.empty?
          view.drawing_color = RED
          view.line_width = 2
          view.line_stipple = ""
          view.draw(GL_LINES, @edges)
        end
      end

      # Click anywhere to dismiss the highlight.
      def onLButtonDown(_flags, _x, _y, _view)
        Sketchup.active_model.select_tool(nil)
      end

      # Escape dismisses the highlight.
      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end

      private

      # Recursively gather world-space triangles and edges for an entity,
      # descending through nested groups/components and accumulating their
      # transforms. transform maps this entity's definition space into world
      # space.
      def collect_mesh(entity, transform)
        return unless entity.respond_to?(:definition) && entity.definition

        entity.definition.entities.each do |e|
          case e
          when Sketchup::Face
            mesh = e.mesh
            mesh.polygons.each do |poly|
              idx = poly.map(&:abs)
              base = transform * mesh.point_at(idx[0])
              (1...(idx.length - 1)).each do |k|
                @triangles << base
                @triangles << transform * mesh.point_at(idx[k])
                @triangles << transform * mesh.point_at(idx[k + 1])
              end
            end
          when Sketchup::Edge
            @edges << transform * e.start.position
            @edges << transform * e.end.position
          when Sketchup::Group, Sketchup::ComponentInstance
            collect_mesh(e, transform * e.transformation)
          end
        end
      end
    end

    # Activate a transient tool that paints the given non-solid parts red.
    # Each part is a { entity:, transform: } hash whose transform maps the
    # entity's definition space into the top-level selection space; here we
    # fold in the current edit context to reach true world space.
    def self.highlight_non_solids(non_solids)
      return if non_solids.empty?
      model = Sketchup.active_model
      edit = model.edit_transform
      parts = non_solids.map do |s|
        { entity: s[:entity], transform: edit * s[:transform] }
      end
      model.select_tool(NonSolidHighlightTool.new(parts))
    end

  end
end
