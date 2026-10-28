-- A stand-in for LÖVE, so the audit can load the whole game under plain
-- LuaJIT (CI has no window, no sound card and no LÖVE). Nothing is drawn or
-- heard: graphics calls do nothing, sounds are silent, but every number the
-- game reads back (window size, font widths, random numbers, sample data)
-- is a real one, so the code paths behind them run as they do in the game.
--
-- Sounds are recorded (`Stub.sounds`): every Source played and the volume
-- it was given, which is how the audit hears whether a map has music.

local Stub = {
  sounds = {}, -- every Source made: { path, data, played, volume, looping, created, lastPlay, duration }
  drawCalls = 0, -- shapes, images and text drawn so far
  W = 1280,
  H = 720,
}

local function noop() end

-- An object every method of which does nothing (and returns nothing): a
-- canvas, an image, a mesh, a shader, a quad.
local function dummy(fields)
  return setmetatable(fields or {}, {
    __index = function()
      return noop
    end,
  })
end

local function newFont(size)
  size = tonumber(size) or 12
  local font = dummy()
  font.getHeight = function()
    return size
  end
  font.getWidth = function(_, text)
    return #tostring(text or "") * size * 0.55
  end
  font.getWrap = function(self, text, limit)
    text = tostring(text or "")
    local lines, width = {}, 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = line
      width = math.max(width, math.min(self:getWidth(line), limit or math.huge))
    end
    return width, lines
  end
  font.getLineHeight = function()
    return 1
  end
  font.getBaseline = function()
    return size * 0.8
  end
  font.getAscent = function()
    return size * 0.8
  end
  font.getDescent = function()
    return size * 0.2
  end
  return font
end

local function newCanvas(w, h)
  local canvas = dummy()
  w, h = w or Stub.W, h or Stub.H
  canvas.getDimensions = function()
    return w, h
  end
  canvas.getWidth = function()
    return w
  end
  canvas.getHeight = function()
    return h
  end
  return canvas
end

local function newImageData(w, h)
  local data = newCanvas(w, h)
  local pixels = {}
  data.setPixel = function(_, x, y, r, g, b, a)
    pixels[y * w + x] = { r, g, b, a }
  end
  data.getPixel = function(_, x, y)
    local p = pixels[y * w + x]
    if p then
      return p[1], p[2], p[3], p[4]
    end
    return 0, 0, 0, 0
  end
  data.mapPixel = function(self, fn)
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        self:setPixel(x, y, fn(x, y, self:getPixel(x, y)))
      end
    end
  end
  return data
end

local function newRandomGenerator(seed)
  -- Park-Miller, seeded: the same seed gives the same map every run.
  local state = math.floor(tonumber(seed) or 1) % 2147483647
  if state <= 0 then
    state = state + 2147483646
  end
  local rng = {}
  local function nextFloat()
    state = (state * 16807) % 2147483647
    return (state - 1) / 2147483646
  end
  function rng.random(_, a, b)
    local r = nextFloat()
    if a == nil then
      return r
    end
    if b == nil then
      a, b = 1, a
    end
    return math.floor(a + r * (b - a + 1))
  end
  function rng.randomNormal(_, stddev, mean)
    local u1, u2 = math.max(nextFloat(), 1e-9), nextFloat()
    return (mean or 0) + (stddev or 1) * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
  end
  function rng.setSeed(_, s)
    state = math.floor(tonumber(s) or 1) % 2147483647
  end
  function rng.getSeed()
    return state
  end
  function rng.getState()
    return tostring(state)
  end
  function rng.setState(_, s)
    state = tonumber(s) or state
  end
  return rng
end

local ffi = require("ffi")

-- Real sample memory, so the synth (src/audio/synth.lua) writes its sounds
-- through the FFI pointer at full speed, as it does in LÖVE.
local function newSoundData(samples, rate)
  if type(samples) ~= "number" then
    samples = 1 -- a file on disk: nothing to read here
  end
  rate = rate or 44100
  local memory = ffi.new("int16_t[?]", math.max(1, samples))
  local sd = {}
  function sd.getFFIPointer()
    return memory
  end
  function sd.setSample(_, i, v)
    memory[i] = math.floor(v * 32767 + 0.5)
  end
  function sd.getSample(_, i)
    return memory[i] / 32767
  end
  function sd.getSampleCount()
    return samples
  end
  function sd.getSampleRate()
    return rate
  end
  function sd.getChannelCount()
    return 1
  end
  function sd.getBitDepth()
    return 16
  end
  function sd.getDuration()
    return samples / rate
  end
  sd.release = noop
  return sd
