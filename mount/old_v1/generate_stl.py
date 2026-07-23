import trimesh, numpy as np
from trimesh.creation import box, cylinder

# ---- PARAMETERS (mm) -- MEASURE YOUR PARTS AND EDIT, then re-run ----
shaft_d   = 15.0   # bare shaft diameter at clamp point (just below grip)
shaft_gap = 0.4    # channel clearance over the shaft
bundle_l  = 34.0   # taped bundle length  (runs ALONG the shaft, +Z = toward clubhead)
bundle_w  = 27.0   # taped bundle width
bundle_h  = 14.0   # taped bundle depth (pocket depth)
wall      = 2.5    # pocket wall thickness
web       = 2.5    # material between shaft channel apex and pocket floor
wing      = 7.0    # zip-tie wing width on each side of the pocket
usb_w, usb_h = 12.0, 6.0   # micro-USB access cutout (w x h)
tie_w     = 4.0    # zip-tie slot width

r_ch = (shaft_d + shaft_gap) / 2.0
# derived block dims: X=width, Y=height(thickness), Z=length(along shaft)
W = bundle_w + 2*wall + 2*wing
pocket_floor = r_ch + web
T = pocket_floor + bundle_h
L = bundle_l + 2*wall
cx = W/2.0

def B(sx,sy,sz,cx_,cy_,cz_):
    m = box(extents=(sx,sy,sz)); m.apply_translation((cx_,cy_,cz_)); return m

block = B(W,T,L, W/2, T/2, L/2)

# shaft channel: cylinder axis along Z, at bottom-center -> semicircular groove
chan = cylinder(radius=r_ch, height=L+4); chan.apply_translation((cx,0,L/2))

# electronics pocket: open-top box
pk_h = (T - pocket_floor) + 4
pocket = B(bundle_w, pk_h, bundle_l, cx, pocket_floor + pk_h/2, L/2)

# micro-USB cutout through one end wall, at pocket-floor level
usb = B(usb_w, usb_h, wall+4, cx, pocket_floor + usb_h/2, wall/2)

# 4 vertical zip-tie slots through the two wings (2 ties)
wing_cx = [wall/2 + wing/2 + 0.0, W - (wall/2 + wing/2)]  # approx wing centers
wing_cx = [wing/2, W - wing/2]
ties=[]
for z in (bundle_l*0.20 + wall, bundle_l*0.80 + wall):
    for wx in wing_cx:
        ties.append(B(tie_w, T+4, tie_w, wx, T/2, z))

cuts = [chan, pocket, usb] + ties
part = trimesh.boolean.difference([block]+cuts, engine='manifold')

part.export('/sessions/bold-sleepy-maxwell/mnt/GolfSwingTrackerApp/mount/shaft_clip.stl')
print("W x T x L (mm):", round(W,1), round(T,1), round(L,1))
print("channel radius:", round(r_ch,2), "pocket floor y:", round(pocket_floor,2))
print("watertight:", part.is_watertight, "| volume(cm^3):", round(part.volume/1000,2),
      "| triangles:", len(part.faces))
