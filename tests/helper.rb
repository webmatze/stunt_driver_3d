# Loads the engine and the game logic (everything that doesn't need
# DragonRuby) into plain Ruby for the tests.
ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(ROOT)
require 'app/d3d/d3d.rb'
%w[geo pieces track world car autopilot race builtin_tracks].each { |f| require "app/game/#{f}.rb" }

module TestHelper
  def self.ascii(track)
    rows = (0...Track::SIZE).map do |j|
      (0...Track::SIZE).map do |i|
        p = track.at(i, j)
        p ? p[2].to_s[0, 2] : ' .'
      end.join(' ')
    end
    rows.reverse.join("\n")
  end

  # Runs the autopilot for at most `seconds`. Returns the Race.
  def self.autodrive(track, seconds = 400.0, log: false)
    world = World.new(track)
    raise "route: #{world.route[:error]} at #{world.route[:cell].inspect}" unless world.ok?

    race = Race.new(world, countdown: 0.0)
    pilot = Autopilot.new(race.car, world)
    dt = 1.0 / 60
    (seconds * 60).to_i.times do |n|
      thr, brk, st = pilot.control
      ev = race.update(dt, thr, brk, st)
      if log && (n % 30 == 0 || ev)
        c = race.car
        puts format('%6.2f cp %2d/%2d pos %7.1f %5.1f %7.1f v %5.1f %s %s %s', race.time, race.next_cp,
                    race.total_cps, c.pos[0], c.pos[1], c.pos[2], c.forward_speed,
                    c.grounded ? 'gnd' : 'AIR', c.surface, ev)
      end
      break if race.state != :running
    end
    race
  end
end
