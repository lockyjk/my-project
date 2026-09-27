--!strict
-- Balance targets from the design brief. If these fail after a Config change, re-tune Config
-- (run `lune run scripts/simulate 7 -v` to see the timeline).

return function()
	local PacingSim = require(script.Parent.PacingSim)

	describe("Pacing targets (idealised free player)", function()
		local result = PacingSim.run(3 * 3600, 7)

		it("buys something within 30 seconds", function()
			expect(result.firstPurchase).to.be.ok()
			expect((result.firstPurchase :: number) <= 30).to.equal(true)
		end)

		it("reaches the second zone within 5 minutes (but not trivially fast)", function()
			local t = result.zoneTimes[2]
			expect(t).to.be.ok()
			expect(t <= 300).to.equal(true)
			expect(t >= 120).to.equal(true)
		end)

		it("does not need the last zones before the first Ascension", function()
			expect(result.zoneTimes[8] == nil).to.equal(true)
		end)

		it("puts the first Ascension at 45-60 minutes (median over seeds)", function()
			local times = {}
			for seed = 1, 9 do
				local r = PacingSim.run(3 * 3600, seed)
				expect(r.ascendTime).to.be.ok()
				table.insert(times, r.ascendTime :: number)
			end
			table.sort(times)
			local median = times[5]
			expect(median >= 45 * 60).to.equal(true)
			expect(median <= 60 * 60).to.equal(true)
			-- no seed should be wildly off
			expect(times[1] >= 38 * 60).to.equal(true)
			expect(times[#times] <= 70 * 60).to.equal(true)
		end)
	end)
end
