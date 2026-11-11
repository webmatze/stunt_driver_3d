# The track editor: a top-down map of the tile grid on the left, the
# available pieces on the right. The map shows a scrollable part of the
# grid (mouse wheel, middle mouse button, the overview or the keyboard
# cursor move it). Pieces are placed with the mouse (or the keyboard
# cursor) and the route is checked after every change.
class Editor
  MX = 24
  MY = 40
  CELL = 64
  MAP = CELL * Track::SIZE
  VIEW = 640 # visible part of the map in pixels
  SCROLL_MAX = MAP - VIEW
  WHEEL = 32 # pixels per wheel step
  PX = 694
  ICON = 60
  ICON_RT = 128 # resolution of a palette icon (also drawn as the ghost)
  ICON_FILL = 0.9
  OV = 160 # overview of the whole grid
  OVX = 1102
  OVY = 44
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
    @drag = nil
    rebuild
    center_view
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

  # ---------------------------------------------------------------- view

  def scroll_to(x, y)
    @vx = D3D.clamp(x, 0, SCROLL_MAX)
    @vy = D3D.clamp(y, 0, SCROLL_MAX)
  end

  # Starts with the middle of the track (or of the grid) in view.
  def center_view
    ci = cj = Track::SIZE / 2.0
    unless @track.empty?
      cells = @track.cells.map do |k, (id, rot)|
        i, j = @track.coords(k)
        fw, fd = Pieces.footprint(id, rot)
        [i, j, i + fw, j + fd]
      end
      ci = (cells.map { |c| c[0] }.min + cells.map { |c| c[2] }.max) / 2.0
      cj = (cells.map { |c| c[1] }.min + cells.map { |c| c[3] }.max) / 2.0
    end
    scroll_to(ci * CELL - VIEW / 2, cj * CELL - VIEW / 2)
    @cur = [D3D.clamp(ci.floor, 0, Track::SIZE - 1), D3D.clamp(cj.floor, 0, Track::SIZE - 1)]
  end

  # Scrolls just far enough to show the cursor and the tiles around it.
  def show_cursor
    i, j = @cur
    x = [[@vx, (i - 1) * CELL].min, (i + 2) * CELL - VIEW].max
    y = [[@vy, (j - 1) * CELL].min, (j + 2) * CELL - VIEW].max
    scroll_to(x, y)
  end

  # Mouse wheel, middle mouse button and the overview. Returns true when
  # the view moved.
  def scroll_input(args, over_map)
    kb = args.inputs.keyboard
    mouse = args.inputs.mouse
    x = @vx
    y = @vy
    if mouse.wheel
      wx = mouse.wheel.x
      wy = mouse.wheel.y
      # a plain wheel scrolls sideways with Shift
      wx, wy = wy, 0 if wx == 0 && (kb.key_held.shift || kb.key_down.shift)
      scroll_to(@vx + wx * WHEEL, @vy + wy * WHEEL)
    end
    if mouse.button_middle
      scroll_to(@vx - (mouse.x - @drag[0]), @vy - (mouse.y - @drag[1])) if @drag
      @drag = [mouse.x, mouse.y]
    else
      @drag = nil
    end
    @ov_drag = false unless mouse.button_left
    @ov_drag = true if mouse.click && mouse.button_left && over_overview?(mouse)
    if @ov_drag
      f = MAP / OV.to_f
      scroll_to((mouse.x - OVX) * f - VIEW / 2, (mouse.y - OVY) * f - VIEW / 2)
    end
    @painting = false unless mouse.button_left
    @painting = true if mouse.click && mouse.button_left && over_map
    x != @vx || y != @vy
  end

  def over_overview?(mouse)
    mouse.x >= OVX && mouse.x < OVX + OV && mouse.y >= OVY && mouse.y < OVY + OV
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
    @sel = (@sel + (kb.key_held.shift ? n - 1 : 1)) % n if down.tab
    @sel = (@sel + 1) % n if down.e
    @sel = (@sel + n - 1) % n if down.q
    @cur[0] = D3D.clamp(@cur[0] + 1, 0, Track::SIZE - 1) if down.right
    @cur[0] = D3D.clamp(@cur[0] - 1, 0, Track::SIZE - 1) if down.left
    @cur[1] = D3D.clamp(@cur[1] + 1, 0, Track::SIZE - 1) if down.up
    @cur[1] = D3D.clamp(@cur[1] - 1, 0, Track::SIZE - 1) if down.down
    show_cursor if down.right || down.left || down.up || down.down

    over_map = mouse.x >= MX && mouse.x < MX + VIEW && mouse.y >= MY && mouse.y < MY + VIEW
    scrolled = scroll_input(args, over_map)
    if over_map && (scrolled || mouse.moved || mouse.button_left || mouse.button_right)
      @cur = [D3D.clamp(((mouse.x - MX + @vx) / CELL).floor, 0, Track::SIZE - 1),
              D3D.clamp(((mouse.y - MY + @vy) / CELL).floor, 0, Track::SIZE - 1)]
    end
    if mouse.click && !over_map
      idx = palette_index(mouse.x, mouse.y)
      @sel = idx if idx
    end

    @last_paint = nil unless mouse.button_left
    if down.space || (over_map && @painting)
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
    rt.w = ICON_RT * Pieces::ORDER.size
    rt.h = ICON_RT
    rt.background_color = [0, 0, 0, 0]
    Pieces::ORDER.each_with_index do |id, n|
      piece = Pieces::DEFS[id]
      b = PieceBuilder.new(0, 0, 0.0, 0.0)
      piece.build.call(b)
      scale = ICON_RT * ICON_FILL / ([piece.w, piece.d].max * World::T)
      rt.sprites << MapView.prims([b.ground], [b.geo], scale, (n + 0.5) * ICON_RT, ICON_RT / 2.0)
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
    MapView.render_world(args, :editor_overview, @world, OV, [98, 166, 76, 255], [255, 232, 90])
    @map_dirty = false
  end

  # The visible part of the map with the cursor, clipped by a render target.
  def render_view(args)
    rt = args.outputs[:editor_view]
    rt.w = VIEW
    rt.h = VIEW
    rt.background_color = [98, 166, 76, 255]
    ox = -@vx.round
    oy = -@vy.round
    rt.sprites << { x: ox, y: oy, w: MAP, h: MAP, path: :editor_map }
    route = @world.route
    cell = route[:cell]
    if !route[:ok] && cell && @track.in_bounds?(cell[0], cell[1])
      3.times do |n|
        rt.borders << { x: ox + cell[0] * CELL + n, y: oy + cell[1] * CELL + n, w: CELL - 2 * n,
                        h: CELL - 2 * n, r: 255, g: 60, b: 40 }
      end
    end
    draw_ghost(rt, ox, oy)
  end

  def draw(args)
    render_palette(args) unless @palette_ready
    render_map(args) if @map_dirty
    hud = @hud
    out = args.outputs.sprites
    hud.rect(args, 0, 0, 1280, 720, [24, 30, 40])
    hud.text(args, MX, 700, "Strecken-Editor:  #{@track.name}", 26, Hud::YELLOW)
    render_view(args)
    out << { x: MX, y: MY, w: VIEW, h: VIEW, path: :editor_view }

    route = @world.route
    if route[:ok]
      hud.text(args, MX, 20, "Strecke geschlossen, #{route[:steps].size} Abschnitte.  T = Probefahrt", 20, Hud::GREEN)
    else
      hud.text(args, MX, 20, "Nicht fahrbar: #{route[:error]}", 20, Hud::RED)
    end

    draw_palette(args)
    draw_overview(args)

    y = 236
    ['Linke Maustaste / Leertaste: Teil setzen',
     'Rechte Maustaste / X: Teil entfernen',
     'R: drehen     Q / E: Teil wählen',
     'Mausrad / mittlere Maustaste: Karte',
     'verschieben     Pfeiltasten: Cursor',
     'T: Probefahrt   S: speichern   ESC: Menü',
     '',
     'Die Strecke muss vom Start/Ziel aus einen',
     'geschlossenen Kurs bilden. Schanzen',
     'brauchen eine zweite Schanze als Landung',
     '(max. 2 Felder Lücke).'].each do |line|
      hud.text(args, PX, y, line, 17, [206, 214, 226])
      y -= 21
    end
  end

  # The whole grid in small, with the visible part framed. A click moves
  # the view there.
  def draw_overview(args)
    args.outputs.sprites << { x: OVX, y: OVY, w: OV, h: OV, path: :editor_overview }
    f = OV / MAP.to_f
    2.times do |n|
      args.outputs.borders << { x: OVX + @vx * f + n, y: OVY + @vy * f + n, w: VIEW * f - 2 * n,
                                h: VIEW * f - 2 * n, r: 255, g: 255, b: 255 }
    end
    route = @world.route
    cell = route[:cell]
    return if route[:ok] || !cell || !@track.in_bounds?(cell[0], cell[1])

    s = OV / Track::SIZE.to_f
    args.outputs.sprites << { x: OVX + cell[0] * s, y: OVY + cell[1] * s, w: s, h: s, path: :solid,
                              r: 255, g: 60, b: 40 }
  end

  def draw_ghost(rt, ox, oy)
    i, j = @cur
    id = selected
    fw, fd = Pieces.footprint(id, @rot)
    ok = @track.in_bounds?(i, j) && @track.in_bounds?(i + fw - 1, j + fd - 1)
    x = ox + i * CELL
    y = oy + j * CELL
    piece = Pieces::DEFS[id]
    size = [piece.w, piece.d].max * CELL / ICON_FILL
    if ok
      rt.sprites << { x: x + fw * CELL / 2.0 - size / 2, y: y + fd * CELL / 2.0 - size / 2,
                      w: size, h: size, path: :palette, source_x: @sel * ICON_RT, source_y: 0,
                      source_w: ICON_RT, source_h: ICON_RT, angle: -90 * @rot, a: 170 }
    end
    c = ok ? [255, 255, 255] : [255, 60, 40]
    2.times do |n|
      rt.borders << { x: x + n, y: y + n, w: fw * CELL - 2 * n, h: fd * CELL - 2 * n,
                      r: c[0], g: c[1], b: c[2] }
    end
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
                                source_x: n * ICON_RT, source_y: 0, source_w: ICON_RT, source_h: ICON_RT,
                                angle: on ? -90 * @rot : 0 }
      hud.text(args, x + (SLOT_W - 4) / 2, top - 77, Pieces::DEFS[id].name, 15,
               on ? Hud::YELLOW : Hud::WHITE, 0.5)
      next unless on

      args.outputs.borders << { x: x, y: top - SLOT_H + 4, w: SLOT_W - 4, h: SLOT_H - 4,
                                r: 255, g: 214, b: 64 }
    end
  end
end
