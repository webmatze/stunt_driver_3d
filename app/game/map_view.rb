# Top-down drawings of track geometry (editor map, palette icons, minimap):
# the same triangles the 3D view uses, seen from straight above.
module MapView
  WHITE = 'sprites/d3d/white.png'

  # Triangle sprites of a list of ground Geos and sorted Geos, scaled by
  # `scale` pixels per metre, with world x/z = 0 at screen ox/oy.
  def self.prims(ground_geos, geos, scale, ox = 0.0, oy = 0.0)
    out = []
    ground_geos.each { |g| add(out, g, scale, ox, oy, false) }
    high = []
    geos.each { |g| add(high, g, scale, ox, oy, true) }
    high.sort_by { |e| e[0] }.each { |e| out << e[1] }
    out
  end

  def self.add(list, geo, scale, ox, oy, keyed)
    geo.each_tri do |ax, ay, az, bx, by, bz, cx, cy, cz, r, g, b|
      x0 = ox + ax * scale
      y0 = oy + az * scale
      x1 = ox + bx * scale
      y1 = oy + bz * scale
      x2 = ox + cx * scale
      y2 = oy + cz * scale
      # walls seen from above have no area
      next if ((x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)).abs < 0.05

      prim = { x: x0, y: y0, x2: x1, y2: y1, x3: x2, y3: y2,
               source_x: 0, source_y: 0, source_x2: 8, source_y2: 0, source_x3: 0, source_y3: 8,
               path: WHITE, r: r, g: g, b: b }
      list << (keyed ? [ay + by + cy, prim] : prim)
    end
  end

  # Renders a whole world into the render target `name` (size x size px).
  def self.render_world(args, name, world, size, bg, route_color = nil)
    rt = args.outputs[name]
    rt.w = size
    rt.h = size
    rt.background_color = bg
    scale = size / (Track::SIZE * World::T)
    rt.sprites << prims(world.ground_geos, world.geos, scale)
    return unless route_color && world.ok?

    path = world.path
    n = path.size
    n.times do |i|
      a = path[i]
      b = path[(i + 1) % n]
      rt.lines << { x: a[0] * scale, y: a[2] * scale, x2: b[0] * scale, y2: b[2] * scale,
                    r: route_color[0], g: route_color[1], b: route_color[2], a: 220 }
    end
  end

  # Small overview map: just the route as a broad line plus the start line.
  def self.render_minimap(args, name, world, size, bg)
    rt = args.outputs[name]
    rt.w = size
    rt.h = size
    rt.background_color = bg
    return unless world.ok?

    scale = size / (Track::SIZE * World::T)
    path = world.path
    n = path.size
    w = 2.0
    n.times do |i|
      a = path[i]
      b = path[(i + 1) % n]
      dx = (b[0] - a[0]) * scale
      dy = (b[2] - a[2]) * scale
      l = Math.sqrt(dx * dx + dy * dy)
      next if l < 1e-6

      ux = dx / l * w
      uy = dy / l * w
      x0 = a[0] * scale - ux
      y0 = a[2] * scale - uy
      x1 = b[0] * scale + ux
      y1 = b[2] * scale + uy
      [[x0 + uy, y0 - ux, x1 + uy, y1 - ux, x1 - uy, y1 + ux],
       [x0 + uy, y0 - ux, x1 - uy, y1 + ux, x0 - uy, y0 + ux]].each do |t|
        rt.sprites << { x: t[0], y: t[1], x2: t[2], y2: t[3], x3: t[4], y3: t[5],
                        source_x: 0, source_y: 0, source_x2: 8, source_y2: 0, source_x3: 0, source_y3: 8,
                        path: WHITE, r: 228, g: 228, b: 232 }
      end
    end
    c = world.start_center
    rt.sprites << { x: c[0] * scale - 4, y: c[2] * scale - 4, w: 8, h: 8, path: :solid, r: 232, g: 60, b: 50 }
  end
end
