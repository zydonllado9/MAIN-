"""Builds the slingshot model in Blender and exports it for Roblox.

Run inside Blender (Scripting tab -> Open -> Run Script), or headless:
    blender --background --python build_slingshot.py -- <output folder>

1 Blender unit = 1 Roblox stud. The slingshot shoots toward Blender +Y,
which becomes Roblox's forward (-Z) after FBX export. Object names matter:
the Roblox setup script looks for TipLeft, TipRight and the other part names.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

# Output folder: first argument after "--", otherwise next to this file.
args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
if args:
    OUT = os.path.abspath(args[0])
elif bpy.data.filepath:
    OUT = os.path.dirname(bpy.data.filepath)
else:
    OUT = os.path.dirname(os.path.abspath(__file__))
RENDER_PREVIEW = "--no-render" not in args

# Shape (studs)
BASE_RADIUS = 2.0
BASE_HEIGHT = 0.8
STEM_TOP = 4.9
STEM_RADIUS_BOTTOM = 0.62
STEM_RADIUS_TOP = 0.5
FORK_SPREAD = 2.2  # tip distance from the centre line
FORK_TOP = 8.4
ARM_RADIUS = 0.42
TIP_RING_Z = 7.75  # where the bands tie on


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, roughness=0.6, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = (*color, 1.0)
    return mat


def srgb(r, g, b):
    """0-255 sRGB to Blender's linear colour."""

    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (lin(r), lin(g), lin(b))


MATS = {}


def make_materials():
    MATS["Stone"] = material("Stone", srgb(128, 128, 136), 0.9)
    MATS["Wood"] = material("Wood", srgb(140, 90, 52), 0.7)
    MATS["Leather"] = material("Leather", srgb(120, 34, 28), 0.55)
    MATS["Gold"] = material("Gold", srgb(255, 190, 60), 0.3, 1.0)
    MATS["Rope"] = material("Rope", srgb(214, 186, 130), 0.9)
    MATS["Rock"] = material("Rock", srgb(100, 102, 108), 0.95)


def finish(obj, name, mat, smooth=True, bevel=0.0):
    obj.name = name
    obj.data.name = name
    obj.data.materials.clear()
    obj.data.materials.append(MATS[mat])
    bpy.context.view_layer.objects.active = obj
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if smooth:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    return obj


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def join(objs, name, mat):
    select_only(objs)
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    return finish(bpy.context.view_layer.objects.active, name, mat)


def curve_object(name, points, radius, radii=None, closed=False, kind="BEZIER", resolution=10):
    """Round tube along points. Bezier uses auto handles; radii taper it."""
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.bevel_depth = radius
    data.bevel_resolution = 4
    data.use_fill_caps = True
    data.resolution_u = resolution
    spline = data.splines.new(kind)
    if kind == "BEZIER":
        spline.bezier_points.add(len(points) - 1)
        for i, p in enumerate(points):
            bp = spline.bezier_points[i]
            bp.co = p
            bp.handle_left_type = bp.handle_right_type = "AUTO"
            bp.radius = radii[i] if radii else 1.0
    else:
        spline.points.add(len(points) - 1)
        for i, p in enumerate(points):
            spline.points[i].co = (*p, 1.0)
            spline.points[i].radius = radii[i] if radii else 1.0
    spline.use_cyclic_u = closed
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def build_base():
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=BASE_RADIUS, depth=BASE_HEIGHT, location=(0, 0, BASE_HEIGHT / 2))
    base = bpy.context.active_object
    finish(base, "Base", "Stone", bevel=0.14)

    # A few rocks around the base.
    rocks = []
    for i, (angle, size) in enumerate([(35, 0.55), (150, 0.42), (250, 0.5), (300, 0.34)]):
        a = math.radians(angle)
        r = BASE_RADIUS + 0.15
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=size, location=(math.cos(a) * r, math.sin(a) * r, size * 0.45))
        rock = bpy.context.active_object
        rock.scale = (1.25, 0.95, 0.7)
        rock.rotation_euler = (0.3 * i, 0.5, a)
        rocks.append(rock)
    select_only(rocks)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    join(rocks, "Rocks", "Rock")
    bpy.ops.object.shade_flat()


def build_stem():
    bpy.ops.mesh.primitive_cone_add(
        vertices=16,
        radius1=STEM_RADIUS_BOTTOM,
        radius2=STEM_RADIUS_TOP,
        depth=STEM_TOP - BASE_HEIGHT + 0.1,
        location=(0, 0, (STEM_TOP + BASE_HEIGHT - 0.1) / 2),
    )
    finish(bpy.context.active_object, "Stem", "Wood", bevel=0.08)

    # Leather grip: a spiral wrap around the middle of the stem.
    turns, z0, z1 = 6, 1.9, 3.9
    steps = turns * 16
    pts = []
    for i in range(steps + 1):
        t = i / steps
        z = z0 + (z1 - z0) * t
        r = STEM_RADIUS_BOTTOM + (STEM_RADIUS_TOP - STEM_RADIUS_BOTTOM) * ((z - BASE_HEIGHT) / (STEM_TOP - BASE_HEIGHT)) + 0.02
        a = t * turns * math.tau
        pts.append((math.cos(a) * r, math.sin(a) * r, z))
    grip = curve_object("Grip", pts, 0.12, kind="POLY")
    grip.data.bevel_resolution = 2
    join([grip], "Grip", "Leather")


