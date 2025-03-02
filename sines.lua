--- ~ sines 0.92 ~
-- @oootini, @eigen, @sixolet, @x2mirko
--
--   ~~    ~~    ~~    ~~    ~~    ~~
--  ~  ~  ~  ~  ~  ~  ~  ~  ~  ~  ~  ~
-- ~    ~~    ~~    ~~    ~~    ~~    ~
--
-- ▼ controls ▼
--
-- E1     - master volume
-- E2    - active sine
--
-- active sine control:
-- E3      - amplitude
-- K2 + E2 - note
-- K2 + E3 - detune
-- K2 + K3 - voice panning
-- K3 + E2 - envelope
-- K3 + E3 - FM index
-- K1 + E2 - sample rate
-- K1 + E3 - bit depth
--
-- sine control w/ 16n:
-- n                - amplitude
-- n + K2           - detune
-- n + K3           - FM index
-- n + K1 + K2      - sample rate
-- n + K1 + K3      - bit depth
-- n + K1 + K2 + K3 - note

local sliders = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
local max_slider_size = 32
local edit = 1
local accum = 1
-- env_name, env_bias, attack, decay. bias of 1.0 is used to create a static drone
local envs = {
  {"drone", 1.0, 1.0, 1.0},
  {"am1", 0.0, 0.001, 0.01},
  {"am2", 0.0, 0.001, 0.02},
  {"am3", 0.3, 0.001, 0.05},
  {"pulse1", 0.0, 0.001, 0.2},
  {"pulse2", 0.0, 0.001, 0.5},
  {"pulse3", 0.0, 0.001, 0.8},
  {"pulse4", 0.3, 0.001, 1.0},
  {"ramp1", 0.0, 1.5, 0.01},
  {"ramp2", 0.0, 2.0, 0.01},
  {"ramp3", 0.0, 3.0, 0.01},
  {"ramp4", 0.3, 4.0, 0.01},
  {"evolve1", 0.3, 10.0, 10.0},
  {"evolve2", 0.3, 15.0, 11.0},
  {"evolve3", 0.3, 20.0, 12.0},
  {"evolve4", 0.4, 25.0, 15.0}
}
local env_values = {}
local env_edit = 1
local env_accum = 1
local value = 0
local text = " "
local step = 0
local cents = {}
local notes = {}
local scale_names = {}
local key_1_pressed = 0
local key_2_pressed = 0
local key_3_pressed = 0
local toggle = false
local scale_toggle = false
local prev_16n_slider_v = {
  vol = {},
  cents = {},
  fm_index = {},
  smpl_rate = {},
  bit_depth = {},
  note = {},
}
local fps = 14
local redraw_clock
local screen_dirty = false

engine.name = "Sines"
MusicUtil = require "musicutil"
_16n = include "sines/lib/16n"

local g = grid.connect()
local grid_width = g.cols
local grid_height = g.rows
local grid_slider_scale = max_slider_size / grid_height
local monobright = false

-- handle monobright grids
if util.string_starts(g.name, 'monome 64 m64')
  or util.string_starts(g.name, 'monome 128 m128')
  or util.string_starts(g.name, 'monome 256 m256') then
    monobright = true
end

function init()
  print("loaded Sines engine")
  add_params()
  edit = 0
  for i = 1, 16 do
    env_values[i] = params:get("env" .. i)
    cents[i] = params:get("cents" .. i)
    sliders[i] = (params:get("vol" .. i)) * max_slider_size
  end

  _16n.init(_16n_slider_callback)
  for i = 1, 16 do
    prev_16n_slider_v["vol"][i] = util.linlin(0.0, 1.0, 0, 127, params:get("vol"..i))
    prev_16n_slider_v["cents"][i] = util.linlin(-200, 200, 0, 127, params:get("cents"..i))
    prev_16n_slider_v["fm_index"][i] = util.linlin(0.0, 200.0, 0, 127, params:get("fm_index"..i))
    prev_16n_slider_v["smpl_rate"][i] = util.linlin(48000, 480, 0, 127, params:get("smpl_rate"..i))
    prev_16n_slider_v["bit_depth"][i] = util.linlin(24, 1, 0, 127, params:get("bit_depth"..i))
    prev_16n_slider_v["note"][i] = params:get("note"..i)
  end

  redraw_clock = clock.run(
    function()
      local step_s = 1 / fps
      while true do
        clock.sleep(step_s)
        if screen_dirty then
          redraw()
          screen_dirty = false
        end
      end
    end)
