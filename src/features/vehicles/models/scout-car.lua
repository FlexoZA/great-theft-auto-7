-- Scout car: Half-Life 2's buggy. A bare tube frame on long-travel
-- suspension and big tyres, an engine at the back and a tau cannon bolted
-- on, and an AK on a pintle for the driver: quick off the line, light, and
-- agile, but there is not much of it to soak up bullets.
return {
  name = "Scout Car",
  price = 240,
  hitpoints = 110,
  topSpeed = 590,
  acceleration = 560,
  weight = 750,
  engine = "v8",
  turning = 3.1,
  length = 52,
  gun = "ak47", -- bolted on: the driver fires it (endless rounds, still reloaded), not their own
}
