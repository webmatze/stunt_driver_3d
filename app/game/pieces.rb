# The track parts a course is built from. Every piece is defined in local
# coordinates (metres, origin at the centre of its footprint, entry at the
# south edge driving towards +z) and is rotated in 90 degree steps when placed.
#
# A piece has connectors [cell_i, cell_j, dir, level] (dir 0 = +z north,
# 1 = +x east, 2 = south, 3 = west; level 0 = ground, 1 = elevated,
# :jump = open end of a jump ramp), links between connector indices, the
# centre line of every link (for the minimap, the autopilot and the start
# position) and a build block that emits geometry through a PieceBuilder.
module Pieces
  V = D3D::V
  T = 30.0          # tile size
  H = T / 2
  HW = 4.0          # half road width
  CURB = 0.5
  EH = 6.0          # height of elevated roads
  JH = 4.0          # height of a jump ramp's lip
  JUMP_SLOPE = 1.6 * JH / T
  LOOP_R = 9.0
  LOOP_S = 2.9      # half of the sideways shift of the loop
  LOOP_HW = 2.6

  DX = [0, 1, 0, -1].freeze
  DZ = [1, 0, -1, 0].freeze

  ASPHALT_A = [96, 96, 104].freeze
  ASPHALT_B = [86, 86, 94].freeze
  CURB_R = [205, 52, 46].freeze
  CURB_W = [236, 236, 232].freeze
  LINE = [238, 238, 226].freeze
  CONCRETE = [172, 168, 158].freeze
  CONCRETE_D = [128, 126, 120].freeze
  EARTH = [150, 126, 92].freeze
  STEEL = [70, 88, 120].freeze
  WOOD = [112, 78, 48].freeze
  PINE = [38, 110, 58].freeze
  BRICK = [196, 170, 138].freeze
  ROOF = [158, 66, 52].freeze

  Piece = Struct.new(:id, :name, :w, :d, :conns, :links, :speed, :paths, :build, :scenery)
  DEFS = {}
  ORDER = []

  def self.define(id, name, conns: [], links: {}, w: 1, d: 1, speed: 70.0, paths: nil, &build)
    DEFS[id] = Piece.new(id, name, w, d, conns, links, speed, paths, build, conns.empty?)
    ORDER << id
  end

  # ---------------------------------------------------------------- placing

  def self.rot_xz(x, z, rot)
    rot.times { x, z = z, -x }
    [x, z]
  end

  # Footprint [w, d] in tiles of a piece rotated by rot quarter turns.
  def self.footprint(id, rot)
    p = DEFS[id]
    rot.odd? ? [p.d, p.w] : [p.w, p.d]
  end

  # Connectors of a rotated piece as [di, dj, dir, level], with the cell
  # relative to the anchor (the footprint's corner with the lowest i and j).
  def self.conns(id, rot)
    @conns ||= {}
    @conns[[id, rot]] ||= begin
      p = DEFS[id]
      fw, fd = footprint(id, rot)
      p.conns.map do |ci, cj, dir, lvl|
        x, z = rot_xz(ci + 0.5 - p.w / 2.0, cj + 0.5 - p.d / 2.0, rot)
        [(x + fw / 2.0 - 0.5).round, (z + fd / 2.0 - 0.5).round, (dir + rot) % 4, lvl]
      end
    end
  end

  # ---------------------------------------------------------------- curves

  def self.line(a, b, n)
    (0..n).map { |i| V.lerp(a, b, i.to_f / n) }
  end

  # Quarter circle around (cx, cz) from its west point, heading north, to
  # its north point, heading east.
  def self.arc(cx, cz, r, n, y = 0.0)
    (0..n).map do |i|
      a = Math::PI / 2 * i / n
      [cx - r * Math.cos(a), y, cz + r * Math.sin(a)]
    end
  end

  def self.hermite(p0, m0, p1, m1, n)
    (0..n).map do |i|
      t = i.to_f / n
      t2 = t * t
      t3 = t2 * t
      a = 2 * t3 - 3 * t2 + 1
      b = t3 - 2 * t2 + t
      c = -2 * t3 + 3 * t2
      d = t3 - t2
      [0, 1, 2].map { |k| a * p0[k] + b * m0[k] + c * p1[k] + d * m1[k] }
    end
  end

  # Cross sections [centre, right, up, half_width] along a centre line.
  # t0/t1 fix the direction at the ends; hint is the rough right vector
  # (default: horizontal, to the right of the driving direction).
  def self.secs(pts, hw = HW, hint: nil, t0: nil, t1: nil)
    n = pts.size
    (0...n).map do |i|
      t = if i == 0 && t0
            t0
          elsif i == n - 1 && t1
            t1
          else
            V.sub(pts[i < n - 1 ? i + 1 : i], pts[i > 0 ? i - 1 : i])
          end
      t = V.norm(t)
      h = hint || [t[2], 0.0, -t[0]]
      r = V.norm(V.sub(h, V.scale(t, V.dot(h, t))))
      [pts[i], r, V.cross(t, r), hw.is_a?(Array) ? hw[i] : hw]
    end
  end

  NORTH = [0.0, 0.0, 1.0].freeze
  EAST = [1.0, 0.0, 0.0].freeze

  def self.straight_pts(y = 0.0, n = 2)
    line([0.0, y, -H], [0.0, y, H], n)
  end

  def self.curve_pts(y = 0.0)
    arc(H, -H, H, 6, y)
  end

  def self.ramp_pts
    (0..8).map do |i|
      t = i / 8.0
      [0.0, EH * (1 - Math.cos(Math::PI * t)) / 2, -H + T * t]
    end
  end

  def self.jump_pts
    (0..8).map do |i|
      t = i / 8.0
      [0.0, JH * t**1.6, -H + T * t]
    end
  end

  def self.loop_tangent
    V.norm([LOOP_S / Math::PI, 0.0, LOOP_R])
  end

  def self.loop_approach
    m = V.scale(loop_tangent, H)
    hermite([0.0, 0.0, -H], [0.0, 0.0, H], [-LOOP_S, 0.0, 0.0], m, 6)
  end

  def self.loop_helix
    (0..32).map do |i|
      a = 2 * Math::PI * i / 32
      [-LOOP_S + 2 * LOOP_S * i / 32.0, LOOP_R * (1 - Math.cos(a)), LOOP_R * Math.sin(a)]
    end
  end

  def self.loop_exit
    loop_approach.reverse.map { |p| [-p[0], 0.0, -p[2]] }
  end

  S0 = [0, 0, 2, 0].freeze
  N0 = [0, 0, 0, 0].freeze
  W0 = [0, 0, 3, 0].freeze
  E0 = [0, 0, 1, 0].freeze
  S1 = [0, 0, 2, 1].freeze
  N1 = [0, 0, 0, 1].freeze
  E1 = [0, 0, 1, 1].freeze
  THROUGH = { 0 => 1, 1 => 0 }.freeze
  CROSSING = { 0 => 1, 1 => 0, 2 => 3, 3 => 2 }.freeze

  # ---------------------------------------------------------------- roads

  define(:straight, 'Gerade', conns: [S0, N0], links: THROUGH,
                              paths: -> { { [0, 1] => straight_pts } }) do |b|
    b.ribbon(secs(straight_pts), ground: true)
  end

  define(:start, 'Start/Ziel', conns: [S0, N0], links: THROUGH,
                               paths: -> { { [0, 1] => straight_pts } }) do |b|
    b.ribbon(secs(straight_pts), ground: true)
    8.times do |i|
      2.times do |k|
        col = (i + k).even? ? [245, 245, 245] : [26, 26, 30]
        b.ground_quad(-HW + i, -1.0 + k, -HW + i + 1, k, col)
      end
    end
    b.box([-5.7, 0.0, -0.4], [-4.9, 6.2, 0.4], STEEL, solid: true)
    b.box([4.9, 0.0, -0.4], [5.7, 6.2, 0.4], STEEL, solid: true)
    b.box([-5.7, 5.2, -0.5], [5.7, 6.6, 0.5], [232, 196, 52], bottom: true)
  end

  define(:curve, 'Kurve', conns: [S0, E0], links: THROUGH, speed: 14.5,
                          paths: -> { { [0, 1] => curve_pts } }) do |b|
    b.ribbon(secs(curve_pts, t0: NORTH, t1: EAST), ground: true)
  end

  define(:wide_curve, 'Weite Kurve', w: 2, d: 2, conns: [[0, 0, 2, 0], [1, 1, 1, 0]],
                                     links: THROUGH, speed: 27.0,
                                     paths: -> { { [0, 1] => arc(T, -T, 1.5 * T, 10) } }) do |b|
    b.ribbon(secs(arc(T, -T, 1.5 * T, 10), t0: NORTH, t1: EAST), ground: true)
  end

  define(:cross, 'Kreuzung', conns: [S0, N0, W0, E0], links: CROSSING,
                             paths: lambda {
                               { [0, 1] => straight_pts,
                                 [2, 3] => line([-H, 0.0, 0.0], [H, 0.0, 0.0], 2) }
                             }) do |b|
    b.ribbon(secs(line([0.0, 0.0, -H], [0.0, 0.0, -HW], 1)), ground: true)
    b.ribbon(secs(line([0.0, 0.0, HW], [0.0, 0.0, H], 1)), ground: true)
    b.ribbon(secs(line([-H, 0.0, 0.0], [-HW, 0.0, 0.0], 1)), ground: true)
    b.ribbon(secs(line([HW, 0.0, 0.0], [H, 0.0, 0.0], 1)), ground: true)
    b.ribbon(secs(line([0.0, 0.0, -HW], [0.0, 0.0, HW], 1)), ground: true, curbs: false, dashes: false)
  end

  # ---------------------------------------------------------------- heights

  define(:ramp, 'Rampe', conns: [S0, N1], links: THROUGH, speed: [21.0, 19.0],
                         paths: -> { { [0, 1] => ramp_pts } }) do |b|
    pts = ramp_pts
    b.ribbon(secs(pts, t0: NORTH, t1: NORTH), skirt: true)
    b.quad([-HW, 0.0, H], [HW, 0.0, H], [HW, EH, H], [-HW, EH, H], EARTH, NORTH)
    b.wedge_solids(pts)
  end

  define(:elevated, 'Hochstraße', conns: [S1, N1], links: THROUGH, speed: 60.0,
                                  paths: -> { { [0, 1] => straight_pts(EH) } }) do |b|
    b.ribbon(secs(straight_pts(EH)), thick: 0.5)
    b.pillar(0.0, -9.0)
    b.pillar(0.0, 9.0)
  end

  define(:elevated_curve, 'Hochkurve', conns: [S1, E1], links: THROUGH, speed: 13.5,
                                       paths: -> { { [0, 1] => curve_pts(EH) } }) do |b|
    pts = curve_pts(EH)
    b.ribbon(secs(pts, t0: NORTH, t1: EAST), thick: 0.5)
    b.pillar(pts[1][0], pts[1][2])
    b.pillar(pts[5][0], pts[5][2])
  end

  define(:bridge, 'Brücke', conns: [S1, N1, W0, E0], links: CROSSING, speed: 60.0,
                            paths: lambda {
                              { [0, 1] => straight_pts(EH),
                                [2, 3] => line([-H, 0.0, 0.0], [H, 0.0, 0.0], 2) }
                            }) do |b|
    b.ribbon(secs(line([-H, 0.0, 0.0], [H, 0.0, 0.0], 2)), ground: true)
    b.ribbon(secs(straight_pts(EH)), thick: 0.5)
    b.pillar(0.0, -9.0)
    b.pillar(0.0, 9.0)
  end

  define(:jump, 'Sprungschanze', conns: [S0, [0, 0, 0, :jump]], links: THROUGH, speed: 70.0,
                                 paths: -> { { [0, 1] => jump_pts } }) do |b|
    pts = jump_pts
    b.ribbon(secs(pts, t0: NORTH), skirt: true)
    b.quad([-HW, 0.0, H], [HW, 0.0, H], [HW, JH, H], [-HW, JH, H], [214, 170, 60], NORTH)
    b.wedge_solids(pts)
    b.solid([-HW, 0.0, H - 0.6], [HW, JH - 0.7, H])
  end

  define(:loop, 'Looping', conns: [S0, N0], links: THROUGH, speed: 36.0,
                           paths: lambda {
                             { [0, 1] => loop_approach + loop_helix[1..-1] + loop_exit[1..-1] }
                           }) do |b|
    tan = loop_tangent
    narrow = [HW, 3.6, 3.1, LOOP_HW, LOOP_HW, LOOP_HW, LOOP_HW]
    b.ribbon(secs(loop_approach, narrow, t0: NORTH, t1: tan), ground: true, dashes: false, guide: true)
    b.ribbon(secs(loop_exit, narrow.reverse, t0: tan, t1: NORTH), ground: true, dashes: false, guide: true)
    b.ribbon(secs(loop_helix, LOOP_HW, hint: EAST, t0: tan, t1: tan),
             double: true, guide: true, gate: ->(i) { i >= 11 && i <= 20 })
    # supports beside the strip, just outside the loop so cars inside can't touch them
    x = LOOP_S / 2 + LOOP_HW + 0.2
    b.box([-x - 0.7, 0.0, LOOP_R + 0.2], [-x, LOOP_R, LOOP_R + 1.2], STEEL, solid: true)
    b.box([x, 0.0, -LOOP_R - 1.2], [x + 0.7, LOOP_R, -LOOP_R - 0.2], STEEL, solid: true)
  end

  define(:tunnel, 'Tunnel', conns: [S0, N0], links: THROUGH,
                            paths: -> { { [0, 1] => straight_pts } }) do |b|
    b.ribbon(secs(straight_pts), ground: true)
    b.box([-5.6, 0.0, -H], [-4.6, 5.0, H], CONCRETE, solid: true)
    b.box([4.6, 0.0, -H], [5.6, 5.0, H], CONCRETE, solid: true)
    b.box([-5.6, 5.0, -H], [5.6, 5.8, H], CONCRETE_D, bottom: true)
  end

  define(:obstacle, 'Hindernis', conns: [S0, N0], links: THROUGH, speed: 12.0,
                                 paths: lambda {
                                   { [0, 1] => [[0.0, 0.0, -H], [1.0, 0.0, -11.5], [2.2, 0.0, -7.5],
                                                [2.0, 0.0, -4.5], [0.0, 0.0, 0.0], [-2.0, 0.0, 4.5],
                                                [-2.2, 0.0, 7.5], [-1.0, 0.0, 11.5], [0.0, 0.0, H]] }
                                 }) do |b|
    b.ribbon(secs(straight_pts), ground: true)
    [[-HW, -0.6, -7.0], [0.6, HW, 6.0]].each do |x0, x1, z|
      4.times do |i|
        w = (x1 - x0) / 4
        col = i.even? ? CURB_R : CURB_W
        b.box([x0 + w * i, 0.0, z], [x0 + w * (i + 1), 1.1, z + 1.0], col)
      end
      b.solid([x0, 0.0, z], [x1, 1.1, z + 1.0])
    end
  end

  # ---------------------------------------------------------------- scenery

  define(:trees, 'Bäume') do |b|
    [[-7.0, -6.0, 1.0], [5.0, 4.0, 1.25], [-2.0, 9.0, 0.85]].each do |x, z, s|
      b.box([x - 0.4, 0.0, z - 0.4], [x + 0.4, 2.0 * s, z + 0.4], WOOD, solid: true)
      b.pyramid(x, 1.6 * s, z, 2.6 * s, 7.0 * s, PINE)
    end
  end

  define(:house, 'Haus') do |b|
    b.box([-5.0, 0.0, -4.0], [5.0, 4.4, 4.0], BRICK, solid: true)
    ridge0 = [-5.0, 7.4, 0.0]
    ridge1 = [5.0, 7.4, 0.0]
    b.quad([-5.0, 4.4, -4.0], [5.0, 4.4, -4.0], ridge1, ridge0, ROOF, [0, 1, -1])
    b.quad([-5.0, 4.4, 4.0], [5.0, 4.4, 4.0], ridge1, ridge0, ROOF, [0, 1, 1])
    b.tri([-5.0, 4.4, -4.0], [-5.0, 4.4, 4.0], ridge0, BRICK, [-1, 0, 0])
    b.tri([5.0, 4.4, -4.0], [5.0, 4.4, 4.0], ridge1, BRICK, [1, 0, 0])
  end

  define(:tribune, 'Tribüne') do |b|
    3.times do |i|
      col = i.even? ? [70, 104, 172] : [222, 222, 214]
      b.box([-11.0, i * 1.8, -4.0 + i * 2.4], [11.0, (i + 1) * 1.8, 4.0], col)
    end
    b.box([-11.0, 0.0, 4.0], [11.0, 8.0, 4.8], CONCRETE_D)
    b.solid([-11.0, 0.0, -4.0], [11.0, 5.4, 4.8])
  end