end

function cleanup()
  clock.cancel(redraw_clock)
end

function is_prev_16n_slider_v_crossing(mode, i, v)
  local prev_v = prev_16n_slider_v[mode][i]
  if mode ~= "vol" and params:string("16n_params_jump") == "yes" then
    return true
  end
  if prev_v == nil then
    return true
  end
  if math.abs(v - prev_v) < 10 then
    return true
  end
  return false
end

function _16n_slider_callback(midi_msg)
  local slider_id = _16n.cc_2_slider_id(midi_msg.cc)
  local v = midi_msg.val

  if params:string("16n_auto") == "no" then
    return
  end

  -- update current slider
  params:set("fader" .. slider_id, v)
end

function virtual_slider_callback(slider_id, v)
  accum = slider_id - 1
  edit = accum

  if key_1_pressed == 0 and key_3_pressed == 0 and key_2_pressed == 0 then
    if is_prev_16n_slider_v_crossing("vol", slider_id, v) then
      params:set("vol" .. edit + 1, util.linlin(0, 127, 0.0, 1.0, v))
      prev_16n_slider_v["vol"][slider_id] = v
    end
  elseif key_1_pressed == 0 and key_2_pressed == 1 and key_3_pressed == 0 then
    if is_prev_16n_slider_v_crossing("cents", slider_id, v) then
      params:set("cents" .. edit + 1, util.linlin(0, 127, -200, 200, v))
      prev_16n_slider_v["cents"][slider_id] = v
    end
  elseif key_1_pressed == 0 and key_2_pressed == 0 and key_3_pressed == 1 then
    if is_prev_16n_slider_v_crossing("fm_index", slider_id, v) then
      params:set("fm_index" .. edit + 1, util.linlin(0, 127, 0.0, 200.0, v))
      prev_16n_slider_v["fm_index"][slider_id] = v
    end
  elseif key_1_pressed == 1 and key_2_pressed == 1 and key_3_pressed == 0 then
    if is_prev_16n_slider_v_crossing("smpl_rate", slider_id, v) then
      params:set("smpl_rate" .. edit + 1, util.linlin(0, 127, 48000, 480, v))
      prev_16n_slider_v["smpl_rate"][slider_id] = v
    end
  elseif key_1_pressed == 1 and key_2_pressed == 0 and key_3_pressed == 1 then
    if is_prev_16n_slider_v_crossing("bit_depth", slider_id, v) then
      params:set("bit_depth" .. edit + 1, util.linlin(0, 127, 24, 1, v))
      prev_16n_slider_v["bit_depth"][slider_id] = v
    end
  elseif key_1_pressed == 1 and key_2_pressed == 1 and key_3_pressed == 1 then
    if is_prev_16n_slider_v_crossing("note", slider_id, v) then
      params:set("note" .. edit + 1, v)
      prev_16n_slider_v["note"][slider_id] = v
    end
  end
  screen_dirty = true
end

