# Tests of the game logic that runs without DragonRuby:
#   ruby tests/game_test.rb
require 'minitest/autorun'
require_relative 'helper'

class PiecesTest < Minitest::Test
  def test_every_piece_builds_geometry
    Pieces::ORDER.each do |id|
      b = PieceBuilder.new(1, 0, 0.0, 0.0)
      Pieces::DEFS[id].build.call(b)
      b.finish
      assert b.geo.tri_count + b.ground.tri_count > 0, "#{id} has no triangles"
      next if Pieces::DEFS[id].scenery

      assert b.cols.size > 0, "#{id} has no road surface"
    end
  end

  def test_connectors_stay_on_the_footprint_and_face_outwards
    Pieces::ORDER.each do |id|
      4.times do |rot|
        fw, fd = Pieces.footprint(id, rot)
        Pieces.conns(id, rot).each do |di, dj, dir, _lvl|
          assert (0...fw).cover?(di) && (0...fd).cover?(dj), "#{id} rot #{rot}"
          ni = di + Pieces::DX[dir]
          nj = dj + Pieces::DZ[dir]
          refute (0...fw).cover?(ni) && (0...fd).cover?(nj), "#{id} rot #{rot} faces inwards"
        end
      end
    end
  end

  def test_centre_lines_start_and_end_on_their_connectors
    Pieces::ORDER.each do |id|
      piece = Pieces::DEFS[id]
      next if piece.scenery

      piece.paths.call.each do |(a, b), pts|
        [[a, pts.first], [b, pts.last]].each do |c, p|
          ci, cj, dir, = piece.conns[c]
          x = (ci + 0.5 - piece.w / 2.0 + Pieces::DX[dir] * 0.5) * Pieces::T
          z = (cj + 0.5 - piece.d / 2.0 + Pieces::DZ[dir] * 0.5) * Pieces::T
          assert_in_delta x, p[0], 0.01, "#{id} connector #{c}"
          assert_in_delta z, p[2], 0.01, "#{id} connector #{c}"
        end
      end
    end
  end
end

class TrackTest < Minitest::Test
  def test_multi_tile_pieces_occupy_and_free_all_their_tiles
    t = Track.new
    assert t.place(4, 4, :wide_curve, 1)
    assert_equal [4, 4, :wide_curve, 1], t.at(5, 5)
    assert t.place(5, 5, :straight, 0)
    assert_nil t.at(4, 4)
    assert_equal [5, 5, :straight, 0], t.at(5, 5)
    refute t.place(Track::SIZE - 1, 0, :wide_curve, 0)
    assert t.remove(5, 5)
    assert t.empty?
  end

  def test_text_round_trip
    BuiltinTracks.all.each do |t|
      copy = Track.parse(t.serialize)
      assert_equal t.name, copy.name
      assert_equal t.cells, copy.cells
    end
  end

  def test_builtin_tracks_are_closed_circuits
    BuiltinTracks.all.each do |t|
      r = t.route
      assert r[:ok], "#{t.name}: #{r[:error]} at #{r[:cell].inspect}"
    end
  end

  def test_route_errors
    t = Track.new
    assert_equal 'Kein Start/Ziel gesetzt', t.route[:error]
    t.place(5, 5, :start, 0)
    t.place(5, 6, :straight, 0)
    r = t.route
    refute r[:ok]
    assert_equal 'Strecke endet hier', r[:error]
    assert_equal [5, 7], r[:cell]
    t.place(5, 7, :jump, 0)
    assert_equal 'Sprung ohne Landung', t.route[:error]
    t.place(8, 8, :start, 0)
    assert_equal 'Nur ein Start/Ziel erlaubt', t.route[:error]
  end

  def test_levels_must_match
    t = Track.new
    t.place(5, 5, :start, 0)
    t.place(5, 6, :elevated, 0)
    assert_equal 'Strecke endet hier', t.route[:error]
  end

  def test_jump_gap_is_recorded
    r = BuiltinTracks.stuntpark.route
    jump = r[:steps].find { |s| s[2] == :jump && s[4] == 0 }
    assert_equal 1, jump[6]
  end
end

class WorldTest < Minitest::Test
  def test_path_is_continuous_apart_from_jumps
    BuiltinTracks.all.each do |t|
      w = World.new(t)
      n = w.path.size
      long = (0...n).count { |i| D3D::V.dist(w.path[i], w.path[(i + 1) % n]) > 16.0 }
      jumps = w.route[:steps].count { |s| s[6] > 0 }
      assert_equal jumps, long, t.name
    end
  end

  def test_raycast_finds_the_road
    w = World.new(BuiltinTracks.oval)
    p = w.start_pos
    hit = w.raycast(p[0], 1.0, p[2], 0.0, -1.0, 0.0, 2.0, true)
    assert hit
    assert_in_delta 1.0, hit[0], 1e-6
    assert_equal :road, hit[1][21]
    assert_nil w.raycast(p[0] + 10.0, 1.0, p[2], 0.0, -1.0, 0.0, 2.0, true)
  end
end

