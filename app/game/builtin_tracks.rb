# The tracks that ship with the game, written as driving directions: a
# "turtle" starts on a tile, lays the named piece, moves to the piece's
# exit and continues there.
module BuiltinTracks
  DX = Pieces::DX
  DZ = Pieces::DZ

  # command => [piece, connector the turtle enters through]
  CMDS = {
    start: [:start, 0], s: [:straight, 0], r: [:curve, 0], l: [:curve, 1],
    wr: [:wide_curve, 0], wl: [:wide_curve, 1], x: [:cross, 0],
    up: [:ramp, 0], dn: [:ramp, 1], e: [:elevated, 0], er: [:elevated_curve, 0],
    el: [:elevated_curve, 1], over: [:bridge, 0], under: [:bridge, 2],
    jump: [:jump, 0], land: [:jump, 1], loop: [:loop, 0], tun: [:tunnel, 0], ob: [:obstacle, 0]
  }.freeze

  # program: commands; :pass drives through a piece that is already there
  # (crossing, bridge), [:gap, n] leaves n tiles empty (after a jump).
  # scenery: [[i, j, id, rot], ...]
  def self.build(name, i, j, heading, program, scenery = [])
    track = Track.new(name)
    program.each do |cmd|
      if cmd.is_a?(Array)
        i += DX[heading] * cmd[1]
        j += DZ[heading] * cmd[1]
        next
      end
      back = (heading + 2) % 4
      if cmd == :pass
        ai, aj, id, rot = track.at(i, j)
        conns = Pieces.conns(id, rot)
        cin = conns.index { |c| ai + c[0] == i && aj + c[1] == j && c[2] == back }
      else
        id, cin = CMDS[cmd]
        raise "unknown command #{cmd}" unless id

        rot = (0..3).find { |r| Pieces.conns(id, r)[cin][2] == back }
        conns = Pieces.conns(id, rot)
        ai = i - conns[cin][0]
        aj = j - conns[cin][1]
        raise "#{name}: #{cmd} does not fit at #{i},#{j}" unless track.place(ai, aj, id, rot)
      end
      out = conns[Pieces::DEFS[id].links[cin]]
      heading = out[2]
      i = ai + out[0] + DX[heading]
      j = aj + out[1] + DZ[heading]
    end
    scenery.each { |si, sj, id, rot| track.place(si, sj, id, rot || 0) unless track.at(si, sj) }
    track
  end

  def self.all
    @all ||= [oval, stuntpark, eight]
  end

  def self.oval
    build('Rundkurs', 3, 3, 0,
          %i[start s s s s s s s s wr s s ob s s s s wr s s s r l s s l r s s wr
             s s s s s s s wr],
          [[2, 6, :tribune, 1], [5, 9, :trees, 0], [6, 11, :trees, 1], [8, 8, :house, 0],
           [1, 12, :trees, 2], [9, 15, :trees, 0], [14, 7, :house, 1], [7, 3, :trees, 3],
           [10, 4, :trees, 0], [15, 11, :trees, 1]])
  end

  def self.stuntpark
    build('Stuntpark', 3, 4, 0,
          [:start, :s, :s, :loop, :s, :s, :wr, :s, :s, :s, :s, :jump, [:gap, 1], :land, :s, :wr,
           :s, :up, :e, :e, :er, :e, :dn, :l, :tun, :s, :r, :s, :s, :s, :s, :s, :s, :wr],
          [[2, 5, :tribune, 1], [5, 8, :trees, 0], [10, 12, :trees, 1], [10, 10, :house, 0],
           [8, 6, :trees, 2], [12, 8, :trees, 3], [16, 7, :trees, 0], [7, 4, :house, 2],
           [13, 3, :trees, 1], [1, 9, :trees, 0]])
  end

  def self.eight
    build('Achterbahn', 3, 4, 0,
          [:start, :s, :s, :up, :over, :dn, :s, :wr, :s, :s, :jump, [:gap, 1], :land, :s, :wr,
           :loop, :s, :r, :s, :s, :tun, :s, :ob, :s, :s, :s, :pass, :l, :s, :s, :s, :s, :l, :l],
          [[4, 6, :tribune, 3], [6, 10, :trees, 0], [8, 10, :house, 0], [1, 10, :trees, 1],
           [9, 6, :trees, 2], [14, 9, :trees, 3], [6, 14, :trees, 0], [13, 13, :house, 1],
           [5, 5, :trees, 1], [10, 13, :trees, 2]])
  end
end
