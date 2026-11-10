# Arcade car physics. The car is a point on the road surface (pos) with an
# orientation basis (right, up, fwd) and a world velocity. Each substep:
#   1. steering, tyre grip, engine, brakes and drag (only with ground contact)
#   2. gravity
#   3. a ray along the velocity catches walls and undersides -> crash
#   4. a ray along the car's own "down" finds the surface: the car is put
#      onto it and its velocity turned into the surface plane. Because the
#      ray follows the car's orientation, this works on ramps and upside
#      down in a loop; a car that is too slow there simply loses contact.
#   5. two spheres collide with solid boxes (pillars, walls, trees)
# Landing too hard or not on the wheels, and hitting anything fast, ends
# the run (crashed).
class Car
  V = D3D::V
  G = 14.0
  SUBSTEPS = 2
  WHEELBASE = 2.6
  ENGINE = 11.0        # acceleration from standstill
  ENGINE_VMAX = 68.0   # speed at which the engine has no pull left
  BRAKE = 22.0
  REVERSE_ACCEL = 6.0
  REVERSE_MAX = 12.0
  ROLL = 1.0
  DRAG = 0.00025
  GRASS_DRAG = 0.5
  GRIP_ROAD = 24.0
  GRIP_GRASS = 10.0
  STEER_ACCEL = 20.0   # lateral acceleration full steering asks for
  STEER_MAX = 0.6
  STEER_RATE = 2.6
  GUIDE = 5.0          # how firmly a guiding road (loop) turns the car along itself
  GUIDE_PULL = 3.0     # ... and towards its centre line (sideways speed per metre off)
  RAY_UP = 1.0
  SKIN = 0.06
  CRASH_WALL = 8.0     # closing speed that wrecks the car
  CRASH_LAND = 19.0    # touchdown speed (into the surface) that wrecks it
  GEARS = [0.0, 15.0, 26.0, 38.0, 50.0, 68.0].freeze
  UP = [0.0, 1.0, 0.0].freeze

  attr_reader :pos, :vel, :right, :up, :fwd, :grounded, :crashed, :steer, :surface,
              :air_time, :gear, :rpm, :skid, :contact_key, :contact_gate, :normal

  def initialize(world)
    @world = world
    reset(world.start_pos, world.start_fwd)
  end

  def reset(pos, fwd)
    @pos = pos.map(&:to_f)
    @vel = [0.0, 0.0, 0.0]
    @up = [0.0, 1.0, 0.0]
    @fwd = V.norm(fwd)
    @right = V.cross(@up, @fwd)
    @normal = [0.0, 1.0, 0.0]
    @grounded = true
    @air_time = 0.0
    @crashed = nil
    @steer = 0.0
    @surface = :road
    @skid = 0.0
    @gear = 1
    @rpm = 0.0
    @contact_key = nil
    @contact_gate = false
    @guide = nil
    self
  end

  def speed
    V.len(@vel)
  end

  def forward_speed
    V.dot(@vel, @fwd)
  end

  # Largest wheel angle at a speed: full lock when slow, less when fast.
  def self.max_steer(speed)
    return STEER_MAX if speed < 5.0

    [Math.atan(STEER_ACCEL * WHEELBASE / (speed * speed)), STEER_MAX].min
  end

  # throttle, brake: 0..1; steer: -1 (left) .. 1 (right).
  def step(dt, throttle, brake, steer)
    return if @crashed

    h = dt / SUBSTEPS
    SUBSTEPS.times do
      substep(h, throttle, brake, steer)
      break if @crashed
    end
    update_gear
  end

  private

  def substep(dt, thr, brk, st)
    drive(dt, thr, brk, st) if @grounded
    pre = @vel
    v = [pre[0], pre[1] - G * dt, pre[2]]
    sp = V.len(v)
    if sp > 1.0
      v = sweep(v, sp, dt)
      return if @crashed
    end
    @vel = v
    @pos = V.madd(@pos, v, dt)
    contact(pre, dt)
    return if @crashed

    collide_solids
    return if @crashed

    if @grounded
      @fwd = V.norm(V.madd(@fwd, @up, -V.dot(@fwd, @up)))
    else
      # in the air the nose follows the flight path
      s = V.len(@vel)
      @fwd = V.norm(V.lerp(@fwd, V.scale(@vel, 1.0 / s), [2.5 * dt, 1.0].min)) if s > 4.0
      @up = V.norm(V.madd(@up, @fwd, -V.dot(@up, @fwd)))
    end
    @right = V.cross(@up, @fwd)
  end

  def drive(dt, thr, brk, st)
    v = @vel
    f = @fwd
    r = @right
    vf = V.dot(v, f)
    target = st * Car.max_steer(vf.abs)
    d = target - @steer
    lim = STEER_RATE * dt
    @steer += d > lim ? lim : (d < -lim ? -lim : d)
    f, r = V.rotate_pair(f, r, vf * Math.tan(@steer) / WHEELBASE * dt)
    g = @guide
    if g && vf.abs > 3.0
      s = V.dot(f, g)
      if s.abs > 0.7
        # aim along the centre line and a little towards it
        want = V.scale(g, s > 0 ? 1.0 : -1.0)
        off = [@pos[0] - g[3], @pos[1] - g[4], @pos[2] - g[5]]
        off = V.madd(off, g, -V.dot(off, g))
        pull = D3D.clamp(V.len(off) * GUIDE_PULL / vf.abs, 0.0, 0.3)
        want = V.madd(want, V.norm(off), -pull) if pull > 1e-4
        want = V.madd(want, @up, -V.dot(want, @up))
        f2 = V.norm(V.lerp(f, V.norm(want), [GUIDE * dt, 1.0].min))
        r2 = V.cross(@up, f2)
        # like a rut, the road turns the car's motion along with its nose
        a = V.dot(v, f)
        b = V.dot(v, r)
        v = V.madd(V.madd(V.madd(V.madd(v, f, -a), r, -b), f2, a), r2, b)
        f = f2
        r = r2
      end
    end
    @fwd = f
    @right = r

    # tyres: no sideways motion up to the grip limit, beyond it the car slides
    vf = V.dot(v, f)
    vr = V.dot(v, r)
    grass = @surface == :grass
    md = (grass ? GRIP_GRASS : GRIP_ROAD) * dt
    if vr.abs <= md
      v = V.madd(v, r, -vr)
      @skid = 0.0
    else
      v = V.madd(v, r, vr > 0 ? -md : md)
      @skid = vr.abs
    end

    a = 0.0
    if thr > 0
      a += vf > -0.5 ? thr * ENGINE * [1.0 - vf / ENGINE_VMAX, 0.0].max : thr * BRAKE
    end
    if brk > 0
      if vf > 0.5
        a -= brk * BRAKE
      elsif vf > -REVERSE_MAX
        a -= brk * REVERSE_ACCEL
      end
    end
    vf2 = vf + a * dt
    res = (ROLL + DRAG * vf2 * vf2 + (grass ? GRASS_DRAG * vf2.abs : 0.0)) * dt
    vf2 = vf2.abs <= res ? 0.0 : vf2 - (vf2 > 0 ? res : -res)
    @vel = V.madd(v, f, vf2 - vf)
  end

  # Ray along the velocity: anything steep in the way (a wall, the back of
  # a ramp or loop) stops the car or wrecks it.
  def sweep(v, sp, dt)
    u = @up
    p = @pos
    dx = v[0] / sp
    dy = v[1] / sp
    dz = v[2] / sp
    hit = @world.raycast(p[0] + u[0] * 0.6, p[1] + u[1] * 0.6, p[2] + u[2] * 0.6,
                         dx, dy, dz, sp * dt + 1.8, false)
    return v unless hit

    t = hit[1]
    n = [t[9], t[10], t[11]]
    nd = n[0] * dx + n[1] * dy + n[2] * dz
    # a surface the wheels can land on is handled by contact
    return v if (nd < 0 && V.dot(n, u) > 0.5) || nd.abs < 0.5

    if sp * nd.abs > CRASH_WALL
      crash(:wall)
      return v
    end
    V.madd(v, n, -V.dot(v, n))
  end

  # Finds the surface under the wheels and settles the car onto it.
  def contact(pre, dt)
    u = @up
    p = @pos
    v = @vel
    was = @grounded
    ox = p[0] + u[0] * RAY_UP
    oy = p[1] + u[1] * RAY_UP
    oz = p[2] + u[2] * RAY_UP
    reach = RAY_UP + 0.6
    hit = @world.raycast(ox, oy, oz, -u[0], -u[1], -u[2], reach, true)
    t = nil
    n = nil
    smooth = nil
    surface = :grass
    key = nil
    gate = false
    guide = nil
    if hit
      tri = hit[1]
      n = [tri[9], tri[10], tri[11]]
      if V.dot(n, u) > 0.3
        t = hit[0]
        b = hit[2]
        c = hit[3]
        a = 1.0 - b - c
        smooth = V.norm([tri[12] * a + tri[15] * b + tri[18] * c,
                         tri[13] * a + tri[16] * b + tri[19] * c,
                         tri[14] * a + tri[17] * b + tri[20] * c])
        surface = tri[21]
        key = tri[22]
        gate = tri[23]
        guide = tri[24]
      end
    end
    if u[1] > 0.3
      tg = oy / u[1] # distance to the ground plane y = 0
      if tg <= reach && (t.nil? || tg < t - 0.02)
        t = tg
        n = UP
        smooth = UP
        surface = :grass
        key = nil
        gate = false
        guide = nil
      end
    end

    touching = false
    if t
      gap = t - RAY_UP
      vn = V.dot(v, n)
      # Gravity only holds the car on a surface that faces upwards; on a
      # wall or ceiling the contact has to come from the car's own motion.
      touching = gap <= 0.0 || (gap <= SKIN && vn <= 0.6 * n[1])
    end
    body = false
    unless touching
      # no wheels on anything: did the body hit the ground?
      low = [p[1], p[1] + u[1] * 1.3].min
      if low < 0.0
        return crash(:roof) if u[1] < 0.55

        @pos = [p[0], 0.0, p[2]]
        touching = true
        body = true
        n = UP
        smooth = UP
        surface = :grass
        key = nil
        gate = false
        guide = nil
        vn = v[1]
      end
    end

    unless touching
      @grounded = false
      @air_time += dt
      @contact_key = nil
      @contact_gate = false
      @guide = nil
      @skid = 0.0
      return
    end

    if !was && @air_time > 0.12 && (-vn > CRASH_LAND || V.dot(u, n) < 0.55)
      return crash(:landing)
    end

    @pos = [ox - u[0] * t, oy - u[1] * t, oz - u[2] * t] unless body
    vt = V.madd(v, n, -vn)
    if was
      # Following a bend in the road must not cost speed: undo what the
      # projection onto the new plane took from the velocity before gravity.
      lp = V.len(pre)
      if lp > 0.5
        lt = V.len(V.madd(pre, n, -V.dot(pre, n)))
        vt = V.scale(vt, lp / lt) if lt > 1e-6 && lp / lt < 1.12
      end
    end
    @vel = vt
    @normal = n
    @grounded = true
    @air_time = 0.0
    @surface = surface
    @contact_key = key
    @contact_gate = gate
    @guide = guide
    @up = V.norm(V.lerp(u, smooth, 0.5))
  end

  def collide_solids
    list = @world.solids_at(@pos[0], @pos[2])
    return if list.empty?

    [1.0, -1.0].each do |k|
      c = V.madd(V.madd(@pos, @up, 0.75), @fwd, k)
      list.each do |b|
        qx = c[0] < b[0] ? b[0] : (c[0] > b[3] ? b[3] : c[0])
        qy = c[1] < b[1] ? b[1] : (c[1] > b[4] ? b[4] : c[1])
        qz = c[2] < b[2] ? b[2] : (c[2] > b[5] ? b[5] : c[2])
        d = [c[0] - qx, c[1] - qy, c[2] - qz]
        d2 = V.dot(d, d)
        next if d2 >= 0.81

        if d2 > 1e-8
          dist = Math.sqrt(d2)
          n = V.scale(d, 1.0 / dist)
        else
          # centre inside the box: push back against the motion
          dist = 0.0
          n = V.norm([-@vel[0], 0.0, -@vel[2]])
        end
        closing = -V.dot(@vel, n)
        return crash(:wall) if closing > CRASH_WALL

        @pos = V.madd(@pos, n, 0.9 - dist)
        @vel = V.madd(@vel, n, closing) if closing > 0
        c = V.madd(c, n, 0.9 - dist)
      end
    end
  end

  def crash(reason)
    @crashed = reason
    @grounded = false
    nil
  end

  def update_gear
    s = forward_speed.abs
    g = @gear
    g += 1 while g < 5 && s > GEARS[g] * 0.94
    g -= 1 while g > 1 && s < GEARS[g - 1] * 0.8
    @gear = g
    lo = g > 1 ? GEARS[g - 1] * 0.7 : 0.0
    @rpm = D3D.clamp((s - lo) / (GEARS[g] - lo), 0.0, 1.0)
  end
end
