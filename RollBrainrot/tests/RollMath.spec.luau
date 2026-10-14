--!strict
return function()
	local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
	local RollMath = require(Modules:WaitForChild("RollMath"))
	local GameConfig = require(Modules:WaitForChild("GameConfig"))

	local function sum(rows: { any }): number
		local total = 0
		for _, r in rows do
			total += r.chance
		end
		return total
	end

	describe("rarity odds", function()
		it("sum to 1 and match the base table at luck 1", function()
			local odds = RollMath.odds(1)
			expect(sum(odds)).to.be.near(1, 1e-9)
			expect(odds[1].chance).to.be.near(0.6, 1e-3)
			expect(odds[#odds].chance).to.be.near(0.0001, 1e-6)
		end)

		it("luck raises rare odds and lowers common odds", function()
			local base, lucky = RollMath.odds(1), RollMath.odds(3)
			expect(lucky[1].chance < base[1].chance).to.equal(true)
			expect(lucky[#lucky].chance > base[#base].chance).to.equal(true)
		end)

		it("respects a minimum rarity", function()
			local odds = RollMath.odds(1, RollMath.pityMinOrder())
			for _, row in odds do
				if row.rarity.order < RollMath.pityMinOrder() then
					expect(row.chance).to.equal(0)
				end
			end
			expect(sum(odds)).to.be.near(1, 1e-9)
		end)
	end)

	describe("mutations", function()
		it("sum to 1 and Normal dominates", function()
			local rows = RollMath.mutationOdds(1)
			expect(sum(rows)).to.be.near(1, 1e-9)
			expect(rows[1].mutation.id).to.equal("Normal")
			expect(rows[1].chance > 0.85).to.equal(true)
		end)
	end)

	describe("pity", function()
		it("forces the configured rarity on the threshold roll and resets", function()
			local rng = Random.new(1)
			local threshold = GameConfig.Roll.Pity.threshold
			local result, newPity = RollMath.roll(rng, 1, threshold - 1)
			expect(result.pityHit).to.equal(true)
			expect(result.rarity.order >= RollMath.pityMinOrder()).to.equal(true)
			expect(newPity).to.equal(0)
		end)

		it("never goes more than threshold rolls without a high rarity", function()
			local rng = Random.new(42)
			local pity, worst, since = 0, 0, 0
			for _ = 1, 5000 do
				local result
				result, pity = RollMath.roll(rng, 1, pity)
				since += 1
				if result.rarity.order >= RollMath.pityMinOrder() then
					worst = math.max(worst, since)
					since = 0
				end
			end
			expect(worst <= GameConfig.Roll.Pity.threshold).to.equal(true)
		end)

		it("rolls a sensible distribution", function()
			local rng = Random.new(7)
			local commons, n = 0, 4000
			for _ = 1, n do
				local result = RollMath.roll(rng, 1, 0)
				if result.rarity.id == "Common" then
					commons += 1
				end
			end
			expect(commons / n).to.be.near(0.6, 0.04)
		end)
	end)
end
