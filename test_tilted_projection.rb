#!/usr/bin/env ruby

# Regression test for tilted-face projection (build_axes_from_normal).
#
# Bug: a part identical in size to others but tilted in 3D space exported at the
# wrong size. A rectangle tilted 75 deg came out at 300 * sin(75) = 289.778 mm
# instead of 300 mm, because the projection frame fell back to raw world axes
# (the face's "shadow") instead of axes lying in the face's own plane.
#
# This test tilts the SAME rectangle to many angles about several axes and
# asserts the projected 2D bounding box always measures the true size. It also
# pins the flat / square-to-axis cases so the fix stays backward compatible.
#
# Run in SketchUp's Ruby Console:
#   load File.join(Sketchup.find_support_file("Plugins"), "..", "..", "test_tilted_projection.rb")
# or just paste the file. It loads the INSTALLED extension, not the repo copy.

require 'sketchup'
Sketchup.require File.join(Sketchup.find_support_file("Plugins"), "cloudcut_exporter", "geometry_extractor")

module TiltedProjectionTest
  extend self

  GE = CloudCut::Exporter::GeometryExtractor

  TRUE_W = 200.0  # rectangle extent along local X
  TRUE_H = 300.0  # rectangle extent along local Y
  TOL    = 1e-4

  # Local rectangle corners in its own plane (normal = +Z when flat).
  def corners
    [
      Geom::Point3d.new(0,       0,      0),
      Geom::Point3d.new(TRUE_W,  0,      0),
      Geom::Point3d.new(TRUE_W,  TRUE_H, 0),
      Geom::Point3d.new(0,       TRUE_H, 0)
    ]
  end

  # Project the tilted rectangle and return the four edge lengths, in corner
  # order (P0-P1, P1-P2, P2-P3, P3-P0). Edge lengths are rotation-invariant, so
  # they measure the true size regardless of how the part is turned within its
  # own plane -- unlike an axis-aligned bounding box, which grows when the
  # rectangle is rotated relative to the u/v axes.
  def projected_edges(transform)
    world_normal = GE.transform_direction(Geom::Vector3d.new(0, 0, 1), transform)
    u_axis, v_axis = GE.build_axes_from_normal(world_normal)

    world_pts = corners.map { |p| transform * p }
    origin = world_pts.first
    pr = world_pts.map { |p| GE.project_point(p, origin, u_axis, v_axis) }

    (0..3).map do |i|
      a = pr[i]
      b = pr[(i + 1) % 4]
      Math.sqrt((a[0] - b[0])**2 + (a[1] - b[1])**2)
    end
  end

  # After any rigid tilt the projected outline must stay a congruent
  # 200 x 300 rectangle: edges 200, 300, 200, 300 in order.
  def edges_ok?(e)
    (e[0] - TRUE_W).abs < TOL && (e[1] - TRUE_H).abs < TOL &&
      (e[2] - TRUE_W).abs < TOL && (e[3] - TRUE_H).abs < TOL
  end

  def check(description, transform)
    e = projected_edges(transform)
    ok = edges_ok?(e)
    @total += 1
    @passed += 1 if ok
    status = ok ? "PASS" : "FAIL"
    printf("  [%s] %-34s  edges=[%s]\n", status, description,
           e.map { |x| format('%.3f', x) }.join(", "))
    ok
  end

  # Tilt about a world axis by the given degrees.
  def tilt(axis, degrees)
    Geom::Transformation.rotation([0, 0, 0], axis, degrees * Math::PI / 180.0)
  end

  def run
    @total = 0
    @passed = 0

    puts "=" * 66
    puts "TILTED-FACE PROJECTION REGRESSION TEST  (true size #{TRUE_W} x #{TRUE_H})"
    puts "=" * 66

    puts "\nFlat baseline (must stay exact):"
    check("flat (identity)", Geom::Transformation.new)
    check("flat rotated 90 deg about Z", tilt([0, 0, 1], 90))
    check("flat rotated 37 deg about Z", tilt([0, 0, 1], 37))

    # These angles span all three regimes of the old code: the near-Z shortcut
    # (< ~26 deg), the correct middle band, and the near-Y/X shortcut (> ~64
    # deg) -- including the exact 75 deg case from the customer's file.
    angles = [5, 15, 25, 26, 30, 45, 60, 64, 65, 75, 85, 89]

    puts "\nTilt about world X (lifts the 300 mm edge):"
    angles.each { |a| check("tilt X #{a} deg", tilt([1, 0, 0], a)) }

    puts "\nTilt about world Y (lifts the 200 mm edge):"
    angles.each { |a| check("tilt Y #{a} deg", tilt([0, 1, 0], a)) }

    puts "\nCompound tilt (about a diagonal axis):"
    [10, 40, 70].each do |a|
      t = tilt([0, 0, 1], 30) * tilt([1, 1, 0], a)
      check("Z30 then diag #{a} deg", t)
    end

    puts "\n" + "=" * 66
    printf("RESULT: %d / %d passed%s\n", @passed, @total,
           @passed == @total ? "  -- ALL GOOD" : "  -- REGRESSIONS PRESENT !!!")
    puts "=" * 66
    @passed == @total
  end
end

TiltedProjectionTest.run
