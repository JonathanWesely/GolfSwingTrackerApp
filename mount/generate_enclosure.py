import trimesh, numpy as np, math
from trimesh.creation import box, cylinder, cone, revolve
U=lambda p: trimesh.boolean.union(p, engine='manifold')
D=lambda a,b: trimesh.boolean.difference([a]+b, engine='manifold')
def Bx(sx,sy,sz,c): m=box(extents=(sx,sy,sz)); m.apply_translation(c); return m
def Cz(r,h,c):      m=cylinder(radius=r,height=h); m.apply_translation(c); return m
def Cx(r,h,c):      m=cylinder(radius=r,height=h); m.apply_transform(trimesh.transformations.rotation_matrix(np.pi/2,[0,1,0])); m.apply_translation(c); return m
def Cy(r,h,c,sec=48):
    m=cylinder(radius=r,height=h,sections=sec); m.apply_transform(trimesh.transformations.rotation_matrix(np.pi/2,[1,0,0])); m.apply_translation(c); return m
def Hy(r,h,c): return Cy(r,h,c,sec=6)   # hex pocket, axis Y
def csk_hole(sx,sz):   # one revolved tool = M3 clearance hole + flush 90-deg countersink (assumes lid_t=3)
    r=lid_clear_d/2; prof=np.array([[0,0],[r,0],[r,2.7],[3.3,4.5],[3.3,6.0],[0,6.0]])
    m=revolve(prof, sections=48); m.apply_transform(trimesh.transformations.rotation_matrix(-np.pi/2,[1,0,0])); m.apply_translation((sx,-1.5,sz)); return m

# ===== PARAMETERS (mm) =====
bx,by,bz=27.0,24.0,30.0; clr=0.6; wall=3.0; web=3.0   # bundle 27(X) x 24(Y) x 30(Z); USB face = +X wall (24x30)
flange_w=7.0; flange_t=4.0; lid_t=3.0; gasket_gap=0.6; reg_t=3.0; boss_h=8.0
shaft_circ_min=44.0; shaft_circ_max=49.0; liner=1.5; shaft_clear=0.35   # clamps 44-49mm circ
shaft_d=shaft_circ_min/math.pi
bore_r=(shaft_circ_max/math.pi)/2 + shaft_clear   # fits the LARGEST; liner grips down to the smallest
core_wall=4.0; half_w=bore_r+core_wall; lower_wall=6.0; usb_d=11.0
lid_pilot_d=2.5; lid_clear_d=3.4
knob_dia=20.0; ear_h=5.0; stud_clear=4.6; nut_r=4.25; nut_h=3.6
stud_x=half_w+knob_dia/2+1.0; ear_out=stud_x+6.5   # wide enough that the M4 nut pocket keeps ~2mm wall
stud_zs=[-11.0,11.0]; ear_z_len=36.0   # near-full side rail so the nut pockets stay fully walled in Z        # 2 knobs/side, near both ends -> no splay

cav=(bx+clr,by+clr,bz+clr); box_x=cav[0]+2*wall; box_z=cav[2]+2*wall
cav_floor=bore_r+web; box_top=cav_floor+cav[1]
flange_x=box_x+2*flange_w; flange_z=box_z+2*flange_w
cxh=flange_x/2-4; czh=flange_z/2-4; BIG=300.0

# ---- BODY ----
parts=[Bx(box_x,box_top,box_z,(0,box_top/2,0)),
       Bx(flange_x,flange_t,flange_z,(0,box_top+flange_t/2,0)),
       Bx(2*half_w,box_top,box_z,(0,box_top/2,0)),
       Bx(2*half_w,box_top,reg_t,(0,box_top/2,box_z/2+reg_t/2))]        # register at +Z FACE
for sgn in (-1,1):
    parts.append(Bx(ear_out-half_w+2,ear_h,ear_z_len,(sgn*(half_w+(ear_out-half_w)/2-1),ear_h/2,0)))
for sx in (-cxh,cxh):
    for sz in (-czh,czh): parts.append(Cy(4.0,boss_h,(sx,box_top-boss_h/2,sz)))
body=U(parts)
cuts=[Cz(bore_r,box_z+reg_t+8,(0,0,0)), Bx(BIG,BIG,BIG,(0,-BIG/2,0)),
      Bx(cav[0],cav[1]+flange_t+6,cav[2],(0,cav_floor+(cav[1]+flange_t+6)/2,0)),
      Bx(cav[0]+6,gasket_gap,cav[2]+6,(0,box_top+flange_t-gasket_gap/2,0)),
      Cx(usb_d/2,wall+6,(box_x/2, cav_floor+5, -(cav[2]/2-7)))]
for sx in (-cxh,cxh):
    for sz in (-czh,czh):
        cuts.append(Cy(lid_pilot_d/2,flange_t+boss_h+2,(sx,box_top+(flange_t-boss_h)/2,sz)))
for sgn in (-1,1):
    for sz in stud_zs:
        x=sgn*stud_x
        cuts.append(Cy(stud_clear/2,ear_h+4,(x,ear_h/2,sz)))
        cuts.append(Hy(nut_r,nut_h,(x,ear_h-nut_h/2,sz)))
body=D(body,cuts)

# ---- LID ----
lid=U([Bx(flange_x,lid_t,flange_z,(0,lid_t/2,0)),
       Bx(cav[0]-0.4,gasket_gap+1.0,cav[2]-0.4,(0,-(gasket_gap+1.0)/2,0))])
lid=D(lid,[csk_hole(sx,sz) for sx in (-cxh,cxh) for sz in (-czh,czh)])

# ---- CLAMP ----
cp=[Bx(2*half_w,bore_r+lower_wall,box_z,(0,-(bore_r+lower_wall)/2,0))]
for sgn in (-1,1):
    cp.append(Bx(ear_out-half_w+2,ear_h,ear_z_len,(sgn*(half_w+(ear_out-half_w)/2-1),-ear_h/2,0)))
clamp=U(cp)
cc=[Cz(bore_r,box_z+6,(0,0,0)),Bx(BIG,BIG,BIG,(0,BIG/2,0))]
for sgn in (-1,1):
    for sz in stud_zs:
        x=sgn*stud_x
        cc.append(Cy(stud_clear/2,ear_h+4,(x,-ear_h/2,sz)))
        cc.append(Cy(knob_dia/2+0.5,1.2,(x,-ear_h+0.6,sz)))
clamp=D(clamp,cc)

for nm,m in [('body',body),('lid',lid),('clamp',clamp)]:
    m.export(f'{nm}.stl')
    print(f"{nm}: watertight={m.is_watertight} vol={m.volume/1000:.1f}cm3 Zrange={m.bounds[0,2]:.1f}..{m.bounds[1,2]:.1f}")
print(f"knobs: 4 (2/side at z={stud_zs}); width={2*ear_out:.0f}")
