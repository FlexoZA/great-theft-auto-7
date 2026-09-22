-- Pixel-art helpers: build images from character grids, nearest-neighbour
-- scaling, and a canvas you draw on at tiny resolution and blow up.

local Pixel = {}

--- grid: list of equal-length strings; palette: char -> {r, g, b[, a]}.
--- Characters missing from the palette are transparent.
function Pixel.imageData(grid, palette)
  local h, w = #grid, #grid[1]
  local img = love.image.newImageData(w, h)
  for y, row in ipairs(grid) do
    for x = 1, w do
      local c = palette[row:sub(x, x)]
      if c then
        img:setPixel(x - 1, y - 1, c[1], c[2], c[3], c[4] or 1)
      end
    end
  end
  return img
end

function Pixel.image(grid, palette)
  local img = love.graphics.newImage(Pixel.imageData(grid, palette))
  img:setFilter("nearest", "nearest")
  return img
end

--- Nearest-neighbour resample of `src` into a new w x h ImageData, keeping
--- aspect ratio and centring. Used for the window icon.
function Pixel.fit(src, w, h)
  local sw, sh = src:getDimensions()
  local scale = math.min(w / sw, h / sh)
  local dw, dh = sw * scale, sh * scale
  local ox, oy = (w - dw) / 2, (h - dh) / 2
  local out = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local sx = math.floor((x - ox) / scale)
      local sy = math.floor((y - oy) / scale)
      if sx >= 0 and sy >= 0 and sx < sw and sy < sh then
        out:setPixel(x, y, src:getPixel(sx, sy))
      end
    end
  end
  return out
end

--- A canvas meant to be drawn on at low resolution and scaled up crisply.
function Pixel.canvas(w, h)
  local c = love.graphics.newCanvas(w, h)
  c:setFilter("nearest", "nearest")
  return c
end

return Pixel
