# Drives a car along the centre line of the route (pure pursuit steering,
# braking for the speed hints of the pieces ahead). Used for the demo in
# the menu and by the tests to prove that a track can be driven.
class Autopilot
  V = D3D::V
  BRAKE = 13.0

  def initialize(car, world)
    @car = car
    @path = world.path
    @speeds = world.path_speed
    @i = 0
  end

  # Returns [throttle, brake, steer].
  def control
    car = @car
    pos = car.pos
    n = @path.size
    best = @i
    bd = 1e18
    14.times do |k|
      j = (@i + k) % n
      d = V.dist2(@path[j], pos)
      next unless d < bd

      bd = d
      best = j
    end
    @i = best

    v = car.forward_speed
    look = 5.0 + v.abs * 0.28
    dist = 0.0
    allowed = @speeds[@i]
    j = @i
    target = nil
    60.times do
      k = (j + 1) % n
      dist += V.dist(@path[j], @path[k])
      j = k
      target ||= @path[j] if dist >= look
      lim = Math.sqrt(@speeds[j]**2 + 2 * BRAKE * dist)
      allowed = lim if lim < allowed
      break if dist > 130.0
    end
    target ||= @path[j]

    to = V.sub(target, pos)
    x = V.dot(to, car.right)
    z = V.dot(to, car.fwd)
    d2 = x * x + z * z
    angle = d2 > 1e-6 ? Math.atan(2 * Car::WHEELBASE * x / d2) : 0.0
    steer = D3D.clamp(angle / Car.max_steer(v.abs), -1.0, 1.0)
    throttle = v < allowed - 0.5 ? 1.0 : 0.0
    brake = v > allowed + 1.5 ? 1.0 : 0.0
    [throttle, brake, steer]
  end
end
