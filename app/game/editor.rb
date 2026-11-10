# The track editor: a top-down map of the tile grid on the left, the
# available pieces on the right. Pieces are placed with the mouse (or the
# keyboard cursor) and the route is checked after every change.
class Editor
  MX = 24
  MY = 40
  CELL = 32
  MAP = CELL * Track::SIZE
  PX = 694
  ICON = 60
  SLOT_W = 142
  SLOT_H = 92
  PAL_TOP = 628
  COLS = 4

  attr_reader :track, :world, :changed

  def initialize(track, hud)
    @track = track
    @hud = hud
    @sel = 0
    @rot = 0
    @cur = [Track::SIZE / 2, Track::SIZE / 2].map(&:to_i)
    @changed = false
    @palette_ready = false
    @last_paint = nil
    rebuild
  end

  def mark_saved
    @changed = false
  end

  # Returns :menu, :test or :save when asked for, else nil.
  def tick(args)
    result = input(args)
    draw(args)
    result
  end

  private

  def rebuild
    @world = World.new(@track)
    @map_dirty = true
  end

  def selected
    Pieces::ORDER[@sel]
  end

  def input(args)
    kb = args.inputs.keyboard
    down = kb.key_down
    mouse = args.inputs.mouse
    return :menu if down.escape
    return :test if down.t || down.enter
    return :save if down.s

    n = Pieces::ORDER.size
    @rot = (@rot + 1) % 4 if down.r
    if mouse.wheel
      @rot = (@rot + (mouse.wheel.y > 0 ? 1 : 3)) % 4
    end
    @sel = (@sel + (kb.key_held.shift ? n - 1 : 1)) % n if down.tab
    @sel = (@sel + 1) % n if down.e
    @sel = (@sel + n - 1) % n if down.q
    @cur[0] = D3D.clamp(@cur[0] + 1, 0, Track::SIZE - 1) if down.right
    @cur[0] = D3D.clamp(@cur[0] - 1, 0, Track::SIZE - 1) if down.left
    @cur[1] = D3D.clamp(@cur[1] + 1, 0, Track::SIZE - 1) if down.up
    @cur[1] = D3D.clamp(@cur[1] - 1, 0, Track::SIZE - 1) if down.down

    over_map = mouse.x >= MX && mouse.x < MX + MAP && mouse.y >= MY && mouse.y < MY + MAP
    if over_map && (mouse.moved || mouse.button_left || mouse.button_right)
      @cur = [((mouse.x - MX) / CELL).floor, ((mouse.y - MY) / CELL).floor]
    end
    if mouse.click && !over_map
      idx = palette_index(mouse.x, mouse.y)
      @sel = idx if idx
    end

    @last_paint = nil unless mouse.button_left
    if down.space || (over_map && mouse.button_left)
      paint = [@cur[0], @cur[1], @sel, @rot]
      if paint != @last_paint
        @last_paint = paint
        place
      end
    end
    if down.x || down.backspace || down.delete || (over_map && mouse.button_right)
      if @track.remove(@cur[0], @cur[1])
        @changed = true
        rebuild
      end
    end
    nil
  end

  def place
    i, j = @cur
    old = @track.at(i, j)
    return if old && old == [i, j, selected, @rot]
    return unless @track.place(i, j, selected, @rot)

    @changed = true
    rebuild
  end

  def palette_index(x, y)
    col = ((x - PX) / SLOT_W).floor
    row = ((PAL_TOP - y) / SLOT_H).floor
    return nil if col < 0 || col >= COLS || row < 0

    idx = row * COLS + col
    idx < Pieces::ORDER.size ? idx : nil
  end

  # ---------------------------------------------------------------- drawing

  def render_palette(args)
    rt = args.outputs[:palette]
    rt.w = ICON * Pieces::ORDER.size
    rt.h = ICON
    rt.background_color = [0, 0, 0, 0]
    Pieces::ORDER.each_with_index do |id, n|
      piece = Pieces::DEFS[id]
      b = PieceBuilder.new(0, 0, 0.0, 0.0)
      piece.build.call(b)
      scale = (ICON - 6) / ([piece.w, piece.d].max * World::T)
      rt.sprites << MapView.prims([b.ground], [b.geo], scale, (n + 0.5) * ICON, ICON / 2.0)
    end
    @palette_ready = true
  end

  def render_map(args)
    MapView.render_world(args, :editor_map, @world, MAP, [98, 166, 76, 255], [255, 232, 90])
    rt = args.outputs[:editor_map]
    (0..Track::SIZE).each do |n|
      v = [n * CELL, MAP - 1].min
      rt.lines << { x: v, y: 0, x2: v, y2: MAP, r: 40, g: 90, b: 40, a: 110 }
      rt.lines << { x: 0, y: v, x2: MAP, y2: v, r: 40, g: 90, b: 40, a: 110 }
    end
    @map_dirty = false
  end

  def draw(args)
    render_palette(args) unless @palette_ready
    render_map(args) if @map_dirty
    hud = @hud
    out = args.outputs.sprites
    hud.rect(args, 0, 0, 1280, 720, [24, 30, 40])
    hud.text(args, MX, 700, "Strecken-Editor:  #{@track.name}", 26, Hud::YELLOW)
    out << { x: MX, y: MY, w: MAP, h: MAP, path: :editor_map }

    route = @world.route
    if route[:ok]
      hud.text(args, MX, 20, "Strecke geschlossen, #{route[:steps].size} Abschnitte.  T = Probefahrt", 20, Hud::GREEN)
    else
      hud.text(args, MX, 20, "Nicht fahrbar: #{route[:error]}", 20, Hud::RED)
      cell = route[:cell]
      if cell && @track.in_bounds?(cell[0], cell[1])
        args.outputs.borders << { x: MX + cell[0] * CELL, y: MY + cell[1] * CELL, w: CELL, h: CELL,
                                  r: 255, g: 60, b: 40 }
        args.outputs.borders << { x: MX + cell[0] * CELL + 1, y: MY + cell[1] * CELL + 1, w: CELL - 2,
                                  h: CELL - 2, r: 255, g: 60, b: 40 }
      end
    end

    draw_ghost(args)
    draw_palette(args)

    y = 236
    ['Linke Maustaste / Leertaste: Teil setzen',
     'Rechte Maustaste / X: Teil entfernen',
     'R / Mausrad: drehen     Q / E: Teil wählen',
     'Pfeiltasten: Cursor bewegen',
     'T: Probefahrt     S: speichern     ESC: Menü',
     '',
     'Die Strecke muss vom Start/Ziel aus einen',
     'geschlossenen Kurs bilden. Schanzen brauchen',
     'eine zweite Schanze als Landung (max. 2 Felder Lücke).'].each do |line|
      hud.text(args, PX, y, line, 18, [206, 214, 226])
      y -= 24
    end
  end

  def draw_ghost(args)
    i, j = @cur
    id = selected
    fw, fd = Pieces.footprint(id, @rot)
    ok = @track.in_bounds?(i, j) && @track.in_bounds?(i + fw - 1, j + fd - 1)
    x = MX + i * CELL
    y = MY + j * CELL
    piece = Pieces::DEFS[id]
    size = [piece.w, piece.d].max * CELL * ICON / (ICON - 6.0)
    if ok
      args.outputs.sprites << { x: x + fw * CELL / 2.0 - size / 2, y: y + fd * CELL / 2.0 - size / 2,
                                w: size, h: size, path: :palette, source_x: @sel * ICON, source_y: 0,
                                source_w: ICON, source_h: ICON, angle: -90 * @rot, a: 170 }
    end
    c = ok ? [255, 255, 255] : [255, 60, 40]
    args.outputs.borders << { x: x, y: y, w: fw * CELL, h: fd * CELL, r: c[0], g: c[1], b: c[2] }
  end

  def draw_palette(args)
    hud = @hud
    Pieces::ORDER.each_with_index do |id, n|
      col = n % COLS
      row = ((n - col) / COLS).to_i
      x = PX + col * SLOT_W
      top = PAL_TOP - row * SLOT_H
      on = n == @sel
      hud.rect(args, x, top - SLOT_H + 4, SLOT_W - 4, SLOT_H - 4, on ? [70, 110, 60] : [40, 50, 64])
      hud.rect(args, x + 39, top - 66, ICON, ICON, [98, 166, 76])
      args.outputs.sprites << { x: x + 39, y: top - 66, w: ICON, h: ICON, path: :palette,
                                source_x: n * ICON, source_y: 0, source_w: ICON, source_h: ICON,
                                angle: on ? -90 * @rot : 0 }
      hud.text(args, x + (SLOT_W - 4) / 2, top - 77, Pieces::DEFS[id].name, 15,
               on ? Hud::YELLOW : Hud::WHITE, 0.5)
      next unless on

      args.outputs.borders << { x: x, y: top - SLOT_H + 4, w: SLOT_W - 4, h: SLOT_H - 4,
                                r: 255, g: 214, b: 64 }
    end
  end
end
