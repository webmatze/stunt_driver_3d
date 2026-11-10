# Open-air rendering on top of D3D::SceneRenderer:
#   - static world geometry (Geo) in world space with near plane clipping,
#     baked sun light and haze towards the horizon
#   - a ground layer (flat roads, grass pattern) drawn first and unsorted
#   - a sky and ground backdrop that follows the camera through any roll
#   - correct order of the car against the world: a triangle whose plane has
#     the car on the camera's side can't hide the car and is drawn before
#     it, every other triangle after it.
# Meshes drawn with the engine's draw_mesh / draw_glow (car, debris) end up
# between those two groups.
class StuntRenderer < D3D::SceneRenderer
  WHITE = 'sprites/d3d/white.png'
  SKY_TOP = [58, 118, 208].freeze
  SKY_LOW = [180, 216, 240].freeze
  HAZE = [170, 206, 222].freeze
  GRASS = [98, 166, 76].freeze
  GRASS_DARK = [89, 155, 69].freeze
  SKY_STEPS = [0.0, 0.025, 0.06, 0.11, 0.18, 0.28, 0.42].freeze
  GROUND_STEPS = [[1.0, 0.8], [0.85, 0.47], [0.7, 0.25], [0.55, 0.11], [0.4, 0.0]].freeze
  SCREEN = [[0.0, 0.0], [1280.0, 0.0], [1280.0, 720.0], [0.0, 720.0]].freeze

  def initialize(**opts)
    super(**opts)
    @cx = []
    @cy = []
    @cz = []
    @sx = []
    @sy = []
    @ground = []
    @behind = []
    @front = []
    @checker = {}
    @kx = Math.sqrt(1 + @tan_x * @tan_x)
    @ky = Math.sqrt(1 + @tan_y * @tan_y)
  end

  # split: world position of the car (or nil when it isn't drawn).
  def begin_frame(pose, split = nil)
    super(pose)
    @ground = []
    @behind = []
    @front = []
    @shadow = nil
    @split = split
    self
  end

  # ------------------------------------------------------------ geometry

  # Draws a Geo. ground: into the unsorted ground layer.
  def draw_geo(geo, ground = false)
    c = geo.center
    rad = geo.radius
    px = @px
    py = @py
    pz = @pz
    dx = c[0] - px
    dy = c[1] - py
    dz = c[2] - pz
    fx = @fx
    fy = @fy
    fz = @fz
    oz = dx * fx + dy * fy + dz * fz
    return if oz < -rad

    d2 = dx * dx + dy * dy + dz * dz
    vd = @view_distance + rad
    return if d2 > vd * vd

    rx = @rx
    ry = @ry
    rz = @rz
    ox = dx * rx + dy * ry + dz * rz
    return if (ox < 0 ? -ox : ox) - oz * @tan_x > rad * @kx

    ux = @ux
    uy = @uy
    uz = @uz
    oy = dx * ux + dy * uy + dz * uz
    return if (oy < 0 ? -oy : oy) - oz * @tan_y > rad * @ky

    # haze towards the horizon, one factor per Geo
    h = Math.sqrt(d2) / @view_distance
    h = 1.0 if h > 1.0
    h = h * h * h
    keep = 1.0 - h
    hr = HAZE[0] * h
    hg = HAZE[1] * h
    hb = HAZE[2] * h

    near = @near
    focal = @focal
    hw = @half_w
    hh = @half_h
    vx = geo.vx
    vy = geo.vy
    vz = geo.vz
    cxs = @cx
    cys = @cy
    czs = @cz
    sxs = @sx
    sys = @sy
    n = vx.size
    i = 0
    while i < n
      x = vx[i] - px
      y = vy[i] - py
      z = vz[i] - pz
      zc = x * fx + y * fy + z * fz
      xc = x * rx + y * ry + z * rz
      yc = x * ux + y * uy + z * uz
      cxs[i] = xc
      cys[i] = yc
      czs[i] = zc
      if zc >= near
        k = focal / zc
        sxs[i] = hw + xc * k
        sys[i] = hh + yc * k
      end
      i += 1
    end

    ta = geo.ta
    tb = geo.tb
    tc = geo.tc
    tr = geo.tr
    tg = geo.tg
    tbl = geo.tbl
    tnx = geo.tnx
    tny = geo.tny
    tnz = geo.tnz
    tds = geo.tds
    split = @split
    if split
      spx = split[0]
      spy = split[1]
      spz = split[2]
    end
    width = @width
    height = @height
    ws = @white_size
    gl = @ground
    behind = @behind
    front = @front
    tn = ta.size
    ti = -1
    while (ti += 1) < tn
      a = ta[ti]
      nx = tnx[ti]
      ny = tny[ti]
      nz = tnz[ti]
      ax = vx[a]
      ay = vy[a]
      az = vz[a]
      d = (px - ax) * nx + (py - ay) * ny + (pz - az) * nz
      next if d <= 0 && !tds[ti]

      b = tb[ti]
      c = tc[ti]
      za = czs[a]
      zb = czs[b]
      zc = czs[c]
      next if za < near && zb < near && zc < near

      r = tr[ti] * keep + hr
      g = tg[ti] * keep + hg
      bl = tbl[ti] * keep + hb
      list = gl
      unless ground
        mx = cxs[a] + cxs[b] + cxs[c]
        my = cys[a] + cys[b] + cys[c]
        mz = za + zb + zc
        key = (mx * mx + my * my + mz * mz) * 0.111111
        list = if split && ((spx - ax) * nx + (spy - ay) * ny + (spz - az) * nz > 0) != (d > 0)
                 front
               else
                 behind
               end
      end

      if za < near || zb < near || zc < near
        clip_emit(list, key, [[cxs[a], cys[a], za], [cxs[b], cys[b], zb], [cxs[c], cys[c], zc]], r, g, bl)
        next
      end

      x0 = sxs[a]
      x1 = sxs[b]
      x2 = sxs[c]
      next if (x0 < 0 && x1 < 0 && x2 < 0) || (x0 > width && x1 > width && x2 > width)

      y0 = sys[a]
      y1 = sys[b]
      y2 = sys[c]
      next if (y0 < 0 && y1 < 0 && y2 < 0) || (y0 > height && y1 > height && y2 > height)

      prim = { x: x0, y: y0, x2: x1, y2: y1, x3: x2, y3: y2,
               source_x: 0, source_y: 0, source_x2: ws, source_y2: 0, source_x3: 0, source_y3: ws,
               path: WHITE, r: r, g: g, b: bl }
      if ground
        list << prim
      else
        list << [key, prim]
      end
    end
    self
  end

  # Clips a camera space triangle against the near plane and emits the rest.
  # key: sort key, or nil for the ground layer.
  def clip_emit(list, key, pts, r, g, b)
    near = @near
    poly = []
    3.times do |i|
      p = pts[i]
      q = pts[(i + 1) % 3]
      pin = p[2] >= near
      poly << p if pin
      next if pin == (q[2] >= near)

      t = (near - p[2]) / (q[2] - p[2])
      poly << [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t, near]
    end
    return if poly.size < 3

    scr = poly.map do |p|
      k = @focal / p[2]
      [@half_w + p[0] * k, @half_h + p[1] * k]
    end
    ws = @white_size
    p0 = scr[0]
    (1...scr.size - 1).each do |i|
      p1 = scr[i]
      p2 = scr[i + 1]
      prim = { x: p0[0], y: p0[1], x2: p1[0], y2: p1[1], x3: p2[0], y3: p2[1],
               source_x: 0, source_y: 0, source_x2: ws, source_y2: 0, source_x3: 0, source_y3: ws,
               path: WHITE, r: r, g: g, b: b }
      list << (key ? [key, prim] : prim)
    end
  end

  # Two-tone grass: the darker squares of a chequerboard of tiles around
  # the camera, so that speed can be felt off the road as well.
  def draw_checker
    t = Pieces::T
    ci = (@px / t).floor
    cj = (@pz / t).floor
    rad = (@view_distance / t).ceil
    fx = @fx
    fz = @fz
    back = -t * 1.5 - @py.abs * 2
    (-rad..rad).each do |dj|
      j = cj + dj
      z = (j + 0.5) * t - @pz
      (-rad..rad).each do |di|
        i = ci + di
        next if (i + j).even?
        next if ((i + 0.5) * t - @px) * fx - @py * @fy + z * fz < back

        draw_geo(checker_geo(i, j), true)
      end
    end
  end

  def checker_geo(i, j)
    key = (i + 4096) * 8192 + j + 4096
    geo = @checker[key]
    return geo if geo

    @checker.clear if @checker.size > 6000
    t = Pieces::T
    x = i * t
    z = j * t
    geo = Geo.new
    geo.quad([x, 0.0, z], [x + t, 0.0, z], [x + t, 0.0, z + t], [x, 0.0, z + t], GRASS_DARK, [0, 1, 0])
    # undo the baked sun so that the tile matches the plain ground colour
    k = 1.0 / Geo.shade([0.0, 1.0, 0.0])
    geo.tr.map! { |v| v * k }
    geo.tg.map! { |v| v * k }
    geo.tbl.map! { |v| v * k }
    @checker[key] = geo.finish
  end

  # Dark patch under the car, lying on the surface with normal n.
  def draw_shadow(pos, right, fwd, n)
    c = V.madd(pos, n, 0.04)
    pts = [[-1.15, -2.3], [1.15, -2.3], [1.15, 2.3], [-1.15, 2.3]].map do |x, z|
      project(V.madd(V.madd(c, right, x), fwd, z))
    end
    return if pts.any?(&:nil?)

    @shadow = [[0, 1, 2], [0, 2, 3]].map do |a, b, cc|
      { x: pts[a][0], y: pts[a][1], x2: pts[b][0], y2: pts[b][1], x3: pts[cc][0], y3: pts[cc][1],
        source_x: 0, source_y: 0, source_x2: 8, source_y2: 0, source_x3: 0, source_y3: 8,
        path: WHITE, r: 0, g: 0, b: 0, a: 95 }
    end
  end

  # Sends the frame to the screen: ground layer, world behind the car,
  # shadow, car and other meshes, world in front of the car.
  def flush_scene(out)
    @triangle_count += @ground.size + @behind.size + @front.size
    out << @ground
    out << D3D::DepthSort.pairs(@behind) unless @behind.empty?
    out << @shadow if @shadow
    out << D3D::DepthSort.pairs(@list) unless @list.empty?
    out << D3D::DepthSort.pairs(@front) unless @front.empty?
  end

  # ------------------------------------------------------------ backdrop

  # World y of the view ray through a screen point (forward component 1)
  # as a * x + b * y + c: positive above the horizon.
  def horizon_coeffs
    [@ry / @focal, @uy / @focal, @fy - (@ry * @half_w + @uy * @half_h) / @focal]
  end

  def self.clip_halfplane(poly, a, b, c)
    out = []
    n = poly.size
    n.times do |i|
      p = poly[i]
      q = poly[(i + 1) % n]
      dp = a * p[0] + b * p[1] + c
      dq = a * q[0] + b * q[1] + c
      out << p if dp >= 0
      next if (dp >= 0) == (dq >= 0)

      t = dp / (dp - dq)
      out << [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t]
    end
    out
  end

  # Part of the screen whose view rays have an elevation between lo and hi.
  def band(lo, hi)
    a, b, c = @horizon
    poly = SCREEN
    poly = StuntRenderer.clip_halfplane(poly, a, b, c - lo) if lo
    poly = StuntRenderer.clip_halfplane(poly, -a, -b, hi - c) if hi && poly.size >= 3
    poly
  end

  def fill(out, poly, col)
    return if poly.size < 3

    p0 = poly[0]
    (1...poly.size - 1).each do |i|
      p1 = poly[i]
      p2 = poly[i + 1]
      out << { x: p0[0], y: p0[1], x2: p1[0], y2: p1[1], x3: p2[0], y3: p2[1],
               source_x: 0, source_y: 0, source_x2: 8, source_y2: 0, source_x3: 0, source_y3: 8,
               path: WHITE, r: col[0], g: col[1], b: col[2] }
    end
  end

  # Sky in bands towards the horizon and the ground fading into the haze
  # at the distance where the world stops being drawn.
  def draw_backdrop(out)
    @horizon = horizon_coeffs
    out << { x: 0, y: 0, w: @width, h: @height, path: :solid,
             r: SKY_TOP[0], g: SKY_TOP[1], b: SKY_TOP[2] }
    6.times do |i|
      fill(out, band(SKY_STEPS[i], SKY_STEPS[i + 1]), V.lerp(SKY_LOW, SKY_TOP, i / 6.0))
    end
    fill(out, band(nil, 0.0), HAZE)
    alt = @py < 0.5 ? 0.5 : @py
    GROUND_STEPS.each do |k, h|
      fill(out, band(nil, -alt / (@view_distance * k)), V.lerp(GRASS, HAZE, h))
    end
  end

  V = D3D::V
end
