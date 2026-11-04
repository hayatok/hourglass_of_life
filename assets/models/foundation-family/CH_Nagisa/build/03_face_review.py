"""Actual Blender face/hair draft review; only run in the heavy-process slot.

Fixed front/profile windows reuse the original sheet's world registration.
The build is intentionally not accepted by this script: inspect its images.
"""
from pathlib import Path
import sys
import math
import json
import bpy
import bmesh
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"review/03_face_hair"
SKILL=Path("/Users/hayatok/.codex/skills/blender-image-to-3d/scripts")
sys.path.insert(0,str(SKILL))
import review_render as R


def coloured_studio(scene,centre,extent):
    """Neutral soft studio for judging warm authored albedo, not dark clay.

    This is review-only lighting. No directional light is baked into an asset.
    """
    if not any(ob.type=="LIGHT" and ob.name.startswith("_review_") for ob in scene.objects):
        R.add_light_rig(scene,centre,extent)
    for ob in scene.objects:
        if ob.type=="LIGHT":
            ob.hide_render=not ob.name.startswith("_review_")
            if not ob.hide_render:
                if ob.name.startswith("_review_key"):
                    ob.data.energy=.85
                elif ob.name.startswith("_review_fill"):
                    ob.data.energy=.35
                else:
                    ob.data.energy=.55
                ob.data.color=(1,1,1);ob.data.angle=math.radians(30)
    R.ensure_world(scene,.65,(.7,.7,.7))
    scene.view_settings.view_transform="Standard"
    scene.view_settings.exposure=-.25;scene.view_settings.gamma=1


def registered_camera(scene,view):
    if view=="front":
        crop=(235,0,408,185);axis=318;az=0
    else:
        crop=(650,0,835,185);axis=746;az=270
    width,height=crop[2]-crop[0],crop[3]-crop[1]
    scale=1.65/975
    right=Vector((math.cos(math.radians(az)),math.sin(math.radians(az)),0))
    back=Vector((math.sin(math.radians(az)),-math.cos(math.radians(az)),0))
    cam=scene.camera
    cam.data.type="ORTHO";cam.data.sensor_fit="HORIZONTAL"
    cam.data.ortho_scale=width*scale
    cam.location=right*((crop[0]+width/2-axis)*scale)+Vector((0,0,(989-height/2)*scale))+back*3
    cam.rotation_mode="QUATERNION"
    cam.rotation_quaternion=(-back).to_track_quat("-Z","Y")
    scene.render.resolution_x=width*3;scene.render.resolution_y=height*3
    return {"source_crop":list(crop),"m_per_source_px":scale,"source_ground_row":989,
            "source_axis_x":axis,"azimuth":az,"resolution_scale":3}


