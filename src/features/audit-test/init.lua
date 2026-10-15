-- Deliberately broken, to test that the audit blocks a merge into staging.
-- A feature must return a table; this one returns nothing, so the game
-- can't load. Never merge this branch: close the pull request and delete it.
local AuditTest = { name = "audit-test" }
local _ = AuditTest