function add_params()
  --set the scale note values
  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
  end
  params:add{type = "option", id = "scale_mode", name = "scale mode",
    options = scale_names, default = 5,
  action = function() set_notes() end}
  params:add{type = "number", id = "root_note", name = "root note",
  min = 0, max = 127, default = 60, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end, action = function() set_notes() end}
  params:add{type = "option", id = "16n_auto", name = "auto bind 16n", options = {"yes", "no"}, default = 1}
  params:add{type = "option", id = "16n_params_jump", name = "16n params jumps", options = {"yes", "no"}, default = 1}
  --amp slew
  params:add_control("amp_slew", "amp slew", controlspec.new(0.01, 10, 'lin', 0.01, 0.01, 's'))
  params:set_action("amp_slew", function(x) set_amp_slew(x) end)
  --set virtual faders params
  params:add_group("virtual faders", 16)
  for i = 1, 16 do
    params:add{type = "number", id = "fader" ..i, name = "fader " .. i, min = 0, max = 127, default = 0, action = function(v) virtual_slider_callback(i, v) end}
  end
  --set voice params
  for i = 1, 16 do
    params:add_group("voice " .. i .. " params", 11)
    --set voice vols
    params:add_control("vol" .. i, "vol " .. i, controlspec.new(0.0, 1.0, 'lin', 0.01, 0.0))
    params:set_action("vol" .. i, function(x) set_vol(i - 1, x) end)
    params:add{type = "number", id = "pan" ..i, name = "pan " .. i, min = -1, max = 1, default = 0, formatter = function(param) return pan_formatter(param:get()) end, action = function(x) set_synth_pan(i - 1, x) end}
    params:add{type = "number", id = "note" ..i, name = "note " .. i, min = 0, max = 127, default = 60, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end, action = function(x) set_note(i - 1, x) end}
    params:add_control("cents" .. i, "cents detune " .. i, controlspec.new(-200, 200, 'lin', 1, 0, 'cents'))
    params:set_action("cents" .. i, function(x) tune(i - 1, x) end)
    params:add_control("fm_index" .. i, "fm index " .. i, controlspec.new(0.0, 200.0, 'lin', 1.0, 3.0))
    params:set_action("fm_index" .. i, function(x) set_fm_index(i - 1, x) end)
    params:add{type = "number", id = "env" ..i, name = "env " .. i, min = 1, max = 16, default = 1, formatter = function(param) return env_formatter(param:get()) end, action = function(x) set_env(i, x) end}
    params:add_control("attack" .. i, "env attack " .. i, controlspec.new(0.01, 15.0, 'lin', 0.01, 1.0, 's'))
    params:set_action("attack" .. i, function(x) set_amp_atk(i - 1, x) end)
    params:add_control("decay" .. i, "env decay " .. i, controlspec.new(0.01, 15.0, 'lin', 0.01, 1.0, 's'))
    params:set_action("decay" .. i, function(x) set_amp_rel(i - 1, x) end)
    params:add_control("env_bias" .. i, "env bias " .. i, controlspec.new(0.0, 1.0, 'lin', 0.1, 1.0))
    params:set_action("env_bias" .. i, function(x) set_env_bias(i - 1, x) end)
    params:add_control("bit_depth" .. i, "bit depth " .. i, controlspec.new(1, 24, 'lin', 1, 24, 'bits'))
    params:set_action("bit_depth" .. i, function(x) set_bit_depth(i - 1, x) end)
    params:add_control("smpl_rate" .. i, "sample rate " .. i, controlspec.new(480, 48000, 'lin', 100, 48000, 'hz'))
    params:set_action("smpl_rate" .. i, function(x) set_sample_rate(i - 1, x) end)
  end
  params:read()
  params:bang()
end

function build_scale()
  notes = MusicUtil.generate_scale_of_length(params:get("root_note"), params:get("scale_mode"), 16)
  local num_to_add = 16 - #notes
  for i = 1, num_to_add do
    table.insert(notes, notes[16 - num_to_add])
  end
end

function set_notes()
  build_scale()
  scale_toggle = true
  for i = 1, 16 do
    params:set("note" .. i, notes[i])
  end
end

function set_amp_slew(slew_rate)
  -- set the slew rate for every voice 
  for i = 0, 15 do
    engine.amp_slew(i, slew_rate)
  end
end

function set_note(synth_num, value)
  notes[synth_num] = value
  --also reset the cents value here too
  params:set("cents" .. synth_num + 1, 0)
  engine.hz(synth_num, MusicUtil.note_num_to_freq(notes[synth_num]))
  engine.hz_lag(synth_num, 0.005)
  if scale_toggle then
    --do nothing
  end
  if not scale_toggle then
    edit = synth_num
  end
  screen_dirty = true
end

function set_freq(synth_num, value)
  engine.hz(synth_num, value)
  engine.hz_lag(synth_num, 0.005)
  edit = synth_num
  screen_dirty = true
end

function set_vol(synth_num, value)
  engine.vol(synth_num, value * 0.2)
  edit = synth_num

  -- update displayed sine value
  local s_id = (synth_num + 1)
  sliders[s_id] = math.floor(util.linlin(0.0, 1.0, 0, max_slider_size, value))

  screen_dirty = true
end

function tune(synth_num, value)
  --calculate new tuned value from cents value + midi note
  --https://music.stackexchange.com/questions/17566/how-to-calculate-the-difference-in-cents-between-a-note-and-an-arbitrary-frequen
  local detuned_freq = (math.pow(10, value / 3986)) * MusicUtil.note_num_to_freq(notes[synth_num])
  --round to 2 decimal points
  detuned_freq = math.floor((detuned_freq) * 10 / 10)
  set_freq(synth_num, detuned_freq)
  edit = synth_num
  screen_dirty = true
