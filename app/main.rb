# STUNT DRIVER 3D - a stunt racing game built on the d3d engine.
GC.generational_mode = false if GC.respond_to?(:generational_mode=)

require 'app/d3d/d3d.rb'
require 'app/game/geo.rb'
require 'app/game/pieces.rb'
require 'app/game/track.rb'
require 'app/game/world.rb'
require 'app/game/car.rb'
require 'app/game/autopilot.rb'
require 'app/game/race.rb'
require 'app/game/builtin_tracks.rb'
require 'app/game/gfx.rb'
require 'app/game/models.rb'
require 'app/game/map_view.rb'
require 'app/game/hud.rb'
require 'app/game/editor.rb'
require 'app/game/game.rb'

def tick(args)
  $game ||= Game.new(args)
  $game.tick(args)
end

# Start over after editing game code: $gtk.reset in the console.
def reset(_args = nil)
  $game = nil
end
