# ed_cnc_exporter.rb — Loader file (extension registration ONLY)
# This file must ONLY register the extension. All other code lives in
# the ed_cnc_exporter/ support folder and is loaded on demand.

module EricDesign
  module CNCExporter
    root = File.dirname(__FILE__).force_encoding('UTF-8')
    loader = File.join(root, "ed_cnc_exporter", "main") # NO .rb extension!

    EXTENSION = SketchupExtension.new("CNC Exporter", loader)
    EXTENSION.creator     = "Eric Design"
    EXTENSION.description = "Export selected solid groups and components " \
                            "as CNC-ready SVG and JSON files with automatic " \
                            "profile, pocket, drill, and through-hole detection."
    EXTENSION.version     = "1.0.0"
    EXTENSION.copyright   = "2026"
    Sketchup.register_extension(EXTENSION, true)
  end
end
