--!strict
return function()
	local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
	local BrainrotMath = require(Modules:WaitForChild("BrainrotMath"))
	local Registry = require(Modules:WaitForChild("Registry"))

	describe("brainrot stats", function()
		it("combat power rises with rarity for the starter set", function()
			local prev = 0
			for _, r in Registry.Rarities do
				local best = 0
				for _, b in Registry.ByRarity[r.id] do
					best = math.max(best, BrainrotMath.combatPower(b, "Normal", 1))
				end
				expect(best > prev).to.equal(true)
				prev = best
			end
		end)

		it("mutations and levels multiply stats", function()
			local def = Registry.Brainrot.BananiniBongo
			local base = BrainrotMath.stats(def, "Normal", 1)
			local golden = BrainrotMath.stats(def, "Golden", 1)
			local leveled = BrainrotMath.stats(def, "Normal", 11)
			expect(golden.hp).to.equal(base.hp * 2)
			expect(leveled.hp > base.hp).to.equal(true)
			expect(BrainrotMath.baseIncome(def, "Rainbow", 1)).to.equal(def.zooIncome * 10)
		end)

		it("level up costs grow and stop at max level", function()
			local def = Registry.Brainrot.Cactoboom
			local c1 = BrainrotMath.levelUpCost(def, 1)
			local c5 = BrainrotMath.levelUpCost(def, 5)
			expect((c5 :: number) > (c1 :: number)).to.equal(true)
			expect(BrainrotMath.levelUpCost(def, 30)).to.equal(nil)
		end)

		it("affinity habitat pays more", function()
			local inst = { id = "Cactoboom", mut = "Normal", lvl = 1, t = 0 }
			local desert = BrainrotMath.placedIncome(inst, Registry.Habitat.Desert, 1)
			local grass = BrainrotMath.placedIncome(inst, Registry.Habitat.Grass, 1)
			expect(desert > grass).to.equal(true)
		end)
	end)

	describe("player xp", function()
		it("levels up and carries leftover xp", function()
			local need = BrainrotMath.xpToNext(1)
			local level, xp, ups = BrainrotMath.applyXp(1, 0, need + 5)
			expect(level).to.equal(2)
			expect(xp).to.equal(5)
			expect(ups).to.equal(1)
		end)
	end)
end