end

function set_env(synth_num, value)
  --env_name, env_bias, attack, decay
  params:set("env_bias" .. synth_num, envs[value][2])
  params:set("attack" .. synth_num, envs[value][3])
  params:set("decay" .. synth_num, envs[value][4])
end

function env_formatter(value)
  local env_name = envs[value][1]
  return (env_name)
end

function set_fm_index(synth_num, value)
  engine.fm_index(synth_num, value)
  edit = synth_num
  screen_dirty = true
end

function set_amp_atk(synth_num, value)
  engine.amp_atk(synth_num, value)
  edit = synth_num
  screen_dirty = true
end

function set_amp_rel(synth_num, value)
  engine.amp_rel(synth_num, value)
  edit = synth_num
  screen_dirty = true
end

function set_env_bias(synth_num, value)
  engine.env_bias(synth_num, value)
  edit = synth_num
  screen_dirty = true
end

function set_bit_depth(synth_num, value)
  engine.bit_depth(synth_num, value)
  edit = synth_num
  screen_dirty = true
end

function set_sample_rate(synth_num, value)
  engine.sample_rate(synth_num, value)
  edit = synth_num
  screen_dirty = true
end

function set_synth_pan(synth_num, value)
  engine.pan(synth_num, value)
  screen_dirty = true
end

function pan_formatter(value)
  if value == 1 then
    text = "right"
  elseif value == 0 then
    text = "middle"
  elseif value == -1 then
    text = "left"
  end
  return (text)
end

function set_pan()
  -- pan position on the bus, -1 is left, 1 is right
  if key_1_pressed == 0 and key_2_pressed == 1 and key_3_pressed == 1 then
    toggle = not toggle
    if toggle then
      --set hard l/r pan values
      for i = 1, 16 do
        if i % 2 == 0 then
          --even, pan right
          set_synth_pan(i, 1)
          params:set("pan" .. i, 1)
        elseif i % 2 == 1 then
          --odd, pan left
          set_synth_pan(i, -1)
          params:set("pan" .. i, -1)
        end
      end
    end
    if not toggle then
      for i = 1, 16 do
        set_synth_pan(i, 0)
        params:set("pan" .. i, 0)
      end
    end
  end
end

--update when a cc change is detected
m = midi.connect()
m.event = function(data)
  local d = midi.to_msg(data)
  -- if d.type == "cc" then
  -- --set all the sliders + fm values
  -- for i = 1,16 do
  -- sliders[i] = (params:get("vol" .. i))*32 - 1
  -- if sliders[i] > 32 then sliders[i] = 32 end
  -- if sliders[i] < 0 then sliders[i] = 0 end
  -- end
  -- end
  --allow root note to be set from midi keyboard - doesn't work with multiple midi devices?
  if d.type == "note_on" then
    params:set("root_note", d.note)
  end
  screen_dirty = true
end

function enc(n, delta)
  if n == 1 then
    if key_1_pressed == 0 then
      params:delta('output_level', delta)
    end
  elseif n == 2 then
    if key_1_pressed == 0 and key_2_pressed == 0 and key_3_pressed == 0 then
      --navigate up/down the list of sliders
      --accum wraps around 0-15
      accum = (accum + delta) % 16
      --edit is the slider number
      edit = accum

    elseif key_1_pressed == 0 and key_2_pressed == 0 and key_3_pressed == 1 then
      params:set("env" .. edit + 1, params:get("env" .. edit + 1) + delta)
      --env_accum = (env_accum + delta) % 16
      --env_edit is the env_values selector
      --env_edit = env_accum
      --change the AD env values
      --env_values[edit+1] = env_edit+1
      --set the env
      --set_env(edit+1, env_edit+1)

    elseif key_1_pressed == 0 and key_2_pressed == 1 and key_3_pressed == 0 then
      -- increment the note value with delta
      params:set("note" .. edit + 1, params:get("note" .. edit + 1) + delta)

    elseif key_1_pressed == 1 and key_2_pressed == 0 and key_3_pressed == 0 then
      --set sample rate
      params:set("smpl_rate" .. edit + 1, params:get("smpl_rate" .. edit + 1) + (delta) * 1000)
    end

  elseif n == 3 then
    if key_1_pressed == 0 and key_3_pressed == 0 and key_2_pressed == 0 then
      --set the slider value
      local new_v = sliders[edit + 1] + (delta * 2)
      local amp_value = util.linlin(0, max_slider_size, 0.0, 1.0, new_v)
      params:set("vol" .. edit + 1, amp_value)
    elseif key_1_pressed == 0 and key_2_pressed == 1 and key_3_pressed == 0 then
      --set the cents value to increment by
      params:set("cents" .. edit + 1, params:get("cents" .. edit + 1) + delta)

    elseif key_1_pressed == 0 and key_2_pressed == 0 and key_3_pressed == 1 then
      -- set the fm value
      params:set("fm_index" .. edit + 1, params:get("fm_index" .. edit + 1) + delta)

    elseif key_1_pressed == 1 and key_2_pressed == 0 and key_3_pressed == 0 then
      --set bit depth
      params:set("bit_depth" .. edit + 1, params:get("bit_depth" .. edit + 1) + delta)
    end
  end
  screen_dirty = true
