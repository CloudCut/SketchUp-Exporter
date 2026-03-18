require 'json'

module EricDesign
  module CNCExporter

    # Data structures
    LineSeg = Struct.new(:start_pt, :end_pt)
    ArcSeg = Struct.new(:start_pt, :end_pt, :center, :radius, :clockwise, :large_arc)
    CircleSeg = Struct.new(:center, :radius)
    ExportContour = Struct.new(:segments, :is_closed, :is_outer)
    ExportOperation = Struct.new(:op_type, :cut_depth, :contours)
    ExportComponent = Struct.new(:name, :guid, :operations, :bbox)

    # Load support files
    dir = __dir__.force_encoding('UTF-8')
    Sketchup.require(File.join(dir, "utils"))
    Sketchup.require(File.join(dir, "geometry_extractor"))
    Sketchup.require(File.join(dir, "path_converter"))
    Sketchup.require(File.join(dir, "svg_builder"))
    Sketchup.require(File.join(dir, "json_builder"))
    Sketchup.require(File.join(dir, "dialog"))
    Sketchup.require(File.join(dir, "updater"))

    # Menu and toolbar setup
    unless @loaded
      cmd_export = UI::Command.new("Export SVG/JSON") { show_export_dialog }
      cmd_export.small_icon = File.join(dir, "icons", "icon_16.png")
      cmd_export.large_icon = File.join(dir, "icons", "icon_24.png")
      cmd_export.tooltip = "Export SVG/JSON"
      cmd_export.status_bar_text = "Export selected solid groups/components as CNC-ready SVG or JSON files."

      menu = UI.menu("Extensions")
      submenu = menu.add_submenu("CNC Exporter")
      submenu.add_item(cmd_export)

      cmd_update = UI::Command.new("Check for Updates") { Updater.check_for_update(silent: false) }
      cmd_update.tooltip = "Check for CNC Exporter updates on GitHub"
      submenu.add_item(cmd_update)

      toolbar = UI::Toolbar.new("CNC Exporter")
      toolbar.add_item(cmd_export)
      toolbar.restore

      # Check for updates in the background (silent — only prompts if update found)
      Updater.check_on_startup

      @loaded = true
    end

  end
end
