#!/usr/bin/env ruby
# Generates the game's sounds procedurally (plain Ruby, no audio tools).
#
#   ruby tools/gen_assets.rb
#
# Output: sounds/*.wav
require "fileutils"

ROOT = File.expand_path("..", __dir__)
RATE = 22_050

def write_wav(name, samples)
  path = File.join(ROOT, "sounds/#{name}.wav")
  FileUtils.mkdir_p(File.dirname(path))
  data = samples.map { |s| ([[s, -1.0].max, 1.0].min * 32_000).round }.pack("s<*")
  header = ["RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, RATE, RATE * 2, 2, 16,
            "data", data.bytesize].pack("A4VA4A4VvvVVvvA4V")
  File.binwrite(path, header + data)
  puts "wrote sounds/#{name}.wav"
end

def lowpass(samples, k)
  y = 0.0
  samples.map { |s| y += (s - y) * k }
end

def normalize(samples, peak = 0.9)
  m = samples.map(&:abs).max
  m = 1e-9 if m < 1e-9
  samples.map { |s| s / m * peak }
end

# Loopable engine: one second holding whole cycles of every partial.
def engine
  base = 55.0
  s = Array.new(RATE) do |i|
    t = i.to_f / RATE
    ph = (t * base * 2) % 1.0
    pulse = Math.exp(-ph * 5.0)
    saw = 2.0 * ((t * base) % 1.0) - 1.0
    saw * 0.5 + Math.sin(2 * Math::PI * base * 2 * t) * 0.3 * (0.4 + pulse) +
      Math.sin(2 * Math::PI * base * 3 * t) * 0.15 + Math.sin(2 * Math::PI * base * 0.5 * t) * 0.3
  end
  write_wav("engine", normalize(lowpass(s, 0.3), 0.75))
end

def tone(name, freq, secs, peak = 0.6)
  n = (RATE * secs).to_i
  s = Array.new(n) do |i|
    t = i.to_f / RATE
    env = [t / 0.005, 1.0].min * [(secs - t) / 0.04, 1.0].min
    (Math.sin(2 * Math::PI * freq * t) + 0.3 * Math.sin(4 * Math::PI * freq * t)) * env
  end
  write_wav(name, normalize(s, peak))
end

def crash
  rng = Random.new(7)
  n = (RATE * 1.3).to_i
  s = Array.new(n) do |i|
    t = i.to_f / RATE
    (rng.rand * 2 - 1) * Math.exp(-t * 3.2) + Math.sin(2 * Math::PI * 60 * t) * Math.exp(-t * 7) * 1.2 +
      (rng.rand * 2 - 1) * (t < 0.06 ? 1.5 : 0.0)
  end
  write_wav("crash", normalize(lowpass(s, 0.4), 0.95))
end

def skid
  rng = Random.new(3)
  n = RATE
  noise = Array.new(n) { rng.rand * 2 - 1 }
  s = Array.new(n) do |i|
    t = i.to_f / RATE
    noise[i] * 0.6 + Math.sin(2 * Math::PI * 880 * t + Math.sin(2 * Math::PI * 6 * t) * 3) * 0.5
  end
  fade = 600
  fade.times do |i|
    k = i / fade.to_f
    s[i] = s[i] * k + s[n - fade + i] * (1 - k)
  end
  write_wav("skid", normalize(lowpass(s[0...(n - fade)], 0.5), 0.6))
end

def finish
  notes = [523.25, 659.25, 783.99, 1046.5]
  s = []
  notes.each_with_index do |f, k|
    secs = k == 3 ? 0.5 : 0.13
    n = (RATE * secs).to_i
    n.times do |i|
      t = i.to_f / RATE
      env = [t / 0.005, 1.0].min * [(secs - t) / 0.05, 1.0].min
      s << (Math.sin(2 * Math::PI * f * t) + 0.4 * Math.sin(4 * Math::PI * f * t)) * env
    end
  end
  write_wav("finish", normalize(s, 0.7))
end

engine
tone("beep", 440.0, 0.18)
tone("go", 880.0, 0.5)
tone("tick", 1320.0, 0.05, 0.4)
crash
skid
finish
