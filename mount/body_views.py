import trimesh, numpy as np, matplotlib
matplotlib.use('Agg'); import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
m=trimesh.load('body.stl'); v=m.vertices; f=m.faces
views=[(-55,20,'front 3/4 (cavity + flange, register at far +Z)'),
       (125,20,'BACK 3/4 (opposite side)'),
       (-90,-75,'bottom (shaft bore + 4 stud holes + knob pockets)'),
       (-90,80,'top (open cavity + gasket rim + lid-screw bosses)')]
fig=plt.figure(figsize=(14,11))
b=m.bounds
for i,(az,el,ttl) in enumerate(views):
    ax=fig.add_subplot(2,2,i+1,projection='3d')
    ax.add_collection3d(Poly3DCollection(v[f],alpha=1,facecolor='#5b8db8',edgecolor='#22384a',linewidth=0.15))
    ax.set_xlim(b[0,0],b[1,0]); ax.set_ylim(b[0,1],b[1,1]); ax.set_zlim(b[0,2],b[1,2])
    ax.set_box_aspect(b[1]-b[0]); ax.view_init(elev=el,azim=az); ax.set_title(ttl,fontsize=10)
    ax.set_xlabel('X'); ax.set_ylabel('Y'); ax.set_zlabel('Z (shaft)')
plt.tight_layout(); plt.savefig('body_views.png',dpi=115); print('saved')
