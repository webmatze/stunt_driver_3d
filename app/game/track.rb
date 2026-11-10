# A course: pieces placed on a SIZE x SIZE grid of tiles. Knows how to
# place and remove pieces, save and load itself as text and follow the road
# from the start line to check that it forms a closed circuit.
class Track
  SIZE = 20
  DX = Pieces::DX
  DZ = Pieces::DZ
  MAX_GAP = 2 # empty tiles a jump may cross

  attr_accessor :name
  attr_reader :cells # anchor key => [piece id, rot]

  def initialize(name = 'Neue Strecke')
    @name = name
    @cells = {}
    @occ = {} # cell key => anchor key
  end

  def key(i, j)
    i + j * SIZE
  end

  def coords(key)
    i = key % SIZE
    [i, ((key - i) / SIZE).to_i]
  end

  def in_bounds?(i, j)
    i >= 0 && j >= 0 && i < SIZE && j < SIZE
  end

  def empty?
    @cells.empty?
  end

  # Places a piece with its anchor (lowest i/j corner) at i, j, replacing
  # whatever is in the way. Returns false when it doesn't fit on the grid.
  def place(i, j, id, rot)
    fw, fd = Pieces.footprint(id, rot)
    return false unless in_bounds?(i, j) && in_bounds?(i + fw - 1, j + fd - 1)

    fw.times { |a| fd.times { |b| remove(i + a, j + b) } }
    k = key(i, j)
    @cells[k] = [id, rot]
    fw.times { |a| fd.times { |b| @occ[key(i + a, j + b)] = k } }
    true
  end

  def remove(i, j)
    return false unless in_bounds?(i, j)

    k = @occ[key(i, j)]
    return false unless k

    @cells.delete(k)
    @occ.delete_if { |_, v| v == k }
    true
  end

  # [anchor_i, anchor_j, id, rot] of the piece covering a cell, or nil.
  def at(i, j)
    return nil unless in_bounds?(i, j)

    k = @occ[key(i, j)]
    return nil unless k

    id, rot = @cells[k]
    ai, aj = coords(k)
    [ai, aj, id, rot]
  end

  # ---------------------------------------------------------------- text

  def serialize
    lines = ["name=#{@name}"]
    @cells.keys.sort.each do |k|
      i, j = coords(k)
      id, rot = @cells[k]
      lines << "#{i} #{j} #{id} #{rot}"
    end
    lines.join("\n") + "\n"
  end

  def self.parse(text)
    track = Track.new
    text.to_s.split("\n").each do |line|
      line = line.strip
      if line.start_with?('name=')
        track.name = line[5..-1]
        next
      end
      i, j, id, rot = line.split(' ')
      next unless rot && Pieces::DEFS[id.to_sym]

      track.place(i.to_i, j.to_i, id.to_sym, rot.to_i % 4)
    end
    track
  end

  def dup
    Track.parse(serialize)
  end

  # ---------------------------------------------------------------- route

  # Follows the road from the start line. Returns
  #   { ok: true, steps: [[ai, aj, id, rot, conn_in, conn_out, gap], ...] }
  # (gap: empty tiles jumped over after the step) or
  #   { ok: false, error: 'text', cell: [i, j] or nil, steps: [...] }.
  def route
    starts = @cells.keys.select { |k| @cells[k][0] == :start }
    return fail_route('Kein Start/Ziel gesetzt', nil, []) if starts.empty?
    return fail_route('Nur ein Start/Ziel erlaubt', coords(starts[1]), []) if starts.size > 1

    start = starts[0]
    steps = []
    k = start
    cin = 0
    loop do
      id, rot = @cells[k]
      ai, aj = coords(k)
      cout = Pieces::DEFS[id].links[cin]
      di, dj, dir, lvl = Pieces.conns(id, rot)[cout]
      step = [ai, aj, id, rot, cin, cout, 0]
      steps << step
      return fail_route('Strecke ist zu lang', [ai, aj], steps) if steps.size > SIZE * SIZE * 2

      ci = ai + di
      cj = aj + dj
      back = (dir + 2) % 4
      found = nil
      reach = lvl == :jump ? MAX_GAP + 1 : 1
      (1..reach).each do |n|
        found = find_conn(ci + DX[dir] * n, cj + DZ[dir] * n, back, lvl)
        next unless found

        step[6] = n - 1
        break
      end
      unless found
        msg = lvl == :jump ? 'Sprung ohne Landung' : 'Strecke endet hier'
        return fail_route(msg, [ci + DX[dir], cj + DZ[dir]], steps)
      end
      k, cin = found
      break if k == start
    end
    return fail_route('Strecke ist zu kurz', coords(start), steps) if steps.size < 4

    { ok: true, steps: steps }
  end

  private

  def fail_route(error, cell, steps)
    { ok: false, error: error, cell: cell, steps: steps }
  end

  # [anchor key, connector index] of a connector on cell i, j facing dir.
  def find_conn(i, j, dir, lvl)
    piece = at(i, j)
    return nil unless piece

    ai, aj, id, rot = piece
    Pieces.conns(id, rot).each_with_index do |c, n|
      return [key(ai, aj), n] if ai + c[0] == i && aj + c[1] == j && c[2] == dir && c[3] == lvl
    end
    nil
  end
end
