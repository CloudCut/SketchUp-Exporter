module CloudCut
  module Exporter

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

      # Reject non-uniform scale: arcs and circles become ellipses under
      # anisotropic scale, which can't be faithfully represented as CNC
      # toolpaths. Users must reset or bake scale before exporting.
      non_uniform = solids.reject { |s| GeometryExtractor.uniform_scale?(s[:transform]) }
      unless non_uniform.empty?
        names = non_uniform.map { |s| part_name(s[:entity]) || "(unnamed)" }.uniq.sort
        UI.messagebox(
          "Non-uniform scale detected on:\n  #{names.join("\n  ")}\n\n" \
          "Circles and arcs cannot be faithfully exported when X/Y/Z scales differ. " \
          "Reset the scale (right-click → Scale → Reset Scale) or explode and re-group " \
          "to bake the scale into the geometry, then export again."
        )
        return
      end

      # Gather metadata for the dialog
      parts_info = []
      unnamed_count = 0
      solids.each do |s|
        entity = s[:entity]
        transform = s[:transform]

        name = part_name(entity)
        unless name
          unnamed_count += 1
          name = "Solid_%03d" % unnamed_count
        end

        classified = GeometryExtractor.classify_faces(entity.definition.entities, transform)
        thickness_in = classified ? classified[:thickness] : 0.0
        thickness_mm = Units.inches_to_mm(thickness_in)

        material_name = entity.material ? entity.material.display_name : "(none)"

        parts_info << {
          name: name,
          guid: export_guid(entity, s[:ancestor_pids]),
          thickness_in: thickness_in,
          thickness_mm: thickness_mm,
          material: material_name
        }
      end

      # Cluster near-identical thicknesses so floating-point drift on the
      # stock plane doesn't split one nominal thickness into two groups.
      cluster_thicknesses(parts_info)

      # Unique materials and thicknesses
      materials = parts_info.map { |p| p[:material] }.uniq.sort
      thicknesses = parts_info.map { |p| p[:canonical_thickness_mm].round(2) }.uniq.sort

      default_unit = default_output_unit

      # Build parts JSON for the dialog
      parts_json = parts_info.map { |p|
        "{\"name\":#{json_str(p[:name])},\"thickness\":#{p[:canonical_thickness_mm].round(2)},\"material\":#{json_str(p[:material])}}"
      }.join(",")

      materials_json = materials.map { |m| json_str(m) }.join(",")
      thicknesses_json = thicknesses.map { |t| t.to_s }.join(",")

      html_path = File.join(__dir__.force_encoding('UTF-8'), "html", "export_dialog.html")

      @export_dialog.close if @export_dialog

      dialog = UI::HtmlDialog.new(
        dialog_title: "CloudCut v#{EXTENSION.version}",
        preferences_key: "CloudCut_Exporter",
        width: 500,
        height: 600,
        resizable: true
      )

      dialog.add_action_callback("initData") do |_ctx|
        js = "initDialog([#{parts_json}], [#{materials_json}], [#{thicknesses_json}], #{json_str(default_unit)}, #{json_str(EXTENSION.version)});"
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
      format = options["format"] || "json"
      unit = options["units"] || "mm"
      selected_materials = options["materials"] || []
      selected_thicknesses = (options["thicknesses"] || []).map { |t| t.to_f }

      # Filter parts
      filtered_indices = []
      parts_info.each_with_index do |pi, idx|
        next unless selected_materials.include?(pi[:material])
        next unless selected_thicknesses.any? { |t| (t - pi[:canonical_thickness_mm].round(2)).abs < 0.01 }
        filtered_indices << idx
      end

      if filtered_indices.empty?
        UI.messagebox("No parts match the selected filters.")
        return
      end

      # Extract geometry for each filtered part
      export_components = []
      filtered_indices.each do |idx|
        s = solids[idx]
        entity = s[:entity]
        transform = s[:transform]
        pi = parts_info[idx]

        classified = GeometryExtractor.classify_faces(entity.definition.entities, transform)
        next unless classified

        operations = GeometryExtractor.extract_contours(classified, transform)
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

      # Group by canonical thickness (shared across a cluster, so no rounding
      # needed — parts in the same cluster share the exact same value).
      thickness_groups = {}
      filtered_indices.each_with_index do |orig_idx, i|
        next if i >= export_components.length
        pi = parts_info[orig_idx]
        thickness_key = pi[:canonical_thickness_mm]
        (thickness_groups[thickness_key] ||= []) << export_components[i]
      end

      model = Sketchup.active_model
      base_name = model.title
      base_name = "export" if base_name.nil? || base_name.empty?

      ext = format == "svg" ? "svg" : "json"

      thickness_groups.each do |thickness_mm, components|
        if unit == "in"
          thickness_val = thickness_mm / 25.4
          thickness_str = Units.format_coord(thickness_val, "in")
          default_filename = "#{base_name}_#{thickness_str}in.#{ext}"
        else
          thickness_str = Units.format_coord(thickness_mm, "mm")
          default_filename = "#{base_name}_#{thickness_str}mm.#{ext}"
        end

        path = UI.savepanel("Save #{ext.upcase} File", "", default_filename)
        next unless path

        # Ensure correct extension
        path += ".#{ext}" unless path.downcase.end_with?(".#{ext}")

        content = if format == "svg"
          SvgBuilder.build_svg(components, unit, thickness_mm)
        else
          JsonBuilder.build_json(components, unit, thickness_mm)
        end

        File.write(path, content)
      end

      @export_dialog.close if @export_dialog

      choice = UI.messagebox(
        "Export complete!\n\nOpen CloudCut to process your file?",
        MB_OKCANCEL
      )
      UI.openURL("https://app.cloudcut.cam") if choice == IDOK
    end

    private

    # Generate a unique, stable identifier for an exported instance. Uses
    # entity.persistent_id (guaranteed unique per entity within a model) and
    # prefixes ancestor persistent_ids when an entity is reached through
    # multiple parent paths (nested shared-definition case), ensuring each
    # world-space placement gets a distinct sourceGuid.
    def self.export_guid(entity, ancestor_pids)
      path = ancestor_pids + [entity.persistent_id]
      path.join("/")
    end

    # Assign each part a canonical thickness shared by every other part within
    # tolerance. Prevents floating-point drift on the stock plane from splitting
    # one nominal thickness into two file groups (e.g. 0.725" landing at
    # 18.415 mm ± 1e-5 mm gets rounded to 18.41 vs 18.42).
    CLUSTER_TOLERANCE_MM = 0.05

    def self.cluster_thicknesses(parts_info)
      clusters = []

      parts_info.sort_by { |p| p[:thickness_mm] }.each do |part|
        t = part[:thickness_mm]
        cluster = clusters.find { |c| (c[:canonical_mm] - t).abs <= CLUSTER_TOLERANCE_MM }
        if cluster
          cluster[:parts] << part
          cluster[:canonical_mm] =
            cluster[:parts].sum { |p| p[:thickness_mm] } / cluster[:parts].length.to_f
        else
          clusters << { canonical_mm: t, parts: [part] }
        end
      end

      clusters.each do |cluster|
        canonical_mm = cluster[:canonical_mm]
        cluster[:parts].each do |part|
          part[:canonical_thickness_mm] = canonical_mm
          part[:canonical_thickness_in] = canonical_mm / 25.4
        end
      end
    end

    def self.json_str(s)
      "\"#{s.to_s.gsub("\\", "\\\\\\\\").gsub("\"", "\\\"")}\""
    end

  end
end