def main():
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/"CH_Nagisa_master.blend"))
    OUT.mkdir(parents=True,exist_ok=True)
    scene=bpy.context.scene
    full_scope=[ob for ob in bpy.data.collections["LOW"].all_objects if ob.type=="MESH" and not ob.hide_render]
    scope=[ob for ob in bpy.data.objects if ob.type=="MESH" and not ob.hide_render and ob.get("owner")=="phase:03_forms_face_hair"]
    if not scope:
        raise RuntimeError("Build the face/hair draft before reviewing it")
    R.apply_visibility(scene,scope)
    cam=bpy.data.objects.new("_face_review_cam",bpy.data.cameras.new("_face_review_cam"))
    scene.collection.objects.link(cam);scene.camera=cam
    cam.data.clip_start=.01;cam.data.clip_end=100
    corners,lo,hi=R.world_corners(scope)
    centre=(lo+hi)/2;extent=max(hi-lo)
    from types import SimpleNamespace
    args=SimpleNamespace(mode="clay",samples=24)
    report={"status":"rendered_draft_not_accepted", "reference":"ref/face-landmarks.json",
            "images":{},"geometry":{},"pending":["Human visual comparison of every face view", "full body silhouette preservation", "clothes/hands forms", "rig/weight/export evidence"]}
    for mode,engine in [("clay","workbench"),("material","cycles")]:
        args.mode=mode
        R.setup_engine(scene,args,engine,scope,centre,extent)
        if mode=="material":
            coloured_studio(scene,centre,extent)
        for view in ["front","side"]:
            registration=registered_camera(scene,view)
            file=OUT/(mode+"_"+view+".png")
            R.render_to(scene,str(file))
            report["images"][file.name]=registration
        scene.render.resolution_x=512;scene.render.resolution_y=512
        R.fit_camera(cam,corners,centre,R.view_direction(35,8),512,512,55,1.10)
        file=OUT/(mode+"_threequarter.png")
        R.render_to(scene,str(file))
        report["images"][file.name]={"azimuth":35,"elevation":8,"lens_mm":55,"fit":"face_hair_actual_bounds"}
    # Examine real openings and quad flow, without changing the saved master.
    args.mode="wire"
    R.setup_engine(scene,args,"workbench",scope,centre,extent)
    registered_camera(scene,"front")
    R.render_to(scene,str(OUT/"wire_front.png"))
    for ob in scope:
        for modifier in list(ob.modifiers):
            if modifier.name=="_review_wire":
                ob.modifiers.remove(modifier)
    head=next(ob for ob in scope if "SkinHeadNeck" in ob.name)
    report["neutral_key_values"]={key.name:key.value for key in head.data.shape_keys.key_blocks}
    blink_parts=[ob for ob in scope if ob.data.shape_keys and "Blink" in ob.data.shape_keys.key_blocks]
    for ob in blink_parts:
        ob.data.shape_keys.key_blocks["Blink"].value=1
    bpy.context.view_layer.update()
    args.mode="material"
    R.setup_engine(scene,args,"cycles",scope,centre,extent)
    coloured_studio(scene,centre,extent)
    registered_camera(scene,"front")
    R.render_to(scene,str(OUT/"material_blink_front.png"))
    for ob in blink_parts:
        ob.data.shape_keys.key_blocks["Blink"].value=0
    report["blink_mesh_group"]=[ob.name for ob in blink_parts]
    for ob in scope:
        bm=bmesh.new();bm.from_mesh(ob.data)
        report["geometry"][ob.name]={
            "vertices":len(bm.verts),"faces":len(bm.faces),
            "triangles":sum(len(face.verts)-2 for face in bm.faces),
            "boundary_edges":sum(edge.is_boundary for edge in bm.edges),
            "wire_edges":sum(edge.is_wire for edge in bm.edges),
            "area_below_1e-10":sum(face.calc_area()<1e-10 for face in bm.faces),
            "shape_keys":list(ob.data.shape_keys.key_blocks.keys()) if ob.data.shape_keys else [],
        }
        bm.free()
    # Normal coloured whole-body evidence is the style review baseline. Clay
    # silhouette strips remain useful for shape, not for accepting this style.
    R.apply_visibility(scene,full_scope)
    full_corners,full_lo,full_hi=R.world_corners(full_scope)
    full_centre=(full_lo+full_hi)/2;full_extent=max(full_hi-full_lo)
    R.setup_engine(scene,args,"cycles",full_scope,full_centre,full_extent)
    coloured_studio(scene,full_centre,full_extent)
    scene.render.resolution_x=512;scene.render.resolution_y=768
    R.fit_camera(cam,full_corners,full_centre,R.view_direction(0,0),512,768,0,1.15)
    R.render_to(scene,str(OUT/"material_fullbody_front.png"))
    R.fit_camera(cam,full_corners,full_centre,R.view_direction(35,15),512,768,50,1.15)
    R.render_to(scene,str(OUT/"material_fullbody_threequarter.png"))
    scene.render.resolution_x=768;scene.render.resolution_y=768
    for distance,label in [(8,"close_8m"),(19,"overview_19m")]:
        direction=R.view_direction(30,50)
        cam.data.type="PERSP";cam.data.lens=43;cam.data.sensor_fit="HORIZONTAL";cam.data.sensor_width=36
        cam.location=Vector((0,0,.825))+direction*distance
        cam.rotation_mode="QUATERNION";cam.rotation_quaternion=(-direction).to_track_quat("-Z","Y")
        file="material_game_"+label+".png"
        R.render_to(scene,str(OUT/file))
        report["images"][file]={"distance_m":distance,"azimuth":30,"elevation":50,"lens_mm":43,
                                 "resolution":[768,768],"method":"physical house camera distance; no bbox refit"}
    report["coloured_lighting"]={"key_sun":.85,"fill_sun":.35,"rim_sun":.55,"sun_soft_angle_degrees":30,
                                  "world_colour":[.7,.7,.7],"world_strength":.65,"view":"Standard","exposure":-.25,
                                  "scope":"review only; original authored albedo, no baked directional light"}
    (OUT/"review.json").write_text(json.dumps(report,indent=2)+"\n")
    print("FACE_HAIR_REVIEW rendered draft; visual acceptance is pending",OUT)


if __name__=="__main__":
    main()