def arm_points(side):
    s = side
    return [
        (0, 0, STEM_TOP - 0.45),
        (s * 0.55, 0, STEM_TOP + 0.55),
        (s * 1.65, 0, STEM_TOP + 1.45),
        (s * FORK_SPREAD, 0, STEM_TOP + 2.45),
        (s * FORK_SPREAD, 0, FORK_TOP),
    ]


def build_fork():
    arms = []
    for side in (-1, 1):
        arm = curve_object("Arm", arm_points(side), ARM_RADIUS, radii=[1.18, 1.05, 0.98, 0.94, 0.9], resolution=12)
        arms.append(arm)
        # Rounded knob on top of each arm.
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=ARM_RADIUS * 1.05, location=(side * FORK_SPREAD, 0, FORK_TOP))
        knob = bpy.context.active_object
        knob.scale = (1, 1, 0.75)
        arms.append(knob)
    join(arms, "Fork", "Wood")

    # Rope binding where the arms split from the stem.
    rings = []
    for i in range(3):
        bpy.ops.mesh.primitive_torus_add(major_radius=STEM_RADIUS_TOP + 0.05, minor_radius=0.1, major_segments=20, minor_segments=8, location=(0, 0, STEM_TOP - 0.55 + i * 0.2))
        rings.append(bpy.context.active_object)
    join(rings, "Binding", "Rope")

    # Gold rings where the bands tie on. These become the band attachment points.
    for side, name in ((-1, "TipLeft"), (1, "TipRight")):
        # Viewed from behind (looking where it shoots, +Y), right is +X.
        bpy.ops.mesh.primitive_torus_add(major_radius=ARM_RADIUS * 0.95, minor_radius=0.13, major_segments=20, minor_segments=8, location=(side * FORK_SPREAD, 0, TIP_RING_Z))
        finish(bpy.context.active_object, name, "Gold")


def slingshot_objects():
    names = ["Base", "Rocks", "Stem", "Grip", "Fork", "Binding", "TipLeft", "TipRight"]
    return [bpy.data.objects[n] for n in names]


def triangle_count(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def export(objs):
    os.makedirs(OUT, exist_ok=True)
    select_only(objs)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT, "Slingshot.fbx"),
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_anim=False,
    )
    bpy.ops.wm.obj_export(
        filepath=os.path.join(OUT, "Slingshot.obj"),
        export_selected_objects=True,
        forward_axis="NEGATIVE_Z",
        up_axis="Y",
        export_materials=True,
    )


def render_preview():
    """Preview picture only: the ground, lights and bands are not exported."""
    scene = bpy.context.scene
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "PreviewGround"
    ground.data.materials.append(material("Grass", srgb(96, 168, 82), 0.95))

    # Two rubber bands and a pouch, roughly where the game draws them.
    band_mat = material("Band", srgb(70, 40, 25), 0.6)
    pouch_y = -2.8
    for side in (-1, 1):
        band = curve_object("PreviewBand", [(side * FORK_SPREAD, 0, TIP_RING_Z), (side * 0.45, pouch_y, TIP_RING_Z - 0.35)], 0.09, kind="POLY")
        band.data.materials.append(band_mat)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.55, location=(0, pouch_y - 0.15, TIP_RING_Z - 0.35))
    ball = bpy.context.active_object
    ball.data.materials.append(material("Ammo", srgb(232, 62, 52), 0.4))
    bpy.ops.object.shade_smooth()

    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (*srgb(150, 200, 255), 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world

    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    scene.collection.objects.link(sun)

    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    cam.location = (9.5, -13.5, 7.5)
    direction = Vector((0, 0, 4.4)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.view_settings.view_transform = "AgX"
    scene.render.filepath = os.path.join(OUT, "preview.png")
    bpy.ops.render.render(write_still=True)

    for obj in [o for o in bpy.data.objects if o.name.startswith(("Preview", "Sun", "Camera", "Sphere"))]:
        bpy.data.objects.remove(obj, do_unlink=True)


def main():
    reset_scene()
    make_materials()
    build_base()
    build_stem()
    build_fork()
    objs = slingshot_objects()
    for o in objs:
        print(f"{o.name:9s} {triangle_count(o):6d} triangles")
    print(f"total     {sum(triangle_count(o) for o in objs):6d} triangles")
    export(objs)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Slingshot.blend"))
    if RENDER_PREVIEW:
        render_preview()
    print("Saved to", OUT)


main()
