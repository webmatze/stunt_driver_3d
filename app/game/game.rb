# STUNT DRIVER 3D - game flow: track menu (with a demo drive in the
# background), the timed run, the editor and its test drives, cameras,
# audio, best times and the user's tracks on disk.
class Game
  DT = 1.0 / 60
  FOV = 78.0
  V = D3D::V
  USER_SLOTS = 8
  TIMES_FILE = 'data/times.txt'
  VIEWS = %i[chase far hood].freeze

  attr_reader :state, :race, :world, :renderer, :editor, :entries
  attr_accessor :view, :autopilot

  def initialize(args)
    D3D::Native.load
    @renderer = StuntRenderer.new(fov: FOV, near: 0.3, fog: 1.0e9, view_distance: 340.0, headlight: 0.0)
    @hud = Hud.new
    @cam = D3D::Pose.new([0.0, 5.0, 0.0], [0.0, 0.0, 1.0])
    @cam_pos = [0.0, 5.0, 0.0]
    @cam_up = [0.0, 1.0, 0.0]
    @view = :chase
    @tick = 0
    @sel = 0
    @message = nil
    @message_time = 0.0
    load_times(args)
    load_tracks(args)
    enter_menu(args)
  end

  def tick(args)
    @tick += 1
    @message_time -= DT if @message_time > 0
    case @state
    when :menu then tick_menu(args)
    when :race then tick_race(args)
    when :editor then tick_editor(args)
    end
    update_audio(args)
  end

  # ------------------------------------------------------------ storage

  def load_times(args)
    @times = {}
    (args.gtk.read_file(TIMES_FILE) || '').split("\n").each do |line|
      id, t = line.split('=')
      @times[id] = t.to_f if t && t.to_f > 0
    end
  end

  def save_times(args)
    args.gtk.write_file(TIMES_FILE, @times.map { |id, t| "#{id}=#{t}" }.join("\n") + "\n")
  end

  def user_file(slot)
    "tracks/user_#{slot}.txt"
  end

  def load_tracks(args)
    @entries = BuiltinTracks.all.map do |t|
      { id: t.name.downcase, name: t.name, track: t, slot: nil }
    end
    (1..USER_SLOTS).each do |slot|
      text = args.gtk.read_file(user_file(slot))
      next if text.nil? || text.strip.empty?

      t = Track.parse(text)
      @entries << { id: "user_#{slot}", name: t.name, track: t, slot: slot }
    end
  end

  def free_slot
    used = @entries.map { |e| e[:slot] }
    (1..USER_SLOTS).find { |s| !used.include?(s) }
  end

  def save_entry(args, entry)
    text = entry[:track].serialize
    return if text == entry[:saved]

    args.gtk.write_file(user_file(entry[:slot]), text)
    if entry[:saved]
      # the track changed: its best time no longer counts
      @times.delete(entry[:id])
      save_times(args)
    end
    entry[:saved] = text
  end

  def note(text, time = 2.5)
    @message = text
    @message_time = time
  end

  # ------------------------------------------------------------ menu

  def enter_menu(args)
    @state = :menu
    @editor = nil
    @confirm_delete = false
    @sel = D3D.clamp(@sel, 0, menu_size - 1)
    start_demo
  end

  def menu_size
    @entries.size + (free_slot ? 1 : 0)
  end

  def start_demo
    @wreck = nil
    entry = @entries[@sel]
    unless entry
      @world = nil
      @race = nil
      return
    end
    @world = World.new(entry[:track])
    @minimap_dirty = true
    if @world.ok?
      @race = Race.new(@world, countdown: 0.0)
      @pilot = Autopilot.new(@race.car, @world)
    else
      @race = nil
    end
    @cam_snap = true
    @demo_end = 0.0
  end

  def tick_menu(args)
    down = args.inputs.keyboard.key_down
    n = menu_size
    move = (down.down ? 1 : 0) - (down.up ? 1 : 0)
    if move != 0
      @sel = (@sel + move + n) % n
      @confirm_delete = false
      start_demo
    end
    entry = @entries[@sel]

    if down.enter || down.space
      if entry.nil?
        return edit_new(args)
      elsif @world.ok?
        return start_race(args, entry, :menu)
      else
        note('Diese Strecke ist nicht fahrbar - mit E im Editor öffnen')
      end
    elsif down.e
      return entry ? edit_entry(args, entry) : edit_new(args)
    elsif (down.delete || down.backspace) && entry && entry[:slot]
      if @confirm_delete
        delete_entry(args, entry)
      else
        @confirm_delete = true
        note('Nochmal Entf drücken, um die Strecke zu löschen')
      end
    end

    # demo drive behind the menu
    if @race
      thr, brk, st = @pilot.control
      @race.update(DT, thr, brk, st)
      if @race.state != :running
        @demo_end += DT
        start_demo if @demo_end > 2.0
      end
      update_camera(@race.car, :far)
      render_scene(args, @race.car)
    else
      hud_rect(args, 0, 0, 1280, 720, [58, 118, 208])
    end
    draw_menu(args)
  end

  def delete_entry(args, entry)
    args.gtk.write_file(user_file(entry[:slot]), '')
    @times.delete(entry[:id])
    save_times(args)
    @entries.delete(entry)
    @confirm_delete = false
    @sel = D3D.clamp(@sel, 0, menu_size - 1)
    start_demo
  end

  def draw_menu(args)
    hud = @hud
    hud.panel(args, 40, 40, 520, 640, 170)
    hud.text(args, 70, 632, 'STUNT DRIVER 3D', 46, Hud::YELLOW)
    hud.text(args, 72, 592, 'Strecke wählen', 22, [200, 210, 220])
    y = 546
    menu_size.times do |i|
      entry = @entries[i]
      on = i == @sel
      hud.rect(args, 56, y - 20, 488, 40, [255, 214, 64], 70) if on
      if entry
        col = on ? Hud::YELLOW : Hud::WHITE
        hud.text(args, 72, y, entry[:name], 24, col)
        hud.text(args, 528, y, Hud.time(@times[entry[:id]]), 22, [200, 210, 220], 1.0)
      else
        hud.text(args, 72, y, '+ Neue Strecke bauen', 24, on ? Hud::YELLOW : Hud::GREEN)
      end
      y -= 42
    end
    entry = @entries[@sel]
    lines = ['Pfeiltasten  Strecke wählen      Enter  Fahren', 'E  Strecke im Editor bearbeiten']
    lines << 'Entf  Eigene Strecke löschen' if entry && entry[:slot]
    lines << 'Mitgelieferte Strecken werden als Kopie bearbeitet' if entry && !entry[:slot]
    y = 126
    lines.each do |line|
      hud.text(args, 72, y, line, 18, [206, 214, 226])
      y -= 26
    end
    hud.text(args, 640, 30, @message, 22, Hud::RED, 0.5) if @message_time > 0
    hud.panel(args, 800, 40, 440, 126, 150)
    ['Gas / Bremse   Pfeil hoch / runter  (W / S)', 'Lenken   Pfeil links / rechts  (A / D)',
     'C Kamera   R Neustart   P Pause', 'ESC  zurück'].each_with_index do |line, i|
      hud.text(args, 820, 142 - i * 26, line, 18, [206, 214, 226])
    end
  end

  # ------------------------------------------------------------ editor

  def edit_new(args)
    slot = free_slot
    return note('Kein freier Speicherplatz für eigene Strecken') unless slot

    entry = { id: "user_#{slot}", name: "Eigene Strecke #{slot}", slot: slot,
              track: Track.new("Eigene Strecke #{slot}") }
    @entries << entry
    open_editor(args, entry)
  end

  def edit_entry(args, entry)
    unless entry[:slot]
      slot = free_slot
      return note('Kein freier Speicherplatz für eine Kopie') unless slot

      copy = entry[:track].dup
      copy.name = "#{entry[:name]} (Kopie #{slot})"
      entry = { id: "user_#{slot}", name: copy.name, track: copy, slot: slot }
      @entries << entry
    end
    entry[:saved] ||= entry[:track].serialize if args.gtk.read_file(user_file(entry[:slot])).to_s.strip != ''
    open_editor(args, entry)
  end

  def open_editor(args, entry)
    @edit_entry = entry
    @sel = @entries.index(entry)
    @editor = Editor.new(entry[:track], @hud)
    @state = :editor
    @race = nil
  end

  def tick_editor(args)
    entry = @edit_entry
    case @editor.tick(args)
    when :save
      save_edit(args, entry)
      note('Strecke gespeichert')
    when :test
      if @editor.world.ok?
        save_edit(args, entry)
        return start_race(args, entry, :editor)
      end
      note('Erst wenn die Strecke geschlossen ist, kann sie gefahren werden')
    when :menu
      save_edit(args, entry)
      return enter_menu(args)
    end
    @hud.text(args, 1256, 700, @message, 20, Hud::YELLOW, 1.0) if @message_time > 0
  end

  def save_edit(args, entry)
    if entry[:track].empty?
      # nothing built: don't keep an empty track around
      args.gtk.write_file(user_file(entry[:slot]), '') if entry[:saved]
      @entries.delete(entry)
      @sel = 0
      return
    end
    @entries << entry unless @entries.include?(entry)
    save_entry(args, entry)
  end

  # ------------------------------------------------------------ race

  def start_race(args, entry, from)
    @race_entry = entry
    @race_from = from
    @state = :race
    @world = World.new(entry[:track]) unless @world && @world.track.equal?(entry[:track]) && from == :menu
    @minimap_dirty = true
    restart_race
  end

  def restart_race
    @race = Race.new(@world)
    @pilot = @autopilot ? Autopilot.new(@race.car, @world) : nil
    @wreck = nil
    @paused = false
    @new_best = false
    @cam_snap = true
    @go_time = 0.0
    @last_count = 4
  end

  def leave_race(args)
    if @race_from == :editor
      @state = :editor
      @race = nil
      @wreck = nil
    else
      enter_menu(args)
    end
  end

  def controls(args)
    return @pilot.control if @pilot

    inp = args.inputs
    kb = inp.keyboard
    c1 = inp.controller_one
    thr = inp.up || (c1 && (c1.key_held.r2 || c1.key_held.a)) ? 1.0 : 0.0
    brk = inp.down || kb.key_held.space || (c1 && (c1.key_held.l2 || c1.key_held.b)) ? 1.0 : 0.0
    steer = inp.respond_to?(:left_right_perc) ? inp.left_right_perc : inp.left_right
    [thr, brk, steer.to_f]
  end

  def tick_race(args)
    down = args.inputs.keyboard.key_down
    return leave_race(args) if down.escape

    restart_race if down.r
    @view = VIEWS[(VIEWS.index(@view) + 1) % VIEWS.size] if down.c
    @paused = !@paused if down.p
    race = @race
    car = race.car

    unless @paused
      thr, brk, st = controls(args)
      @throttle = thr
      case race.update(DT, thr, brk, st)
      when :go
        sound(args, 'go')
        @go_time = 1.0
      when :checkpoint
        sound(args, 'tick', 0.35)
      when :crash
        @wreck = Wreck.new(car)
        sound(args, 'crash')
      when :finish
        finish(args)
      end
      @wreck.update(DT) if @wreck
      @go_time -= DT if @go_time > 0
      if race.state == :countdown
        n = race.countdown.ceil
        sound(args, 'beep', 0.6) if n != @last_count
        @last_count = n
      end
    end

    update_camera(car, @view)
    render_scene(args, car)
    @hud.draw_race(args, race, @times[@race_entry[:id]], @tick)
    draw_race_messages(args, race)
  end

  def finish(args)
    id = @race_entry[:id]
    best = @times[id]
    if best.nil? || @race.time < best
      @times[id] = @race.time
      save_times(args)
      @new_best = true
    end
    sound(args, 'finish')
  end

  def draw_race_messages(args, race)
    hud = @hud
    back = @race_from == :editor ? 'Editor' : 'Menü'
    case race.state
    when :countdown
      hud.big(args, race.countdown.ceil.to_s, Hud::YELLOW)
    when :running
      hud.big(args, 'LOS!', Hud::GREEN) if @go_time > 0
      if race.missed && @tick % 40 < 28
        hud.text(args, 640, 560, 'Abschnitt ausgelassen - zurück zur Markierung auf der Karte!', 28,
                 Hud::RED, 0.5)
      elsif race.car.surface == :grass && race.car.grounded && race.car.forward_speed.abs > 3 &&
            @tick % 40 < 28
        hud.text(args, 640, 560, 'Neben der Strecke', 24, Hud::YELLOW, 0.5)
      end
    when :crashed
      hud.big(args, 'CRASH!', Hud::RED)
      hud.text(args, 640, 380, "R  Neustart      ESC  #{back}", 26, Hud::WHITE, 0.5)
    when :finished
      hud.big(args, 'ZIEL!', Hud::GREEN)
      hud.text(args, 640, 384, "Zeit  #{Hud.time(race.time)}", 44, Hud::WHITE, 0.5)
      hud.text(args, 640, 334, 'Neue Bestzeit!', 30, Hud::YELLOW, 0.5) if @new_best
      hud.text(args, 640, 284, "R  Nochmal      ESC  #{back}", 26, Hud::WHITE, 0.5)
    end
    hud.big(args, 'PAUSE', Hud::WHITE, 300, 60) if @paused
  end

  # ------------------------------------------------------------ camera

  def update_camera(car, view)
    pos = car.pos
    u = car.up
    f = car.fwd
    if car.crashed && @wreck
      # circle the wreck
      a = @wreck.age * 0.5
      o = @wreck.origin
      target = [o[0], [o[1], 1.0].max, o[2]]
      want = [o[0] + Math.cos(a) * 13.0, target[1] + 5.0, o[2] + Math.sin(a) * 13.0]
      @cam_pos = V.lerp(@cam_pos, want, 0.05)
      @cam_up = V.norm(V.lerp(@cam_up, [0.0, 1.0, 0.0], 0.1))
    elsif view == :hood
      @cam_pos = V.madd(V.madd(pos, u, 1.25), f, 0.35)
      @cam_up = u
      @cam.position = @cam_pos
      @cam.look!(f, u)
      return
    else
      back, height = view == :far ? [13.0, 5.5] : [7.5, 2.8]
      want = V.madd(V.madd(pos, u, height), f, -back)
      target = V.madd(V.madd(pos, u, 1.2), f, 4.0)
      k = @cam_snap ? 1.0 : 0.22
      @cam_pos = V.lerp(@cam_pos, want, k)
      @cam_up = V.norm(V.lerp(@cam_up, u, @cam_snap ? 1.0 : 0.12))
      @cam_snap = false
    end
    # keep the camera above the ground (the car can be upside down above it)
    @cam_pos = [@cam_pos[0], 0.5, @cam_pos[2]] if @cam_pos[1] < 0.5
    @cam.position = @cam_pos
    @cam.look!(V.sub(target, @cam_pos), @cam_up)
  end

  # ------------------------------------------------------------ rendering

  def render_scene(args, car)
    r = @renderer
    world = @world
    show_car = !car.crashed && !(@view == :hood && @state == :race)
    r.begin_frame(@cam, show_car ? V.madd(car.pos, car.up, 0.6) : nil)
    out = args.outputs.sprites
    r.draw_backdrop(out)
    r.draw_checker
    world.ground_geos.each { |g| r.draw_geo(g, true) }
    world.geos.each { |g| r.draw_geo(g, false) }
    if show_car
      Models.draw_car(r, car)
      if car.grounded
        r.draw_shadow(car.pos, car.right, car.fwd, car.normal)
      elsif car.pos[1] > 0
        fl = V.norm([car.fwd[0], 0.0, car.fwd[2]])
        r.draw_shadow([car.pos[0], 0.0, car.pos[2]], [fl[2], 0.0, -fl[0]], fl, [0.0, 1.0, 0.0])
      end
    end
    @wreck.draw(r) if @wreck
    r.flush_scene(out)
    @tris = r.triangle_count
    return unless @minimap_dirty

    MapView.render_minimap(args, :minimap, world, Hud::MAP, [44, 84, 46, 255])
    @minimap_dirty = false
  end

  def hud_rect(args, x, y, w, h, col)
    @hud.rect(args, x, y, w, h, col)
  end

  # ------------------------------------------------------------ audio

  def sound(args, name, gain = 0.8)
    @snd = (@snd || 0) + 1
    args.audio[:"fx#{@snd % 8}"] = { input: "sounds/#{name}.wav", gain: gain, pitch: 1.0 }
  end

  def update_audio(args)
    racing = @state == :race && @race && !@paused && !@race.car.crashed
    unless racing
      args.audio[:engine] = nil
      args.audio[:skid] = nil
      return
    end
    car = @race.car
    eng = (args.audio[:engine] ||= { input: 'sounds/engine.wav', looping: true, gain: 0.0, pitch: 1.0 })
    eng[:pitch] = 0.55 + car.rpm * 0.75 + car.gear * 0.07
    eng[:gain] = 0.22 + (@throttle || 0.0) * 0.3
    skid = (args.audio[:skid] ||= { input: 'sounds/skid.wav', looping: true, gain: 0.0, pitch: 1.0 })
    want = car.grounded && car.surface == :road ? D3D.clamp(car.skid / 6.0, 0.0, 0.5) : 0.0
    skid[:gain] += (want - skid[:gain]) * 0.2
  end
end
