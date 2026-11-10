# Evaluated inside DragonRuby by tools/smoke.rb. Scenario:
#   menu -> autopilot lap on the Stuntpark (all camera views) -> a run that
#   is too slow for the loop and crashes -> the editor.
# Takes screenshots, measures the Ruby time per tick, writes smoke/report.txt.
$smoke = { frame: 0, phase: :menu, since: 0, times: [], tris: [], log: [], shots: 0 }

def smoke_shot(args, name)
  args.outputs.screenshots << { x: 0, y: 0, w: 1280, h: 720, path: "smoke/#{name}.png", a: 255 }
end

class Game
  attr_accessor :slow_demo

  alias smoke_controls controls
  def controls(args)
    thr, brk, st = smoke_controls(args)
    return [thr, brk, st] unless @slow_demo

    # creep into the loop: too slow to make it over the top
    v = @race.car.forward_speed
    [v < 17.0 ? 1.0 : 0.0, 0.0, st]
  end
end

def smoke_next(phase)
  $smoke[:phase] = phase
  $smoke[:since] = 0
end

def tick(args)
  s = $smoke
  f = s[:frame]
  begin
    $game ||= Game.new(args)
    g = $game
    case s[:phase]
    when :menu
      smoke_shot(args, 'menu') if s[:since] == 200
      if s[:since] == 240
        g.autopilot = true
        g.start_race(args, g.entries[1], :menu)
        smoke_next(:lap)
      end
    when :lap
      n = s[:since]
      g.view = n > 1500 && n < 1900 ? :hood : (n > 2200 && n < 2500 ? :far : :chase)
      smoke_shot(args, format('lap_%04d', n)) if n % 150 == 100
      if g.race.state != :running && g.race.state != :countdown
        s[:log] << "lap: #{g.race.state} time #{g.race.time.round(2)} crashed #{g.race.car.crashed.inspect}"
        s[:log] << 'FAIL lap not finished' unless g.race.state == :finished
        smoke_next(:lap_end)
      end
    when :lap_end
      smoke_shot(args, 'finish') if s[:since] == 60
      if s[:since] == 90
        g.slow_demo = true
        g.view = :chase
        g.restart_race
        smoke_next(:crash)
      end
    when :crash
      smoke_shot(args, format('slow_%04d', s[:since])) if s[:since] % 120 == 60 && g.race.state == :running
      if g.race.state == :crashed
        s[:crash_at] ||= s[:since]
        smoke_shot(args, 'crash') if s[:since] == s[:crash_at] + 40
        if s[:since] == s[:crash_at] + 80
          s[:log] << "slow run: crashed #{g.race.car.crashed.inspect} after #{g.race.time.round(2)} s"
          g.leave_race(args)
          g.edit_entry(args, g.entries[2])
          smoke_next(:editor)
        end
      elsif s[:since] > 1500
        s[:log] << "FAIL slow run did not crash (state #{g.race.state})"
        smoke_next(:done)
      end
    when :editor
      if s[:since] == 10
        # build something, as the mouse would
        ed = g.editor
        ed.instance_variable_set(:@cur, [15, 15])
        ed.instance_variable_set(:@sel, Pieces::ORDER.index(:house))
        ed.send(:place)
        ed.instance_variable_set(:@sel, Pieces::ORDER.index(:wide_curve))
        ed.instance_variable_set(:@rot, 1)
        ed.instance_variable_set(:@cur, [16, 4])
      end
      smoke_shot(args, 'editor') if s[:since] == 30
      if s[:since] == 50
        g.save_edit(args, g.instance_variable_get(:@edit_entry))
        text = $gtk.read_file('tracks/user_1.txt').to_s
        s[:log] << 'FAIL track file not written' unless text.include?('15 15 house 0')
        fresh = Game.new(args)
        s[:log] << "FAIL saved track not loaded (#{fresh.entries.size} entries)" unless fresh.entries.size == 4
        s[:log] << "editor: saved #{text.split("\n").size - 1} pieces, reloaded as '#{fresh.entries[3][:name]}'"
        g.enter_menu(args)
        smoke_next(:menu2)
      end
    when :menu2
      smoke_shot(args, 'menu2') if s[:since] == 120
      smoke_next(:done) if s[:since] == 130
    end
    t0 = Time.now
    g.tick(args)
    if s[:phase] == :lap
      s[:times] << (Time.now - t0) * 1000
      s[:tris] << (g.instance_variable_get(:@tris) || 0)
    end
  rescue Exception => e
    s[:log] << "FAIL frame #{f} (#{s[:phase]}): #{e.class}: #{e.message} | #{e.backtrace.to_a.first(6).join(' | ')}"
    s[:phase] = :done
  end
  s[:frame] += 1
  s[:since] += 1
  return unless s[:phase] == :done || s[:frame] > 9000

  t = s[:times].sort
  unless t.empty?
    avg = t.sum / t.size
    s[:log] << format('ticks %d  avg %.1f ms  median %.1f ms  p95 %.1f ms  max %.1f ms',
                      t.size, avg, t[(t.size / 2).to_i], t[(t.size * 0.95).to_i], t.last)
    tr = s[:tris].sort
    s[:log] << format('triangles avg %d  max %d', tr.sum / tr.size, tr.last)
  end
  s[:log] << "native #{D3D::Native.enabled?}"
  $gtk.write_file('smoke/report.txt', s[:log].join("\n") + "\nDONE\n")
  $gtk.request_quit
end
