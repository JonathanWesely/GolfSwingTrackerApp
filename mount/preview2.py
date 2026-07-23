import trimesh, numpy as np, matplotlib
matplotlib.use('Agg'); import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
parts=[('body.stl',(0,0,0),'#5b8db8'),('clamp.stl',(0,-30,0),'#b8875b'),('lid.stl',(0,40,0),'#6bab6b')]
fig=plt.figure(figsize=(13,6))
for i,(az,el,ttl) in enumerate([(-60,20,'exploded 3/4 (body + lid above + clamp below)'),(-90,0,'end-on (shaft bore + bolt ears)')]):
    ax=fig.add_subplot(1,2,i+1,projection='3d'); allpts=[]
    for f,off,col in parts:
        m=trimesh.load(f); v=m.vertices+np.array(off)
        ax.add_collection3d(Poly3DCollection(v[m.faces],alpha=1,facecolor=col,edgecolor='#2a2a2a',linewidth=0.15))
        allpts.append(v)
    P=np.vstack(allpts); mn,mx=P.min(0),P.max(0)
    ax.set_xlim(mn[0],mx[0]); ax.set_ylim(mn[1],mx[1]); ax.set_zlim(mn[2],mx[2]); ax.set_box_aspect(mx-mn)
    ax.view_init(elev=el,azim=az); ax.set_title(ttl,fontsize=9); ax.set_xlabel('X'); ax.set_ylabel('Y'); ax.set_zlabel('Z shaft')
plt.tight_layout(); plt.savefig('preview.png',dpi=110); print('saved')
