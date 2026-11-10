# Second scenario for tools/smoke.rb (--eval tools/smoke_ui.rb): the paths
# the autopilot lap doesn't touch - real input polling in a race, pause,
# a new empty track in the editor, a test drive from the editor and
# deleting a user track.
$smoke = { frame: 0, log: [] }

def tick(args)
  s = $smoke
  f = s[:frame]
  begin
    $game ||= Game.new(args)
    g = $game
    case f
    when 20 then g.start_race(args, g.entries[0], :menu)
    when 260 then g.instance_variable_set(:@paused, true)
    when 280 then g.instance_variable_set(:@paused, false)
    when 300
      s[:log] << "race: #{g.race.state}, clock #{g.race.time.round(2)}"
      g.leave_race(args)
    when 320 then g.edit_new(args)
    when 330
      ed = g.editor
      [[5, 5, :start, 0], [5, 6, :curve, 0], [6, 6, :curve, 1], [6, 5, :straight, 0], [6, 4, :curve, 2],
       [5, 4, :curve, 3]].each do |i, j, id, rot|
        ed.track.place(i, j, id, rot)
      end
      ed.send(:rebuild)
      s[:log] << "new track route: #{ed.world.route[:ok] ? 'ok' : ed.world.route[:error]}"
    when 340
      args.outputs.screenshots << { x: 0, y: 0, w: 1280, h: 720, path: 'smoke/new_track.png', a: 255 }
    when 350
      entry = g.instance_variable_get(:@edit_entry)
      g.save_edit(args, entry)
      g.start_race(args, entry, :editor) if g.editor.world.ok?
    when 420
      s[:log] << "test drive: #{g.state} #{g.race && g.race.state}"
      g.leave_race(args)
      s[:log] << "back in: #{g.state}"
      g.enter_menu(args)
      s[:log] << "menu entries: #{g.entries.map { |e| e[:name] }.join(', ')}"
    when 440
      g.delete_entry(args, g.entries.last)
      s[:log] << "after delete: #{g.entries.size} entries, file '#{$gtk.read_file('tracks/user_1.txt')}'"
    end
    g.tick(args)
  rescue Exception => e
    s[:log] << "FAIL frame #{f}: #{e.class}: #{e.message} | #{e.backtrace.to_a.first(6).join(' | ')}"
    f = 9999
  end
  s[:frame] += 1
  return if f < 470

  $gtk.write_file('smoke/report.txt', s[:log].join("\n") + "\nDONE\n")
  $gtk.request_quit
end
