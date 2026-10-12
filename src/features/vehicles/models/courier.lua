-- Courier: Grey City's armoured runner, the car VEX's couriers drive. A low
-- wedge plated over with armour, neon down its flanks, and a minigun in a
-- turret on the roof that the driver fires: it winds up first, then
-- shreds whatever is chasing you. Lent to everyone on the Overpass.
return {
  name = "Courier",
  price = 600,
  hitpoints = 180, -- the plates: more than an SUV takes
  topSpeed = 560,
  acceleration = 460,
  weight = 1500,
  engine = "v8",
  turning = 2.7,
  length = 50,
  time = 90,
  gun = "minigun", -- bolted on: the driver fires it (endless rounds, still reloaded), not their own
}
