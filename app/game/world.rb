# Everything a Track turns into for driving: render geometry per piece,
# collision triangles and solid boxes hashed by tile, the route with its
# centre line and the start position.
class World
  V = D3D::V
  T = Pieces::T
  N = Track::SIZE
  NONE = [].freeze

  attr_reader :track, :route, :geos, :ground_geos, :keys, :path, :path_speed,
              :start_pos, :start_fwd, :start_center

  def initialize(track)
    @track = track
    @cols = Array.new(N * N)
    @solids = Array.new(N * N)
    @geos = []
    @ground_geos = []
    track.cells.each do |key, (id, rot)|
      ai, aj = track.coords(key)
      b = build_piece(key, id, rot, ai, aj)
      @geos << b.geo unless b.geo.empty?
      @ground_geos << b.ground unless b.ground.empty?
      b.cols.each { |c| register(@cols, c, tri_bounds(c), 2.6) }
      b.solids.each { |s| register(@solids, s, [s[0], s[2], s[3], s[5]], 2.5) }
    end
    @route = track.route
    @keys = []
    @path = []
    @path_speed = []
    find_start
    build_path if @route[:ok]
  end

  def ok?
    @route[:ok]
  end

  def self.center(ai, aj, id, rot)
    fw, fd = Pieces.footprint(id, rot)
    [(ai + fw / 2.0) * T, (aj + fd / 2.0) * T]
  end

  # Collision triangles near a position (see PieceBuilder#col for the layout).
  def cols_at(x, z)
    i = (x / T).floor
    j = (z / T).floor
    return NONE if i < 0 || j < 0 || i >= N || j >= N

    @cols[i + j * N] || NONE
  end

  # Solid boxes [x0, y0, z0, x1, y1, z1] near a position.
  def solids_at(x, z)
    i = (x / T).floor
    j = (z / T).floor
    return NONE if i < 0 || j < 0 || i >= N || j >= N

    @solids[i + j * N] || NONE
  end

  # Nearest collision triangle hit by a ray (unit direction) within max.
  # cull: ignore triangles seen from behind. Returns [t, tri, u, v] (u, v:
  # barycentric weights of the 2nd and 3rd corner) or nil. Only triangles
  # registered for the tile of the origin are tested, so max must stay
  # below the registration margin (2.6).
  def raycast(ox, oy, oz, dx, dy, dz, max, cull)
    list = cols_at(ox, oz)
    best = nil
    bu = 0.0
    bv = 0.0
    i = 0
    n = list.size
    while i < n
      t = list[i]
      i += 1
      next if cull && t[9] * dx + t[10] * dy + t[11] * dz >= 0

      e1x = t[3]
      e1y = t[4]
      e1z = t[5]
      e2x = t[6]
      e2y = t[7]
      e2z = t[8]
      hx = dy * e2z - dz * e2y
      hy = dz * e2x - dx * e2z
      hz = dx * e2y - dy * e2x
      det = e1x * hx + e1y * hy + e1z * hz
      next if det > -1e-9 && det < 1e-9

      inv = 1.0 / det
      sx = ox - t[0]
      sy = oy - t[1]
      sz = oz - t[2]
      u = (sx * hx + sy * hy + sz * hz) * inv
      next if u < -1e-5 || u > 1.00001

      qx = sy * e1z - sz * e1y
      qy = sz * e1x - sx * e1z
      qz = sx * e1y - sy * e1x
      v = (dx * qx + dy * qy + dz * qz) * inv
      next if v < -1e-5 || u + v > 1.00001

      tt = (e2x * qx + e2y * qy + e2z * qz) * inv
      next if tt < 0 || tt >= max

      max = tt
      best = t
      bu = u
      bv = v
    end
    best ? [max, best, bu, bv] : nil
  end

  private

  def build_piece(key, id, rot, ai, aj)
    cx, cz = World.center(ai, aj, id, rot)
    b = PieceBuilder.new(key, rot, cx, cz)
    Pieces::DEFS[id].build.call(b)
    b.finish
  end

  def tri_bounds(c)
    xs = [c[0], c[0] + c[3], c[0] + c[6]]
    zs = [c[2], c[2] + c[5], c[2] + c[8]]
    [xs.min, zs.min, xs.max, zs.max]
  end

  # Adds item to every tile its x/z bounds (grown by margin) touch.
  def register(grid, item, bounds, margin)
    i0 = [((bounds[0] - margin) / T).floor, 0].max
    j0 = [((bounds[1] - margin) / T).floor, 0].max
    i1 = [((bounds[2] + margin) / T).floor, N - 1].min
    j1 = [((bounds[3] + margin) / T).floor, N - 1].min
    (j0..j1).each do |j|
      (i0..i1).each { |i| (grid[i + j * N] ||= []) << item }
    end
  end

  def find_start
    key = @track.cells.keys.find { |k| @track.cells[k][0] == :start }
    unless key
      mid = N * T / 2
      @start_center = [mid, 0.0, mid]
      @start_pos = [mid, 0.0, mid]
      @start_fwd = [0.0, 0.0, 1.0]
      return
    end
    ai, aj = @track.coords(key)
    rot = @track.cells[key][1]
    fx, fz = Pieces.rot_xz(0.0, 1.0, rot)
    @start_fwd = [fx, 0.0, fz]
    @start_center = [(ai + 0.5) * T, 0.0, (aj + 0.5) * T]
    @start_pos = V.madd(@start_center, @start_fwd, -9.0)
  end

  # Centre line of the whole route in driving order, with a speed hint per
  # point for the autopilot.
  def build_path
    @route[:steps].each do |ai, aj, id, rot, cin, cout, gap|
      piece = Pieces::DEFS[id]
      @keys << @track.key(ai, aj)
      forward = cin < cout
      pts = piece.paths.call[forward ? [cin, cout] : [cout, cin]]
      pts = pts.reverse unless forward
      speed = piece.speed
      speed = speed[forward ? 0 : 1] if speed.is_a?(Array)
      speed = World.jump_speed(gap) * 1.1 + 2.0 if id == :jump && forward && gap > 0
      cx, cz = World.center(ai, aj, id, rot)
      pts.each_with_index do |p, n|
        x, z = Pieces.rot_xz(p[0], p[2], rot)
        wp = [x + cx, p[1].to_f, z + cz]
        next if n == 0 && !@path.empty? && V.dist(@path[-1], wp) < 0.01

        @path << wp
        @path_speed << speed
      end
    end
    return unless @path.size > 1 && V.dist(@path[0], @path[-1]) < 0.01

    @path.pop
    @path_speed.pop
  end

  public

  # Take-off speed needed to clear `gap` empty tiles between two jump ramps.
  def self.jump_speed(gap)
    return 0.0 if gap <= 0

    a = Math.atan(Pieces::JUMP_SLOPE)
    Math.sqrt(gap * T * Car::G / Math.sin(2 * a))
  end
end