end

# Emits the geometry of one placed piece: `geo` (depth sorted), `ground`
# (flat on the ground, drawn first and unsorted), collision triangles and
# solid boxes, all transformed into world space.
class PieceBuilder
  V = D3D::V
  P = Pieces

  attr_reader :geo, :ground, :cols, :solids

  # key: id stored in the collision triangles; rot: quarter turns;
  # ox/oz: world position of the footprint centre.
  def initialize(key, rot, ox, oz)
    @key = key
    @rot = rot
    @ox = ox
    @oz = oz
    @geo = Geo.new
    @ground = Geo.new
    @cols = []
    @solids = []
  end

  def w(p)
    x, z = P.rot_xz(p[0], p[2], @rot)
    [x + @ox, p[1].to_f, z + @oz]
  end

  def wd(d)
    x, z = P.rot_xz(d[0], d[2], @rot)
    [x, d[1].to_f, z]
  end

  # Road surface along cross sections (see Pieces.secs).
  #   ground: flat on the ground (ground layer)   thick: slab with underside
  #   skirt: side walls down to the ground        double: visible from below
  #   gate: counts for checkpoints (true/false or ->(segment) { })
  #   guide: the road gently steers the car along itself (loop)
  def ribbon(secs, ground: false, thick: 0.0, skirt: false, curbs: true, double: false,
             gate: true, dashes: nil, guide: false)
    g = ground ? @ground : @geo
    dashes = ground if dashes.nil?
    ws = secs.map { |c, r, u, hw| [w(c), wd(r), wd(u), hw] }
    (ws.size - 1).times do |i|
      c0, r0, u0, h0 = ws[i]
      c1, r1, u1, h1 = ws[i + 1]
      l0 = V.madd(c0, r0, -h0)
      e0 = V.madd(c0, r0, h0)
      l1 = V.madd(c1, r1, -h1)
      e1 = V.madd(c1, r1, h1)
      un = V.norm(V.add(u0, u1))
      asphalt = i.even? ? P::ASPHALT_A : P::ASPHALT_B
      if curbs
        cl0 = V.madd(c0, r0, -h0 + P::CURB)
        cr0 = V.madd(c0, r0, h0 - P::CURB)
        cl1 = V.madd(c1, r1, -h1 + P::CURB)
        cr1 = V.madd(c1, r1, h1 - P::CURB)
        curb = i.even? ? P::CURB_R : P::CURB_W
        g.quad(l0, cl0, cl1, l1, curb, un, double: double)
        g.quad(cl0, cr0, cr1, cl1, asphalt, un, double: double)
        g.quad(cr0, e0, e1, cr1, curb, un, double: double)
      else
        g.quad(l0, e0, e1, l1, asphalt, un, double: double)
      end
      if dashes
        a = V.lerp(c0, c1, 0.25)
        d = V.lerp(c0, c1, 0.75)
        g.quad(V.madd(a, r0, -0.15), V.madd(a, r0, 0.15), V.madd(d, r1, 0.15), V.madd(d, r1, -0.15),
               P::LINE, un)
      end
      gt = gate.respond_to?(:call) ? gate.call(i) : gate
      dir = guide ? V.norm(V.sub(c1, c0)) + c0 : nil
      col(l0, e0, e1, u0, u0, u1, gt, dir)
      col(l0, e1, l1, u0, u1, u1, gt, dir)
      if thick > 0
        bl0 = V.madd(l0, u0, -thick)
        be0 = V.madd(e0, u0, -thick)
        bl1 = V.madd(l1, u1, -thick)
        be1 = V.madd(e1, u1, -thick)
        g.quad(l0, l1, bl1, bl0, P::CONCRETE, V.scale(r0, -1.0))
        g.quad(e0, e1, be1, be0, P::CONCRETE, r0)
        g.quad(bl0, be0, be1, bl1, P::CONCRETE_D, V.scale(un, -1.0))
      end
      next unless skirt && (l0[1] > 0.05 || l1[1] > 0.05)

      g.quad(l0, l1, [l1[0], 0.0, l1[2]], [l0[0], 0.0, l0[2]], P::EARTH, V.scale(r0, -1.0))
      g.quad(e0, e1, [e1[0], 0.0, e1[2]], [e0[0], 0.0, e0[2]], P::EARTH, r0)
    end
  end

  # Collision triangle:
  #   [a(3), e1(3), e2(3), n(3), na(3), nb(3), nc(3), surface, key, gate, guide]
  # guide: nil or [direction(3), point(3)] of the centre line the car is steered along.
  def col(a, b, c, na, nb, nc, gate, guide = nil, surface = :road)
    e1 = V.sub(b, a)
    e2 = V.sub(c, a)
    n = V.norm(V.cross(e1, e2))
    n = V.scale(n, -1.0) if V.dot(n, na) < 0
    @cols << (a + e1 + e2 + n + na + nb + nc + [surface, @key, gate, guide])
  end

  def quad(p0, p1, p2, p3, color, hint, double: false)
    @geo.quad(w(p0), w(p1), w(p2), w(p3), color, wd(hint), double: double)
  end

  def tri(p0, p1, p2, color, hint)
    @geo.tri(w(p0), w(p1), w(p2), color, wd(hint))
  end

  # Flat rectangle painted on the ground (start line etc.).
  def ground_quad(x0, z0, x1, z1, color)
    @ground.quad(w([x0, 0.0, z0]), w([x1, 0.0, z0]), w([x1, 0.0, z1]), w([x0, 0.0, z1]),
                 color, [0, 1, 0])
  end

  def box(lo, hi, color, solid: false, bottom: false)
    a = w(lo)
    b = w(hi)
    wlo = [[a[0], b[0]].min, a[1], [a[2], b[2]].min]
    whi = [[a[0], b[0]].max, b[1], [a[2], b[2]].max]
    @geo.box(wlo, whi, color, bottom: bottom)
    @solids << (wlo + whi) if solid
  end

  # Invisible box the car collides with.
  def solid(lo, hi)
    a = w(lo)
    b = w(hi)
    @solids << [[a[0], b[0]].min, a[1], [a[2], b[2]].min, [a[0], b[0]].max, b[1], [a[2], b[2]].max]
  end

  def pillar(x, z)
    box([x - 0.7, 0.0, z - 0.7], [x + 0.7, P::EH - 0.5, z + 0.7], P::CONCRETE, solid: true)
  end

  def pyramid(x, y, z, r, h, color)
    tip = [x, y + h, z]
    c = [[x - r, y, z - r], [x + r, y, z - r], [x + r, y, z + r], [x - r, y, z + r]]
    4.times do |i|
      a = c[i]
      b = c[(i + 1) % 4]
      tri(a, b, tip, color, [(a[0] + b[0]) / 2 - x, 0.6, (a[2] + b[2]) / 2 - z])
    end
  end

  # Boxes under a rising road (points along +z) so that the car can't drive
  # through its embankment from the side.
  def wedge_solids(pts)
    (2...pts.size - 1).each do |i|
      h = pts[i][1] - 0.7
      next if h < 0.4

      solid([-P::HW, 0.0, pts[i][2]], [P::HW, h, pts[i + 1][2]])
    end
  end

  def finish
    @geo.finish
    @ground.finish
    self
  end
end