class CarTest < Minitest::Test
  DT = 1.0 / 60

  def loop_track
    BuiltinTracks.build('Loop', 5, 2, 0, %i[start s s s s loop s s s])
  end

  # Full throttle (or the given inputs); a block caps the speed instead.
  def drive(car, seconds, thr = 1.0, brk = 0.0, steer = 0.0, max_speed: nil)
    (seconds * 60).to_i.times do
      t = max_speed && car.forward_speed > max_speed ? 0.0 : thr
      car.step(DT, t, brk, steer)
      yield car if block_given?
      break if car.crashed
    end
    car
  end

  def test_stays_put_without_input
    car = Car.new(World.new(BuiltinTracks.oval))
    start = car.pos.dup
    drive(car, 2.0, 0.0)
    assert_in_delta 0.0, D3D::V.dist(start, car.pos), 1e-6
    assert car.grounded
  end

  def test_accelerates_brakes_and_reverses
    car = Car.new(World.new(BuiltinTracks.oval))
    drive(car, 3.0)
    assert car.forward_speed > 20
    assert_equal :road, car.surface
    drive(car, 3.0, 0.0, 1.0)
    assert car.forward_speed < 0, 'brake held at standstill reverses'
    assert car.forward_speed >= -Car::REVERSE_MAX - 0.5
  end

  def test_grass_is_slow
    car = Car.new(World.new(Track.new))
    drive(car, 12.0)
    assert_equal :grass, car.surface
    assert car.forward_speed < 20
  end

  def test_fast_car_makes_the_loop
    car = Car.new(World.new(loop_track))
    top = 0.0
    drive(car, 9.0) { |c| top = [top, c.pos[1]].max }
    assert_nil car.crashed
    assert_in_delta 2 * Pieces::LOOP_R, top, 0.3
    assert car.pos[2] > 8 * 30.0, 'left the loop on the far side'
  end

  def test_loop_guides_a_car_that_enters_off_centre
    world = World.new(loop_track)
    [-2.5, 1.5].each do |off|
      [26.0, 60.0].each do |cap|
        car = Car.new(world)
        car.reset([world.start_pos[0] + off, 0.0, world.start_pos[2]], [0.0, 0.0, 1.0])
        top = 0.0
        drive(car, 12.0, max_speed: cap) { |c| top = [top, c.pos[1]].max }
        assert_nil car.crashed, "offset #{off} at #{cap} m/s"
        assert top > 17.0, "offset #{off} at #{cap} m/s went around the loop"
      end
    end
  end

  def test_slow_car_falls_out_of_the_loop
    car = Car.new(World.new(loop_track))
    drive(car, 40.0, max_speed: 17.0)
    assert car.crashed
  end

  def test_hitting_a_pillar_fast_is_a_crash
    t = Track.new
    t.place(5, 5, :start, 0)
    t.place(5, 7, :elevated, 0) # its pillars stand in the car's way
    car = Car.new(World.new(t))
    drive(car, 6.0)
    assert_equal :wall, car.crashed
  end

  def test_jump_clears_the_gap_only_when_fast_enough
    t = BuiltinTracks.build('Jump', 5, 1, 0, [:start, :s, :s, :s, :s, :jump, [:gap, 1], :land, :s, :s])
    fast = Car.new(World.new(t))
    drive(fast, 9.0)
    assert_nil fast.crashed
    assert fast.pos[2] > 9 * 30.0

    slow = Car.new(World.new(t))
    drive(slow, 30.0, max_speed: 20.0)
    assert slow.crashed || slow.pos[2] < 8 * 30.0, 'a slow car does not reach the landing ramp'
  end
end

class RaceTest < Minitest::Test
  def test_autopilot_finishes_every_builtin_track
    BuiltinTracks.all.each do |t|
      race = TestHelper.autodrive(t)
      assert_equal :finished, race.state, "#{t.name}: #{race.car.crashed.inspect} at #{race.next_cp}/#{race.total_cps}"
      assert race.time < 90
    end
  end

  def test_parts_have_to_be_driven_in_order
    world = World.new(BuiltinTracks.oval)
    race = Race.new(world, countdown: 0.0)
    # reverse over the start line straight away: not a finish
    200.times { race.update(1.0 / 60, 0.0, 1.0, 0.0) }
    assert_equal :running, race.state
    assert_equal 1, race.next_cp
  end

  def test_car_stops_after_the_finish_instead_of_reversing
    race = TestHelper.autodrive(BuiltinTracks.oval)
    assert_equal :finished, race.state
    600.times { race.update(1.0 / 60, 0.0, 0.0, 0.0) }
    assert_in_delta 0.0, race.car.forward_speed, 0.6
  end

  def test_countdown_holds_the_car
    race = Race.new(World.new(BuiltinTracks.oval))
    start = race.car.pos.dup
    170.times { race.update(1.0 / 60, 1.0, 1.0, 0.0) }
    assert_equal :countdown, race.state
    assert_in_delta 0.0, D3D::V.dist(start, race.car.pos), 1e-6, 'car waits on the spot'
    events = (0...30).map { race.update(1.0 / 60, 1.0, 0.0, 0.0) }
    assert_includes events, :go
    assert_equal :running, race.state
    assert D3D::V.dist(start, race.car.pos) > 0.1
    assert race.time < 0.4
  end
end
