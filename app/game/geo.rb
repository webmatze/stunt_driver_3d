# Static world geometry in world space: deduplicated vertices plus triangles
# with a face normal and a colour that already contains the sun light. The
# flat arrays are read directly by StuntRenderer#draw_geo.
class Geo
  V = D3D::V
  SUN = V.norm([0.42, 0.82, -0.38])

  attr_reader :vx, :vy, :vz, :ta, :tb, :tc, :tr, :tg, :tbl, :tnx, :tny, :tnz, :tds,
              :center, :radius

  def initialize
    @vx = []
    @vy = []
    @vz = []
    @ta = []
    @tb = []
    @tc = []
    @tr = []
    @tg = []
    @tbl = []
    @tnx = []
    @tny = []
    @tnz = []
    @tds = []
    @index = {}
    @center = [0.0, 0.0, 0.0]
    @radius = 0.0
  end

  def empty?
    @ta.empty?
  end

  def tri_count
    @ta.size
  end

  def vert(p)
    key = [(p[0] * 200).round, (p[1] * 200).round, (p[2] * 200).round]
    i = @index[key]
    return i if i

    @vx << p[0].to_f
    @vy << p[1].to_f
    @vz << p[2].to_f
    @index[key] = @vx.size - 1
  end

  # Brightness of a surface with unit normal n under the sun.
  def self.shade(n)
    l = V.dot(n, SUN)
    l > 0 ? 0.6 + 0.48 * l : 0.6 + 0.22 * l
  end

  # Triangle of world points; its normal is flipped to agree with `hint`.
  # double: visible from both sides.
  def tri(p0, p1, p2, color, hint, double: false)
    n = V.cross(V.sub(p1, p0), V.sub(p2, p0))
    l = V.len(n)
    return if l < 1e-9

    n = V.scale(n, 1.0 / l)
    n = V.scale(n, -1.0) if V.dot(n, hint) < 0
    k = Geo.shade(n)
    @ta << vert(p0)
    @tb << vert(p1)
    @tc << vert(p2)
    @tr << [color[0] * k, 255.0].min
    @tg << [color[1] * k, 255.0].min
    @tbl << [color[2] * k, 255.0].min
    @tnx << n[0]
    @tny << n[1]
    @tnz << n[2]
    @tds << double
  end

  def quad(p0, p1, p2, p3, color, hint, double: false)
    tri(p0, p1, p2, color, hint, double: double)
    tri(p0, p2, p3, color, hint, double: double)
  end

  # Axis aligned box between the corners lo and hi.
  def box(lo, hi, color, top: nil, bottom: false)
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    quad([x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0], color, [0, 0, -1])
    quad([x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1], color, [0, 0, 1])
    quad([x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0], color, [-1, 0, 0])
    quad([x1, y0, z0], [x1, y0, z1], [x1, y1, z1], [x1, y1, z0], color, [1, 0, 0])
    quad([x0, y1, z0], [x1, y1, z0], [x1, y1, z1], [x0, y1, z1], top || color, [0, 1, 0])
    quad([x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1], color, [0, -1, 0]) if bottom
  end

  # Computes the bounding sphere used for culling. Call once after building.
  def finish
    n = @vx.size
    return self if n == 0

    lo = [@vx.min, @vy.min, @vz.min]
    hi = [@vx.max, @vy.max, @vz.max]
    @center = [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2]
    @radius = V.dist(lo, hi) / 2
    self
  end

  # Yields [ax, ay, az, bx, by, bz, cx, cy, cz, r, g, b] per triangle.
  def each_tri
    @ta.size.times do |i|
      a = @ta[i]
      b = @tb[i]
      c = @tc[i]
      yield @vx[a], @vy[a], @vz[a], @vx[b], @vy[b], @vz[b], @vx[c], @vy[c], @vz[c],
            @tr[i], @tg[i], @tbl[i]
    end
  end
end
