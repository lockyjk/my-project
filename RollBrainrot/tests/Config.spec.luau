--!strict
return function()
	local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
	local Registry = require(Modules:WaitForChild("Registry"))

	describe("config", function()
		it("has no broken cross references", function()
			local errors = Registry.validate()
			expect(#errors).to.equal(0)
		end)

		it("defines at least 8 Brainrots covering every rarity", function()
			expect(#Registry.Brainrots >= 8).to.equal(true)
			for _, r in Registry.Rarities do
				expect(#Registry.RollPool[r.id] > 0).to.equal(true)
			end
		end)

		it("ends every arena with a boss wave", function()
			for _, arena in Registry.Arenas do
				local last = arena.waves[#arena.waves]
				expect(last.boss).to.equal(true)
				expect(Registry.Monster[last.spawns[1].monster].kind).to.equal("Boss")
			end
		end)
	end)
end
