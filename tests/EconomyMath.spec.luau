--!strict
return function()
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local Config = require(Shared:WaitForChild("Config"))
	local Defs = require(Shared:WaitForChild("Defs"))
	local EconomyMath = require(Shared:WaitForChild("EconomyMath"))

	describe("upgrades", function()
		it("costs grow geometrically and are integers", function()
			local def = Defs.Upgrade.JarCapacity
			expect(EconomyMath.upgradeCost(def, 0)).to.equal(def.baseCost)
			local c5 = EconomyMath.upgradeCost(def, 5)
			expect(c5).to.equal(math.floor(def.baseCost * def.costGrowth ^ 5))
			expect(c5 % 1).to.equal(0)
		end)

		it("clamps values to min/max", function()
			expect(EconomyMath.upgradeValue(Defs.Upgrade.CatchSpeed, 1000)).to.equal(Defs.Upgrade.CatchSpeed.min)
			expect(EconomyMath.upgradeValue(Defs.Upgrade.WalkSpeed, 1000)).to.equal(Defs.Upgrade.WalkSpeed.max)
		end)

		it("jar capacity applies bonus", function()
			local base = EconomyMath.jarCapacity(3, 0)
			expect(EconomyMath.jarCapacity(3, 0.5)).to.equal(math.floor(EconomyMath.upgradeValue(Defs.Upgrade.JarCapacity, 3) * 1.5))
			expect(base > 0).to.equal(true)
		end)

		it("catch cooldown is never below a floor even with huge bonuses", function()
			local cd = EconomyMath.catchCooldown(30, 5, 10)
			expect(cd > 0.05).to.equal(true)
		end)
	end)

	describe("multipliers", function()
		local neutral: EconomyMath.MultContext = {
			ascensions = 0,
			petBonus = 0,
			additive = 0,
			doubleCharge = false,
			potion = 1,
			storm = 1,
			event = 1,
		}

		it("is 1 with nothing active", function()
			expect(EconomyMath.chargeMultiplier(neutral)).to.equal(1)
		end)

		it("stacks buckets multiplicatively", function()
			local ctx = table.clone(neutral)
			ctx.ascensions = 1
			ctx.petBonus = 1
			ctx.doubleCharge = true
			local expected = (1 + Config.Ascension.ChargeBonusPerAscension) * 2 * 2
			expect(EconomyMath.chargeMultiplier(ctx)).to.be.near(expected)
		end)

		it("spirit values round and respect shiny", function()
			local normal = EconomyMath.spiritValue(2, 4, false, 1)
			local shiny = EconomyMath.spiritValue(2, 4, true, 1)
			expect(normal).to.equal(8)
			expect(shiny).to.equal(8 * Config.Economy.ShinyValueMult)
			expect(EconomyMath.spiritValue(0.01, 1, false, 1)).to.equal(1)
		end)

		it("VIP zone scales from best zone", function()
			local lagoon = Defs.Zone.RainbowLagoon
			expect(EconomyMath.zoneValueMult(lagoon, 100)).to.be.near(100 * (lagoon.bestZoneScale :: number))
			expect(EconomyMath.zoneValueMult(Defs.Zone.ThunderPeaks, 100)).to.equal(Defs.Zone.ThunderPeaks.valueMult)
		end)
	end)

	describe("zones", function()
		it("each main zone is 3-5x more lucrative than the last", function()
			for i = 2, #Defs.MainZones do
				local ratio = Defs.MainZones[i].valueMult / Defs.MainZones[i - 1].valueMult
				expect(ratio >= 3 and ratio <= 5).to.equal(true)
			end
		end)

		it("has at least 10 main zones with increasing gates", function()
			expect(#Defs.MainZones >= 10).to.equal(true)
			for i = 2, #Defs.MainZones do
				expect(Defs.MainZones[i].gateCost > Defs.MainZones[i - 1].gateCost).to.equal(true)
			end
		end)
	end)

	describe("ascension", function()
		it("cost grows and tokens reward overflow up to a cap", function()
			expect(EconomyMath.ascensionCost(1) > EconomyMath.ascensionCost(0)).to.equal(true)
			local cost = EconomyMath.ascensionCost(0)
			expect(EconomyMath.ascensionTokens(0, cost)).to.equal(Config.Ascension.BaseTokens)
			expect(EconomyMath.ascensionTokens(0, cost * 4)).to.equal(Config.Ascension.BaseTokens + 2)
			expect(EconomyMath.ascensionTokens(0, cost * 1e12)).to.equal(Config.Ascension.BaseTokens + Config.Ascension.OverflowTokenCap)
		end)

		it("sums tree stats with level caps", function()
			local tree = { StormHeart = 2, DeepJar = 1, Unknown = 5 }
			expect(EconomyMath.ascStat(tree, "Charge")).to.be.near(0.3)
			expect(EconomyMath.ascStat(tree, "Capacity")).to.be.near(0.2)
			expect(EconomyMath.ascStat({ ExtraSlot = 99 }, "Slots")).to.equal(3)
		end)
	end)

	describe("eggs", function()
		it("odds sum to 1 and luck only boosts Rare+", function()
			for _, egg in Config.Eggs do
				local odds = EconomyMath.eggOdds(egg, 1)
				local total = 0
				for _, o in odds do
					total += o.chance
					expect(o.chance).to.be.near(o.baseChance, 1e-9)
				end
				expect(total).to.be.near(1, 1e-9)
			end
			local egg = Defs.Egg.DrizzleEgg
			local lucky = EconomyMath.eggOdds(egg, 2)
			local commonBase = EconomyMath.eggOdds(egg, 1)[1].chance
			expect(lucky[1].chance < commonBase).to.equal(true)
			expect(lucky[#lucky].chance > EconomyMath.eggOdds(egg, 1)[#lucky].chance).to.equal(true)
		end)

		it("picks by cumulative chance", function()
			local odds = {
				{ pet = "A", chance = 0.5, baseChance = 0.5 },
				{ pet = "B", chance = 0.5, baseChance = 0.5 },
			}
			expect(EconomyMath.pickFromOdds(odds, 0)).to.equal("A")
			expect(EconomyMath.pickFromOdds(odds, 0.49)).to.equal("A")
			expect(EconomyMath.pickFromOdds(odds, 0.5)).to.equal("B")
			expect(EconomyMath.pickFromOdds(odds, 0.9999999)).to.equal("B")
		end)

		it("paid eggs contain no Secret pets", function()
			for _, egg in Config.Eggs do
				if egg.currency == "Robux" then
					for _, entry in egg.pets do
						expect(Defs.Pet[entry.pet].rarity ~= "Secret").to.equal(true)
					end
				end
			end
		end)

		it("egg discount never goes below 30%", function()
			expect(EconomyMath.eggCost(Defs.Egg.DrizzleEgg, 5)).to.equal(math.floor(Defs.Egg.DrizzleEgg.cost * 0.3))
		end)
	end)

	describe("pets", function()
		it("fusion tiers multiply power", function()
			local base = EconomyMath.petPower("DropletPup", 1)
			expect(EconomyMath.petPower("DropletPup", 2)).to.be.near(base * Config.Fusion.Tiers[2].powerMult)
			expect(EconomyMath.petPower("Nope", 1)).to.equal(0)
		end)

		it("bestPowers takes the top N", function()
			expect(EconomyMath.bestPowers({ 1, 5, 3, 4 }, 2)).to.equal(9)
			expect(EconomyMath.bestPowers({ 1 }, 3)).to.equal(1)
		end)

		it("pet score ranks rarity first", function()
			expect(EconomyMath.petScore("Nullstorm", 1) > EconomyMath.petScore("EyeOfEternity", 4)).to.equal(true)
		end)
	end)

	describe("storm pass", function()
		it("tier math round-trips", function()
			expect((EconomyMath.passTier(0))).to.equal(0)
			local xp = EconomyMath.passTotalXPForTier(10)
			local tier, into = EconomyMath.passTier(xp)
			expect(tier).to.equal(10)
			expect(into).to.equal(0)
			expect((EconomyMath.passTier(1e12))).to.equal(Config.StormPass.Tiers)
		end)
	end)

	describe("offline + leaderboard encoding", function()
		it("offline earnings respect min time and cap", function()
			expect(EconomyMath.offlineEarnings(10, 100, 8)).to.equal(0)
			local capped = EconomyMath.offlineEarnings(1e9, 100, 8)
			expect(capped).to.equal(math.floor(8 * 3600 * 100 * Config.Offline.IncomeFraction))
		end)

		it("log encoding is monotonic and decodes approximately", function()
			local a, b = EconomyMath.encodeLog(1e6), EconomyMath.encodeLog(2e6)
			expect(b > a).to.equal(true)
			expect(EconomyMath.decodeLog(EconomyMath.encodeLog(123456)) / 123456).to.be.near(1, 1e-4)
			expect(EconomyMath.encodeLog(1e300) < 2 ^ 53).to.equal(true)
		end)
	end)
end
