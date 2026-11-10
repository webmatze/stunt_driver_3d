# One timed run on a world: countdown, clock, the order in which the parts
# of the route have to be driven, the finish and the crash.
class Race
  V = D3D::V
  COUNTDOWN = 3.0

  attr_reader :world, :car, :state, :time, :countdown, :next_cp, :missed

  def initialize(world, countdown: COUNTDOWN)
    @world = world
    @car = Car.new(world)
    @keys = world.keys
    @state = countdown > 0 ? :countdown : :running
    @countdown = countdown
    @time = 0.0
    @next_cp = 1
    @missed = false
  end

  def total_cps
    @keys.size
  end

  # Centre of the tile that has to be driven next.
  def next_cp_pos
    k = @keys[@next_cp % @keys.size]
    i, j = @world.track.coords(k)
    piece = @world.track.at(i, j)
    cx, cz = World.center(piece[0], piece[1], piece[2], piece[3])
    [cx, 0.0, cz]
  end

  # Advances the race by dt. Returns :go, :checkpoint, :finish or :crash
  # when that happened in this step, else nil.
  def update(dt, throttle, brake, steer)
    case @state
    when :countdown
      @countdown -= dt
      # no brake here: held at standstill it is the reverse gear
      @car.step(dt, 0.0, 0.0, steer)
      return nil if @countdown > 0

      @state = :running
      return :go
    when :running
      @time += dt
      @car.step(dt, throttle, brake, steer)
      if @car.crashed
        @state = :crashed
        return :crash
      end
      return track_progress
    when :finished
      @car.step(dt, 0.0, @car.forward_speed > 0.5 ? 0.6 : 0.0, 0.0)
    end
    nil
  end

  private

  def track_progress
    car = @car
    n = @keys.size
    if @next_cp >= n
      # every part driven: the run ends on the start line
      rel = V.sub(car.pos, @world.start_center)
      along = V.dot(rel, @world.start_fwd)
      side = rel[0] * @world.start_fwd[2] - rel[2] * @world.start_fwd[0]
      if along >= 0.0 && along < 15.0 && side.abs < 15.0
        @state = :finished
        return :finish
      end
      return nil
    end
    key = car.contact_key
    return nil unless key && car.contact_gate

    if key == @keys[@next_cp]
      @next_cp += 1
      @missed = false
      return :checkpoint
    end
    (1..3).each do |k|
      @missed = true if @next_cp + k < n && key == @keys[@next_cp + k]
    end
    nil
  end
end