end

local function newSource(what, kind)
  local record = {
    path = type(what) == "string" and what or "<generated>",
    data = what, -- the same SoundData behind two sources is the same sound
    kind = kind,
    played = 0,
    volume = 1,
    created = Stub.clock,
    -- Seconds long, when it was made here from samples (the synth's music is).
    duration = type(what) == "table" and what.getSampleCount and what:getSampleCount() / what:getSampleRate() or 0,
  }
  -- What it sounds like, in a few numbers: the same tune gives the same
  -- signature in any process.
  if record.duration > 0 then
    local sum, n = 0, what:getSampleCount()
    for i = 0, n - 1, math.max(1, math.floor(n / 4096)) do
      sum = sum + math.abs(what:getSample(i))
    end
    record.signature = ("%.2f:%.4f"):format(record.duration, sum)
  else
    record.signature = record.path
  end
  Stub.sounds[#Stub.sounds + 1] = record
  local source = {}
  local playing = false
  function source.play()
    playing = true
    record.played = record.played + 1
    record.lastPlay = Stub.clock
    return true
  end
  function source.stop()
    playing = false
  end
  function source.pause()
    playing = false
  end
  function source.isPlaying()
    return playing
  end
  function source.setVolume(_, v)
    record.volume = v
  end
  function source.getVolume()
    return record.volume
  end
  function source.setLooping(_, on)
    record.looping = on
  end
  function source.isLooping()
    return record.looping
  end
  function source.clone()
    return newSource(what, kind)
  end
  function source.tell()
    return 0
  end
  function source.getDuration()
    return record.duration
  end
  function source.getChannelCount()
    return 1
  end
  function source.getPitch()
    return 1
  end
  return setmetatable(source, {
    __index = function()
      return noop
    end,
  })
end

local function directoryItems(path)
  local items = {}
  local pipe = io.popen('ls -1 "' .. path .. '" 2>/dev/null')
  if pipe then
    for line in pipe:lines() do
      items[#items + 1] = line
    end
    pipe:close()
  end
  return items
end

local function fileInfo(path, want)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  -- A directory opens on Linux but will not read.
  local _, err = f:read(1)
  f:close()
  local kind = (err and err:find("directory")) and "directory" or "file"
  if want and want ~= kind then
    return nil
  end
  return { type = kind, size = 0, modtime = 0 }
end

-- An in-process stand-in for enet: the one listening host and every host
-- that connects to it pass messages through queues, in order, as reliable
-- ENet would on a perfect line. Each `service` hands out one event.
function Stub.loopback()
  local listening = nil
  local nextIndex = 0

  local function newHost(address)
    local host = { queue = {}, peers = {} }
    function host.service()
      return table.remove(host.queue, 1)
    end
    function host.connect(self, _)
      if not listening then
        return nil
      end
      nextIndex = nextIndex + 1
      local mine, theirs = { host = self }, { host = listening }
      local function makePeer(peer, other, index)
        function peer.index()
          return index
        end
        function peer.send(_, data)
          if not peer.closed then
            local q = other.host.queue
            q[#q + 1] = { type = "receive", peer = other, data = data }
          end
        end
        function peer.disconnect()
          if not peer.closed then
            peer.closed, other.closed = true, true
            local q = other.host.queue
            q[#q + 1] = { type = "disconnect", peer = other }
          end
        end
        peer.disconnect_later = peer.disconnect
        peer.disconnect_now = peer.disconnect
        function peer.reset()
          peer.closed = true
        end
        peer.ping_interval = noop
        peer.timeout = noop
        function peer.round_trip_time()
          return 1
        end
      end
      makePeer(mine, theirs, nextIndex)
      makePeer(theirs, mine, nextIndex)
      listening.queue[#listening.queue + 1] = { type = "connect", peer = theirs }
      self.queue[#self.queue + 1] = { type = "connect", peer = mine }
      return mine
    end
    host.flush = noop
    host.destroy = noop
    host.broadcast = noop
    function host.get_socket_address()
      return address or "127.0.0.1:0"
    end
    return host
  end

  return {
    host_create = function(address)
      local host = newHost(address)
      if address then
        listening = host
      end
      return host
    end,
  }
end

local mouse = { x = Stub.W / 2, y = Stub.H / 2, down = {} }

--- Install the stand-in as the global `love` and the native modules the
--- game requires (enet, socket, utf8). `root` is the repo's top folder.
function Stub.install()
  Stub.clock = 0
  local graphics = setmetatable({
    getDimensions = function()
      return Stub.W, Stub.H
    end,
    getWidth = function()
      return Stub.W
    end,
    getHeight = function()
      return Stub.H
    end,
    newFont = function(a, b)
      return newFont(type(a) == "number" and a or b)
    end,
    setNewFont = function(a, b)
      return newFont(type(a) == "number" and a or b)
    end,
    getFont = function()
      return newFont(12)
    end,
    newCanvas = newCanvas,
    newImage = function()
      return newCanvas(32, 32)
    end,
    newArrayImage = function()
      return newCanvas(32, 32)
    end,
    newQuad = function()
      return dummy()
    end,
    newMesh = function()
      return dummy()
    end,
    newShader = function()
      return dummy()
    end,
    newSpriteBatch = function()
      return dummy()
    end,
    newParticleSystem = function()
      return dummy()
    end,
    getBackgroundColor = function()
      return 0, 0, 0, 1
    end,
    getColor = function()
      return 1, 1, 1, 1
    end,
    getLineWidth = function()
      return 1
    end,
    getScissor = function()
      return nil
    end,
    getCanvas = function()
      return nil
    end,
    getBlendMode = function()
      return "alpha", "alphamultiply"
    end,
    getStats = function()
      return { drawcalls = 0 }
    end,
    transformPoint = function(x, y)
      return x, y
    end,
    inverseTransformPoint = function(x, y)
      return x, y
    end,
    getDPIScale = function()
      return 1
    end,
  }, {
    __index = function()
      return noop
    end,
  })

  -- Count what is drawn, so the audit can tell whether a feature drew anything.
  for _, name in ipairs({ "rectangle", "circle", "ellipse", "arc", "polygon", "line", "points", "draw", "print",
    "printf", "drawInstanced", "drawLayer" }) do
    graphics[name] = function()
      Stub.drawCalls = Stub.drawCalls + 1
    end
  end

  _G.love = {
    graphics = graphics,
    audio = setmetatable({
      newSource = newSource,
      getPosition = function()
        return 0, 0, 0
      end,
      getActiveSourceCount = function()
        return 0
      end,
    }, {
      __index = function()
        return noop
      end,
    }),
    sound = { newSoundData = newSoundData, newDecoder = dummy },
    image = {
      newImageData = function(w, h)
        if type(w) ~= "number" then
          return newImageData(32, 32)
        end
        return newImageData(w, h)
      end,
    },
    math = {
      random = function(a, b)
        if a == nil then
          return math.random()
        elseif b == nil then
          return math.random(a)
        end
        return math.random(a, b)
      end,
      randomNormal = function(stddev, mean)
        return (mean or 0) + (stddev or 1) * (math.random() + math.random() + math.random() - 1.5)
      end,
      newRandomGenerator = newRandomGenerator,
      noise = function(x, y, z)
        -- Smooth enough, in 0..1, and the same for the same input.
        local v = math.sin((x or 0) * 12.9898 + (y or 0) * 78.233 + (z or 0) * 37.719) * 0.5 + 0.5
        return v
      end,
      triangulate = function(...)
        local p = select("#", ...) == 1 and ... or { ... }
        local tris = {}
        for i = 3, #p / 2 - 0 do
          if i * 2 <= #p then
            tris[#tris + 1] = { p[1], p[2], p[i * 2 - 3], p[i * 2 - 2], p[i * 2 - 1], p[i * 2] }
          end
        end
        return tris
      end,
      isConvex = function()
        return true
      end,
      setRandomSeed = function(s)
        math.randomseed(s)
      end,
      getRandomSeed = function()
        return 0
      end,
      colorFromBytes = function(r, g, b, a)
        return r / 255, g / 255, b / 255, a and a / 255
      end,
      gammaToLinear = function(...)
        return ...
      end,
      linearToGamma = function(...)
        return ...
      end,
    },
    timer = {
      getTime = function()
        return Stub.clock
      end,
      getFPS = function()
        return 60
      end,
      getDelta = function()
        return 1 / 60
      end,
      sleep = noop,
      step = function()
        return 1 / 60
      end,
    },
    filesystem = {
      getDirectoryItems = directoryItems,
      getInfo = fileInfo,
      read = function(path)
        local f = io.open(path, "rb")
        if not f then
          return nil, "not found"
        end
        local s = f:read("*a")
        f:close()
        return s, #s
      end,
      load = function(path)
        return loadfile(path)
      end,
      write = function()
        return true
      end,
      append = function()
        return true
      end,
      remove = function()
        return true
      end,
      createDirectory = function()
        return true
      end,
      getSaveDirectory = function()
        return "/nonexistent/audit-saves"
      end,
      setIdentity = noop,
      lines = function(path)
        return io.lines(path)
      end,
      exists = function(path)
        return fileInfo(path) ~= nil
      end,
    },
    mouse = setmetatable({
      getPosition = function()
        return mouse.x, mouse.y
      end,
      getX = function()
        return mouse.x
      end,
      getY = function()
        return mouse.y
      end,
      isDown = function(b)
        return mouse.down[b] == true
      end,
      isVisible = function()
        return true
      end,
      isGrabbed = function()
        return false
      end,
      setPosition = function(x, y)
        mouse.x, mouse.y = x, y
      end,
      getSystemCursor = function()
        return dummy()
      end,
    }, {
      __index = function()
        return noop
      end,
    }),
    keyboard = setmetatable({
      isDown = function()
        return false
      end,
      isScancodeDown = function()
        return false
      end,
      getKeyFromScancode = function(k)
        return k
      end,
      getScancodeFromKey = function(k)
        return k
      end,
    }, {
      __index = function()
        return noop
      end,
    }),
    window = setmetatable({
      getMode = function()
        return Stub.W, Stub.H, { fullscreen = false, vsync = 1, msaa = 0 }
      end,
      getDimensions = function()
        return Stub.W, Stub.H
      end,
      getDesktopDimensions = function()
        return 1920, 1080
      end,
      isOpen = function()
        return true
      end,
      getFullscreen = function()
        return false
      end,
      getDPIScale = function()
        return 1
      end,
    }, {
      __index = function()
        return noop
      end,
    }),
    data = {
      compress = function(_, _, s)
        return s
      end,
      decompress = function(_, _, s)
        return s
      end,
      encode = function(_, _, s)
        return s
      end,
      decode = function(_, _, s)
        return s
      end,
      hash = function(_, s)
        return tostring(#tostring(s))
      end,
    },
    event = { quit = noop, push = noop, pump = noop, poll = function()
      return noop
    end },
    system = {
      getOS = function()
        return "Linux"
      end,
      getClipboardText = function()
        return ""
      end,
      setClipboardText = noop,
      getProcessorCount = function()
        return 1
      end,
    },
    joystick = { getJoysticks = function()
      return {}
    end },
    getVersion = function()
      return 11, 5, 0, "Mysterious Mysteries"
    end,
    errorhandler = nil,
  }

  -- Native modules LÖVE ships: no sockets here, the audit runs host and
  -- client in one process (harness.lua joins them back to back).
  package.preload["enet"] = function()
    return Stub.loopback()
  end
  package.preload["socket"] = function()
    return {
      gettime = function()
        return Stub.clock
      end,
      udp = function()
        return dummy({
          receivefrom = function()
            return nil, "timeout"
          end,
          receive = function()
            return nil, "timeout"
          end,
        })
      end,
      dns = { toip = function(h)
        return h
      end },
    }
  end
  package.preload["socket.core"] = package.preload["socket"]
  package.preload["utf8"] = function()
    local utf8 = { charpattern = "[\0-\x7F\xC2-\xF4][\x80-\xBF]*" }
    function utf8.len(s)
      local _, n = tostring(s):gsub("[^\128-\191]", "")
      return n
    end
    function utf8.offset(s, n)
      if n == 0 then
        return 1
      end
      local count = 0
      for i = 1, #s do
        local c = s:byte(i)
        if c < 128 or c >= 192 then
          count = count + 1
          if count == n then
            return i
          end
        end
      end
      if n == count + 1 or n < 0 then
        return #s + 1 + (n < 0 and n + 1 or 0)
      end
      return nil
    end
    function utf8.char(...)
      local out = {}
      for _, c in ipairs({ ... }) do
        out[#out + 1] = c < 128 and string.char(c) or "?"
      end
      return table.concat(out)
    end
    function utf8.codes(s)
      local i = 0
      return function()
        i = i + 1
        if i <= #s then
          return i, s:byte(i)
        end
      end
    end
    function utf8.codepoint(s, i)
      return s:byte(i or 1)
    end
    return utf8
  end
end

--- Move the clock the game reads (`love.timer.getTime`) on by `dt`.
function Stub.advance(dt)
  Stub.clock = Stub.clock + dt
end

Stub.mouse = mouse

return Stub
