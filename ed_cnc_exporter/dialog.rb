module EricDesign
  module CNCExporter

    # Keep a reference to prevent garbage collection closing the dialog.
    @export_dialog = nil

    def self.show_export_dialog
      model = Sketchup.active_model
      unless model
        UI.messagebox("No model is open.")
        return
      end

      selection = model.selection
      solids = GeometryExtractor.find_solids_in_selection(selection)

      if solids.empty?
        UI.messagebox(
          "No solid groups or components selected.\n\n" \
          "Select one or more groups/components that SketchUp considers 'Solid' " \
          "(shown in Entity Info), then try again."
        )
        return
      end

      # Gather metadata for the dialog
      parts_info = []
      unnamed_count = 0
      solids.each do |entity|
        name = part_name(entity)
        unless name
          unnamed_count += 1
          name = "Solid_%03d" % unnamed_count
        end

        classified = GeometryExtractor.classify_faces(entity.definition.entities)
        thickness_in = classified ? classified[:thickness] : 0.0
        thickness_mm = Units.inches_to_mm(thickness_in)

        material_name = entity.material ? entity.material.display_name : "(none)"

        parts_info << {
          name: name,
          guid: entity.guid,
          thickness_in: thickness_in,
          thickness_mm: thickness_mm,
          material: material_name
        }
      end

      # Unique materials and thicknesses
      materials = parts_info.map { |p| p[:material] }.uniq.sort
      thicknesses = parts_info.map { |p| p[:thickness_mm].round(2) }.uniq.sort

      default_unit = default_output_unit

      # Build parts JSON for the dialog
      parts_json = parts_info.map { |p|
        "{\"name\":#{json_str(p[:name])},\"thickness\":#{p[:thickness_mm].round(2)},\"material\":#{json_str(p[:material])}}"
      }.join(",")

      materials_json = materials.map { |m| json_str(m) }.join(",")
      thicknesses_json = thicknesses.map { |t| t.to_s }.join(",")

      html_path = File.join(__dir__.force_encoding('UTF-8'), "html", "export_dialog.html")

      @export_dialog.close if @export_dialog

      dialog = UI::HtmlDialog.new(
        dialog_title: "CNC Exporter",
        preferences_key: "EricDesign_CNCExporter",
        width: 500,
        height: 600,
        resizable: true
      )

      dialog.add_action_callback("initData") do |_ctx|
        js = "initDialog([#{parts_json}], [#{materials_json}], [#{thicknesses_json}], #{json_str(default_unit)});"
        dialog.execute_script(js)
      end

      dialog.add_action_callback("doExport") do |_ctx, options_json|
        begin
          options = JSON.parse(options_json)
          perform_export(options, solids, parts_info)
        rescue => e
          UI.messagebox("Export failed: #{e.message}")
        end
      end

      dialog.add_action_callback("doCancel") do |_ctx|
        dialog.close
      end

      dialog.set_file(html_path)
      dialog.show

      @export_dialog = dialog
    end

    def self.perform_export(options, solids, parts_info)
      format = options["format"] || "svg"
      unit = options["units"] || "mm"
      selected_materials = options["materials"] || []
      selected_thicknesses = (options["thicknesses"] || []).map { |t| t.to_f }

      # Filter parts
      filtered_indices = []
      parts_info.each_with_index do |pi, idx|
        next unless selected_materials.include?(pi[:material])
        next unless selected_thicknesses.any? { |t| (t - pi[:thickness_mm].round(2)).abs < 0.01 }
        filtered_indices << idx
      end

      if filtered_indices.empty?
        UI.messagebox("No parts match the selected filters.")
        return
      end

      # Extract geometry for each filtered part
      export_components = []
      filtered_indices.each do |idx|
        entity = solids[idx]
        pi = parts_info[idx]

        classified = GeometryExtractor.classify_faces(entity.definition.entities)
        next unless classified

        operations = GeometryExtractor.extract_contours(classified)
        next if operations.empty?

        export_components << ExportComponent.new(
          pi[:name],
          pi[:guid],
          operations,
          nil
        )
      end

      if export_components.empty?
        UI.messagebox("No exportable geometry found in the selected parts.")
        return
      end

      # Group by thickness
      thickness_groups = {}
      filtered_indices.each_with_index do |orig_idx, i|
        next if i >= export_components.length
        pi = parts_info[orig_idx]
        thickness_key = pi[:thickness_mm].round(2)
        (thickness_groups[thickness_key] ||= []) << export_components[i]
      end

      model = Sketchup.active_model
      base_name = model.title
      base_name = "export" if base_name.nil? || base_name.empty?

      ext = format == "svg" ? "svg" : "json"

      thickness_groups.each do |thickness_mm, components|
        thickness_str = Units.format_depth(thickness_mm, "mm")
        default_filename = "#{base_name}_#{thickness_str}mm.#{ext}"

        path = UI.savepanel("Save #{ext.upcase} File", "", default_filename)
        next unless path

        # Ensure correct extension
        path += ".#{ext}" unless path.downcase.end_with?(".#{ext}")

        content = if format == "svg"
          SvgBuilder.build_svg(components, unit)
        else
          JsonBuilder.build_json(components, unit)
        end

        File.write(path, content)
      end

      @export_dialog.close if @export_dialog
      UI.messagebox("Export complete!")
    end

    private

    def self.json_str(s)
      "\"#{s.to_s.gsub("\\", "\\\\\\\\").gsub("\"", "\\\"")}\""
    end

  end
end