end

function key(n, z)
  --use these keypress variables to add extra functionality on key hold
  if n == 1 and z == 1 then
    key_1_pressed = 1
  elseif n == 1 and z == 0 then
    key_1_pressed = 0
  elseif n == 2 and z == 1 then
    key_2_pressed = 1
  elseif n == 2 and z == 0 then
    key_2_pressed = 0
  elseif n == 3 and z == 1 then
    key_3_pressed = 1
  elseif n == 3 and z == 0 then
    key_3_pressed = 0
  end
  set_pan()
  screen_dirty = true
end

function redraw()
  redraw_screen()
  redraw_grid()
end

function redraw_screen()
  screen.aa(1)
  screen.line_width(2.0)
  screen.clear()

  for i = 0, 15 do
    if i == edit then
      screen.level(15)
    else
      screen.level(2)
    end
    screen.move(32 + i * 4, 62)
    screen.line(32 + i * 4, 60 - sliders[i + 1])
    screen.stroke()
  end
  screen.level(10)
  screen.line(32 + step * 4, 68)
  screen.stroke()
  --display current values
  screen.move(0, 5)
  screen.level(2)
  screen.text("note: ")
  screen.level(15)
  screen.text(MusicUtil.note_num_to_name(params:get("note" .. edit + 1), true) .. " ")
  screen.level(2)
  screen.text("detune: ")
  screen.level(15)
  screen.text(params:get("cents" .. edit + 1) .. " cents")
  screen.move(0, 12)
  screen.level(2)
  screen.text("env: ")
  screen.level(15)
  screen.text(env_formatter(params:get("env" .. edit + 1)))
  --screen.text(envs[env_values[edit+1]][1])
  --screen.text(params:get("attack" .. edit+1) .. "/" ..  params:get("decay" .. edit+1) .. " s")
  screen.level(2)
  screen.text(" fm index: ")
  screen.level(15)
  screen.text(params:get("fm_index" .. edit + 1))
  screen.move(0, 19)
  screen.level(2)
  screen.text("smpl rate: ")
  screen.level(15)
  screen.text(params:get("smpl_rate" .. edit + 1) / 1000 .. "k")
  screen.level(2)
  screen.text(" bit dpt: ")
  screen.level(15)
  screen.text(params:get("bit_depth" .. edit + 1))
  screen.move(0, 26)
  screen.level(2)
  screen.text("pan: ")
  screen.level(15)
  screen.text(pan_formatter(params:get("pan" .. edit + 1)))
  screen.level(2)
  screen.text(" master vol: ")
  screen.level(15)
  screen.text(math.floor((params:get('output_level')) * 10 / 10) .. " dB")
  screen.update()
end

function redraw_grid()
  g:all(0)
  for x = 1, grid_width do
    local col_height = grid_height - math.ceil(sliders[x] / grid_slider_scale)
    for y = col_height, grid_height do
      if monobright then
        g:led(x,y,15)
      else
        g:led(x,y,x == (edit + 1) and 8 or 4)
      end
    end
  end
  g:refresh()
end

g.key = function(x,y,z)
  if z == 1 then
    local amp_value = util.linlin(0, grid_height, 0.0, 1.0, grid_height - y)
    params:set("vol" .. x, amp_value)
    edit = x - 1
  end
  screen_dirty = true
end