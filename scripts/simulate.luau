--!nocheck
-- Prints the pacing timeline: `lune run scripts/simulate [seed]`
local process = require("@lune/process")
process.env.LOADER_ONLY = "1"
local runner = require("./run-tests")
local sim = runner.require(runner.tests.PacingSim)
local r = sim.run(3 * 3600, tonumber(process.args[1]) or 7, process.args[2] == "-v")
for _, e in r.events do
	print(string.format("%6.0fs  %5.1f min  %s", e.t, e.t / 60, e.text))
end
