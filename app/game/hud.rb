# 2D overlays: text helpers, the instruments of a race (speed, gear, revs,
# clock, progress, minimap) and its messages.
class Hud
  WHITE = [255, 255, 255].freeze
  YELLOW = [255, 214, 64].freeze
  RED = [255, 84, 64].freeze
  GREEN = [120, 230, 110].freeze
  MAP = 200
  MAP_X = 1060
  MAP_Y = 20

  def self.time(t)
    return '-:--.--' unless t

    m = (t / 60).to_i
    format('%d:%05.2f', m, t - m * 60)
  end

  def text(args, x, y, str, size = 24, col = WHITE, align = 0.0, a = 255)
    args.outputs.labels << { x: x + 2, y: y - 2, text: str, size_px: size, anchor_x: align, anchor_y: 0.5,
                             r: 0, g: 0, b: 0, a: a * 0.7 }
    args.outputs.labels << { x: x, y: y, text: str, size_px: size, anchor_x: align, anchor_y: 0.5,
                             r: col[0], g: col[1], b: col[2], a: a }
  end

  def rect(args, x, y, w, h, col, a = 255)
    args.outputs.sprites << { x: x, y: y, w: w, h: h, path: :solid, r: col[0], g: col[1], b: col[2], a: a }
  end

  def panel(args, x, y, w, h, a = 130)
    rect(args, x, y, w, h, [10, 14, 22], a)
  end

  def draw_race(args, race, best, tick)
    car = race.car
    panel(args, 20, 20, 270, 118)
    kmh = (car.forward_speed.abs * 3.6).round
    text(args, 170, 96, kmh.to_s, 60, WHITE, 1.0)
    text(args, 180, 84, 'km/h', 20, [200, 210, 220])
    text(args, 270, 100, car.forward_speed < -0.5 ? 'R' : car.gear.to_s, 40, YELLOW, 1.0)
    rect(args, 40, 36, 230, 14, [40, 46, 58])
    rpm = car.rpm
    rect(args, 40, 36, 230 * rpm, 14, rpm > 0.85 ? RED : (rpm > 0.6 ? YELLOW : GREEN))

    panel(args, 20, 622, 270, 78)
    text(args, 36, 674, Hud.time(race.time), 40)
    text(args, 36, 640, "Bestzeit  #{Hud.time(best)}", 20, [200, 210, 220])

    panel(args, 1010, 652, 250, 48)
    done = [race.next_cp - 1, 0].max
    text(args, 1244, 676, "Abschnitt #{done}/#{race.total_cps}", 24, WHITE, 1.0)

    draw_minimap(args, race, tick)
  end

  def draw_minimap(args, race, tick)
    args.outputs.sprites << { x: MAP_X, y: MAP_Y, w: MAP, h: MAP, path: :minimap, a: 215 }
    k = MAP / (Track::SIZE * World::T)
    if race.state == :running && tick % 30 < 20
      cp = race.next_cp_pos
      rect(args, MAP_X + cp[0] * k - 5, MAP_Y + cp[2] * k - 5, 10, 10, WHITE, 200)
    end
    p = race.car.pos
    x = D3D.clamp(MAP_X + p[0] * k, MAP_X, MAP_X + MAP)
    y = D3D.clamp(MAP_Y + p[2] * k, MAP_Y, MAP_Y + MAP)
    rect(args, x - 5, y - 5, 10, 10, [0, 0, 0])
    rect(args, x - 3, y - 3, 6, 6, YELLOW)
  end

  def big(args, str, col = WHITE, y = 470, size = 96)
    text(args, 640, y, str, size, col, 0.5)
  end
end
