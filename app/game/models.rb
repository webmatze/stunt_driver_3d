# Flat shaded meshes of the car (local space: +x right, +y up, +z forward,
# origin on the road under the middle of the car) and the wreckage that
# flies apart after a crash.
module Models
  V = D3D::V
  PAINT = [214, 44, 40].freeze
  PAINT_DARK = [150, 30, 30].freeze
  GLASS = [52, 74, 104].freeze
  TYRE = [34, 34, 38].freeze
  HUB = [178, 178, 184].freeze
  WHEELS = [[-0.98, 0.36, 1.32], [0.98, 0.36, 1.32], [-0.98, 0.36, -1.3], [0.98, 0.36, -1.3]].freeze

  def self.body
    @body ||= begin
      m = D3D::FlatMesh.new
      m.box(0.0, 0.56, 0.0, 0.95, 0.3, 2.1, PAINT, PAINT_DARK)
      # cabin: a frustum with glass all around and a painted roof
      lo = [[-0.85, 0.86, -1.35], [0.85, 0.86, -1.35], [0.85, 0.86, 0.85], [-0.85, 0.86, 0.85]]
      hi = [[-0.68, 1.3, -0.95], [0.68, 1.3, -0.95], [0.68, 1.3, 0.3], [-0.68, 1.3, 0.3]]
      l = lo.map { |p| m.vert(*p) }
      h = hi.map { |p| m.vert(*p) }
      inside = [0.0, 1.0, -0.2]
      4.times do |i|
        j = (i + 1) % 4
        m.quad(l[i], l[j], h[j], h[i], i.even? ? GLASS : [44, 62, 90], inside: inside)
      end
      m.quad(h[0], h[1], h[2], h[3], PAINT, inside: inside)
      # rear wing, head and tail lights
      m.box(0.0, 1.08, -2.0, 0.95, 0.04, 0.22, PAINT_DARK)
      m.box(-0.62, 0.62, 2.11, 0.22, 0.1, 0.02, [255, 244, 190], emissive: true)
      m.box(0.62, 0.62, 2.11, 0.22, 0.1, 0.02, [255, 244, 190], emissive: true)
      m.box(-0.66, 0.66, -2.11, 0.2, 0.08, 0.02, [255, 40, 30], emissive: true)
      m.box(0.66, 0.66, -2.11, 0.2, 0.08, 0.02, [255, 40, 30], emissive: true)
      m
    end
  end

  # Wheel around the x axis, centred on its hub.
  def self.wheel
    @wheel ||= begin
      m = D3D::FlatMesh.new
      r = 0.36
      w = 0.15
      sides = 8
      left = []
      right = []
      sides.times do |i|
        a = Math::PI * 2 * i / sides
        y = Math.cos(a) * r
        z = Math.sin(a) * r
        left << m.vert(-w, y, z)
        right << m.vert(w, y, z)
      end
      cl = m.vert(-w, 0.0, 0.0)
      cr = m.vert(w, 0.0, 0.0)
      sides.times do |i|
        j = (i + 1) % sides
        m.quad(left[i], left[j], right[j], right[i], TYRE)
        m.tri(left[i], left[j], cl, HUB)
        m.tri(right[i], right[j], cr, HUB)
      end
      m
    end
  end

  def self.chunk(color)
    D3D::FlatMesh.new.box(0.0, 0.0, 0.0, 0.22, 0.14, 0.3, color)
  end

  # Draws the car with its four wheels (the front ones turned by steer).
  def self.draw_car(renderer, car, flash = 0.0)
    r = car.right
    u = car.up
    f = car.fwd
    renderer.draw_mesh(body, car.pos, r, u, f, 1.0, [1.0, 1.0, 1.0], flash, ambient: 0.75)
    sf, sr = V.rotate_pair(f, r, car.steer * 1.4)
    WHEELS.each_with_index do |w, i|
      p = V.madd(V.madd(V.madd(car.pos, r, w[0]), u, w[1]), f, w[2])
      if i < 2
        renderer.draw_mesh(wheel, p, sr, u, sf, 1.0, [1.0, 1.0, 1.0], flash, ambient: 0.75)
      else
        renderer.draw_mesh(wheel, p, r, u, f, 1.0, [1.0, 1.0, 1.0], flash, ambient: 0.75)
      end
    end
  end
end

# The pieces of a wrecked car: body, wheels and chunks tumbling away from
# the crash, bouncing on the ground.
class Wreck
  V = D3D::V
  Part = Struct.new(:mesh, :pose, :vel, :spin_a, :spin_b)

  attr_reader :age, :origin

  def initialize(car)
    @age = 0.0
    @origin = V.madd(car.pos, car.up, 0.6)
    base = V.scale(car.vel, 0.45)
    @parts = []
    add(Models.body, car.pos, car, V.add(base, [0.0, 6.0, 0.0]), 2.0)
    Models::WHEELS.each do |w|
      p = V.madd(V.madd(V.madd(car.pos, car.right, w[0]), car.up, w[1]), car.fwd, w[2])
      add(Models.wheel, p, car, V.add(base, scatter(9.0)), 9.0)
    end
    cols = [Models::PAINT, Models::PAINT_DARK, Models::GLASS, [60, 60, 64]]
    12.times do |i|
      add(Models.chunk(cols[i % 4]), @origin, car, V.add(base, scatter(13.0)), 12.0)
    end
  end

  def update(dt)
    @age += dt
    @parts.each do |p|
      p.vel[1] -= Car::G * dt
      pos = V.madd(p.pose.position, p.vel, dt)
      if pos[1] < 0.15
        pos[1] = 0.15
        p.vel = [p.vel[0] * 0.7, p.vel[1].abs * 0.35, p.vel[2] * 0.7]
        p.spin_a *= 0.6
        p.spin_b *= 0.6
      end
      p.pose.position = pos
      p.pose.pitch!(p.spin_a * dt).roll!(p.spin_b * dt).orthonormalize!
    end
  end

  def draw(renderer)
    @parts.each do |p|
      q = p.pose
      renderer.draw_mesh(p.mesh, q.position, q.right, q.up, q.fwd, 1.0, [1.0, 1.0, 1.0], 0.0, ambient: 0.75)
    end
    return unless @age < 0.5

    k = 1.0 - @age / 0.5
    renderer.draw_glow(@origin, 6.0 + @age * 30.0, 255, 190, 90, 255 * k)
  end

  private

  def scatter(s)
    [(rand - 0.5) * s, rand * s * 0.8 + 2.0, (rand - 0.5) * s]
  end

  def add(mesh, pos, car, vel, spin)
    pose = D3D::Pose.new(pos, car.fwd, car.up)
    @parts << Part.new(mesh, pose, vel, (rand - 0.5) * spin * 2, (rand - 0.5) * spin * 2)
  end
end
