#!/usr/bin/env ruby

# Test script to validate mirroring behavior for all scenarios
# Run this in SketchUp's Ruby Console to test all mirroring cases

require 'sketchup'
# Load the installed version, not the repo version
Sketchup.require File.join(Sketchup.find_support_file("Plugins"), "cloudcut_exporter", "geometry_extractor")

module MirrorTest
  extend self

  # Create a simple L-shaped test geometry that shows orientation clearly
  def create_test_face
    # Create an L-shape that makes orientation obvious
    # Points form an L when viewed from above (Z+)
    points = [
      [0, 0, 0],
      [10, 0, 0],
      [10, 5, 0],
      [5, 5, 0],
      [5, 10, 0],
      [0, 10, 0]
    ]
    points
  end

  # Test identity (no transformation)
  def test_identity
    puts "\n=== Testing Identity (no transformation) ==="
    transform = Geom::Transformation.new
    test_transform(transform, "Identity")
  end

  # Test pure rotations
  def test_rotations
    puts "\n=== Testing Pure Rotations ==="

    # 90° around Z
    transform = Geom::Transformation.rotation([0,0,0], [0,0,1], Math::PI/2)
    test_transform(transform, "90° rotation around Z")

    # 90° around X
    transform = Geom::Transformation.rotation([0,0,0], [1,0,0], Math::PI/2)
    test_transform(transform, "90° rotation around X")

    # 90° around Y
    transform = Geom::Transformation.rotation([0,0,0], [0,1,0], Math::PI/2)
    test_transform(transform, "90° rotation around Y")
  end

  # Test mirror transformations
  def test_mirrors
    puts "\n=== Testing Mirror Transformations ==="

    # Mirror in X (scale -1 in X)
    transform = Geom::Transformation.scaling(-1, 1, 1)
    test_transform(transform, "Mirror in X")

    # Mirror in Y (scale -1 in Y)
    transform = Geom::Transformation.scaling(1, -1, 1)
    test_transform(transform, "Mirror in Y")

    # Mirror in Z (scale -1 in Z)
    transform = Geom::Transformation.scaling(1, 1, -1)
    test_transform(transform, "Mirror in Z")

    # Mirror in XY (scale -1 in both X and Y)
    transform = Geom::Transformation.scaling(-1, -1, 1)
    test_transform(transform, "Mirror in XY")

    # Mirror in all axes (scale -1 in X, Y, Z)
    transform = Geom::Transformation.scaling(-1, -1, -1)
    test_transform(transform, "Mirror in XYZ")
  end

  # Test combined transformations
  def test_combined
    puts "\n=== Testing Combined Transformations ==="

    # Rotate 90° around Z then mirror in X
    t1 = Geom::Transformation.rotation([0,0,0], [0,0,1], Math::PI/2)
    t2 = Geom::Transformation.scaling(-1, 1, 1)
    transform = t1 * t2
    test_transform(transform, "Rotate 90° Z then Mirror X")

    # Mirror in X then rotate 90° around Z
    t1 = Geom::Transformation.scaling(-1, 1, 1)
    t2 = Geom::Transformation.rotation([0,0,0], [0,0,1], Math::PI/2)
    transform = t2 * t1
    test_transform(transform, "Mirror X then Rotate 90° Z")

    # Your customer's actual transformation
    a = [2.2261025051009175e-06, -0.999999999943474, -1.0396961699137863e-05, 0.0,
         -5.334917073946185e-06, -1.0396973575087929e-05, 0.9999999999317208, 0.0,
         -0.9999999999832917, -2.2260470380204348e-06, -5.334940218373544e-06, 0.0,
         51.20655476413128, 119.46501348661076, 19.882351491069027, 1.0]
    transform = Geom::Transformation.new(a)
    test_transform(transform, "Customer's F150 transformation")
  end

  def test_transform(transform, description)
    puts "\n#{description}:"

    # Calculate determinant
    det = determinant_3x3(transform)
    is_mirrored = det < 0

    # Transform face normal (assuming face points up initially)
    original_normal = Geom::Vector3d.new(0, 0, 1)
    world_normal = CloudCut::Exporter::GeometryExtractor.transform_direction(original_normal, transform)

    # Get projection axes
    u_axis, v_axis = CloudCut::Exporter::GeometryExtractor.build_axes_from_normal(world_normal)

    # Test points: corner of L-shape
    test_points = [
      Geom::Point3d.new(0, 0, 0),    # Origin
      Geom::Point3d.new(10, 0, 0),   # Right
      Geom::Point3d.new(0, 10, 0),   # Up
      Geom::Point3d.new(10, 10, 0)   # Diagonal
    ]

    puts "  Determinant: #{det.round(6)} (mirrored: #{is_mirrored})"
    puts "  World normal: [#{world_normal.x.round(3)}, #{world_normal.y.round(3)}, #{world_normal.z.round(3)}]"
    puts "  U-axis: [#{u_axis.x.round(3)}, #{u_axis.y.round(3)}, #{u_axis.z.round(3)}]"
    puts "  V-axis: [#{v_axis.x.round(3)}, #{v_axis.y.round(3)}, #{v_axis.z.round(3)}]"

    # Project test points and show results
    puts "  Projected points:"
    test_points.each_with_index do |pt, i|
      world_pt = transform * pt
      origin = Geom::Point3d.new(0, 0, 0)
      projected = CloudCut::Exporter::GeometryExtractor.project_point(world_pt, origin, u_axis, v_axis)
      labels = ["Origin", "Right(+X)", "Up(+Y)", "Diagonal"]
      puts "    #{labels[i]}: [#{projected[0].round(2)}, #{projected[1].round(2)}]"
    end

    # Check if projection preserves handedness
    # In original: (10,0) × (0,10) = positive (right-handed)
    # After projection: check if still right-handed
    world_right = transform * Geom::Point3d.new(10, 0, 0)
    world_up = transform * Geom::Point3d.new(0, 10, 0)
    origin_world = transform * Geom::Point3d.new(0, 0, 0)

    proj_right = CloudCut::Exporter::GeometryExtractor.project_point(world_right, origin_world, u_axis, v_axis)
    proj_up = CloudCut::Exporter::GeometryExtractor.project_point(world_up, origin_world, u_axis, v_axis)

    # 2D cross product to check handedness
    cross_2d = proj_right[0] * proj_up[1] - proj_right[1] * proj_up[0]
    puts "  2D handedness: #{cross_2d > 0 ? 'right-handed' : 'left-handed'} (cross: #{cross_2d.round(2)})"
    puts "  Expected: #{is_mirrored ? 'left-handed' : 'right-handed'}"
    puts "  CORRECT: #{(cross_2d > 0) == !is_mirrored ? 'YES' : 'NO !!!'}"
  end

  def determinant_3x3(transform)
    a = transform.to_a
    a[0] * (a[5] * a[10] - a[6] * a[9]) -
    a[4] * (a[1] * a[10] - a[2] * a[9]) +
    a[8] * (a[1] * a[6] - a[2] * a[5])
  end

  def run_all_tests
    puts "=" * 60
    puts "MIRRORING BEHAVIOR TEST SUITE"
    puts "=" * 60

    test_identity
    test_rotations
    test_mirrors
    test_combined

    puts "\n" + "=" * 60
    puts "TEST COMPLETE"
    puts "=" * 60
  end
end

# Run the tests
MirrorTest.run_all_tests