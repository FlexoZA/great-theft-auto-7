-- The "7": the game's logo, as a pixel grid. Used on the menu and as the
-- window icon.

local Pixel = require("src.art.pixel")

local Logo = {}

local PALETTE = {
  k = { 0.08, 0.04, 0.05 }, -- outline
  w = { 1.00, 0.95, 0.70 }, -- top highlight
  g = { 0.98, 0.62, 0.12 }, -- gold
  o = { 0.90, 0.42, 0.08 }, -- orange
  d = { 0.60, 0.22, 0.05 }, -- dark bevel
}

Logo.GRID = {
  "kkkkkkkkkkkkkkkk",
  "kwwwwwwwwwwwwwwk",
  "kwggggggggggggwk",
  "kgggggggggggggok",
  "koooooooooooooook",
  "kkkkkkkkkkkoooook",
  "..........kooook",
  ".........kooook.",
  ".........kgooook",
  "........kgooook.",
  "........kgooook.",
  ".......kggooook.",
  ".......kggoook..",
  "......kggoook...",
  "......kggoook...",
  ".....kggoook....",
  ".....kggoook....",
  "....kggoook.....",
  "....kgddddk.....",
  "....kkkkkkk.....",
}

local image, icon

function Logo.image()
  if not image then
    image = Pixel.image(Logo.GRID, PALETTE)
  end
  return image
end

--- 32x32 ImageData for love.window.setIcon.
function Logo.icon()
  if not icon then
    icon = Pixel.fit(Pixel.imageData(Logo.GRID, PALETTE), 32, 32)
  end
  return icon
end

--- Draw with a hard drop shadow. scale is the pixel size.
function Logo.draw(x, y, scale)
  local img = Logo.image()
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.draw(img, x + scale, y + scale, 0, scale, scale)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(img, x, y, 0, scale, scale)
end

return Logo
