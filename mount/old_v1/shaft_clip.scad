// GolfTracker — bare-shaft clip mount (parametric)
// Clamps to the bare metal shaft just below the grip. The electronics bundle
// sits in the open-top pocket; two zip ties through the wing slots wrap the
// shaft into the channel. Orient the bundle so the sensor +Z axis points DOWN
// the shaft toward the clubhead (the frame convention the firmware/app assume).
//
// >>> MEASURE your parts with calipers and edit the values below, then re-render.
// Render an STL:  openscad -o shaft_clip.stl shaft_clip.scad
// (or edit generate_stl.py and run it — same geometry, no OpenSCAD needed)

// ---- parameters (mm) ----
shaft_d   = 15.0;  // bare shaft diameter at the clamp point (just below grip)
shaft_gap = 0.4;   // channel clearance over the shaft (increase if too tight)
bundle_l  = 34.0;  // taped bundle length  (runs ALONG the shaft)
bundle_w  = 27.0;  // taped bundle width
bundle_h  = 14.0;  // taped bundle depth  (pocket depth)
wall      = 2.5;   // pocket wall thickness
web       = 2.5;   // material between channel apex and pocket floor
wing      = 7.0;   // zip-tie wing width each side
usb_w     = 12.0;  // micro-USB cutout width
usb_h     = 6.0;   // micro-USB cutout height
tie_w     = 4.0;   // zip-tie slot width
$fn       = 96;

// ---- derived ----
r_ch = (shaft_d + shaft_gap) / 2;
W    = bundle_w + 2*wall + 2*wing;   // X (width)
pf   = r_ch + web;                   // pocket floor height
T    = pf + bundle_h;                // Y (height)
L    = bundle_l + 2*wall;            // Z (along shaft)
cx   = W/2;

module shaft_clip() {
  difference() {
    cube([W, T, L]);

    // shaft channel (semicircular groove along Z at bottom-center)
    translate([cx, 0, -2]) cylinder(h = L+4, r = r_ch);

    // electronics pocket (open top)
    translate([cx - bundle_w/2, pf, L/2 - bundle_l/2])
      cube([bundle_w, T - pf + 4, bundle_l]);

    // micro-USB access cutout through one end wall
    translate([cx - usb_w/2, pf, -2]) cube([usb_w, usb_h, wall+4]);

    // zip-tie slots: 2 ties x 2 wings
    for (z = [bundle_l*0.2 + wall, bundle_l*0.8 + wall])
      for (wx = [wing/2, W - wing/2])
        translate([wx - tie_w/2, -2, z - tie_w/2]) cube([tie_w, T+4, tie_w]);
  }
}

shaft_clip();
