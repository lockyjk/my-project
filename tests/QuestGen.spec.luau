--!strict
return function()
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local Config = require(Shared:WaitForChild("Config"))
	local Defs = require(Shared:WaitForChild("Defs"))
	local QuestGen = require(Shared:WaitForChild("QuestGen"))
	local PassRewards = require(Shared:WaitForChild("PassRewards"))
	local Schedule = require(Shared:WaitForChild("Schedule"))

	local ctx = { userId = 12345, incomePerSecond = 50, unlockedZones = { "DrizzleMeadows", "BreezyBluffs" } }

	describe("QuestGen", function()
		it("creates 3 daily and 5 weekly quests with distinct kinds", function()
			for day = 1, 30 do
				local daily = QuestGen.generate(day, true, ctx)
				expect(#daily).to.equal(Config.Quests.DailyCount)
				local weekly = QuestGen.generate(day, false, ctx)
				expect(#weekly).to.equal(Config.Quests.WeeklyCount)
				local kinds = {}
				for _, q in daily do
					local kind = Defs.Quest[q.template].kind
					expect(kinds[kind]).to.equal(nil)
					kinds[kind] = true
					expect(q.target >= 1).to.equal(true)
					expect(q.progress).to.equal(0)
				end
			end
		end)

		it("is deterministic per player and period, and varies between players/days", function()
			local a = QuestGen.generate(100, true, ctx)
			local b = QuestGen.generate(100, true, ctx)
			for i = 1, #a do
				expect(a[i].template).to.equal(b[i].template)
			end
			local different = false
			for day = 101, 110 do
				local c = QuestGen.generate(day, true, ctx)
				if c[1].template ~= a[1].template then
					different = true
				end
			end
			expect(different).to.equal(true)
		end)

		it("scales Earn targets with income and picks unlocked zones for Explore", function()
			local earn = Defs.Quest.D_Earn
			local low = QuestGen.target(earn, { userId = 1, incomePerSecond = 1, unlockedZones = {} })
			local high = QuestGen.target(earn, { userId = 1, incomePerSecond = 1e6, unlockedZones = {} })
			expect(high > low * 1000).to.equal(true)
			for day = 1, 60 do
				for _, q in QuestGen.generate(day, true, ctx) do
					if q.zone then
						expect(table.find(ctx.unlockedZones, q.zone) ~= nil).to.equal(true)
					end
				end
			end
		end)

		it("routes progress: catches in the chosen zone advance Explore quests", function()
			local explore = Defs.Quest.D_Explore
			local quest = { template = "D_Explore", target = 10, progress = 0, claimed = false, zone = "BreezyBluffs" }
			expect(QuestGen.progressFor(explore, quest, "Catch", 1, "BreezyBluffs")).to.equal(1)
			expect(QuestGen.progressFor(explore, quest, "Catch", 1, "DrizzleMeadows")).to.equal(0)
			expect(QuestGen.progressFor(Defs.Quest.D_Hatch, quest, "Hatch", 3, nil)).to.equal(3)
		end)

		it("rounds to friendly numbers", function()
			expect(QuestGen.niceRound(1234)).to.equal(1000)
			expect(QuestGen.niceRound(1600)).to.equal(1500)
			expect(QuestGen.niceRound(3.4)).to.equal(3)
		end)
	end)

	describe("Storm Pass", function()
		it("has free and premium rewards for all tiers", function()
			for t = 1, Config.StormPass.Tiers do
				local r = PassRewards.forTier(t)
				expect(r.free).to.be.ok()
				expect(r.premium).to.be.ok()
				if r.free.pet then
					expect(Defs.Pet[r.free.pet]).to.be.ok()
				end
				if r.premium.pet then
					expect(Defs.Pet[r.premium.pet]).to.be.ok()
				end
				if r.premium.decoration then
					expect(Defs.Decoration[r.premium.decoration]).to.be.ok()
				end
			end
		end)

		it("is completable by an active free player in a season", function()
			-- 3 dailies/day + 5 weeklies/week + ~3,000 catches/day
			local days = Config.StormPass.Days
			local dailyXP = 0
			for _, t in Config.Quests.Templates do
				if t.daily then
					dailyXP += (t.reward.passXP or 0)
				end
			end
			local avgDaily = dailyXP / 10 * Config.Quests.DailyCount
			local weeklyXP = 5 * 600
			local total = avgDaily * days + weeklyXP * (days / 7) + 3000 * Config.Economy.PassXPPerCatch * days
			local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
			expect(total >= EconomyMath.passTotalXPForTier(Config.StormPass.Tiers)).to.equal(true)
		end)
	end)

	describe("Schedule", function()
		it("cycles storms on a fixed UTC grid", function()
			local t = 1_800_000_000 - 1_800_000_000 % Config.Weather.CycleSeconds
			local s = Schedule.storm(t)
			expect(s.active).to.be.ok()
			expect(s.endsAt).to.equal(t + Config.Weather.ActiveSeconds)
			local quiet = Schedule.storm(t + Config.Weather.ActiveSeconds + 1)
			expect(quiet.active).to.equal(nil)
			expect(quiet.nextStartsAt).to.equal(t + Config.Weather.CycleSeconds)
			local seen = {}
			for i = 0, #Config.Weather.Order - 1 do
				seen[Schedule.stormForSlot(i)] = true
			end
			for _, id in Config.Weather.Order do
				expect(seen[id]).to.equal(true)
			end
		end)

		it("weeks start on Monday UTC", function()
			-- 2026-09-28 is a Monday
			local monday = 1790553600
			expect(Schedule.weekIndex(monday)).to.equal(Schedule.weekIndex(monday + 6 * 86400 + 86399))
			expect(Schedule.weekIndex(monday - 1)).to.equal(Schedule.weekIndex(monday) - 1)
		end)

		it("rolls Storm Pass seasons automatically", function()
			local start = Config.StormPass.StartUnix
			expect((Schedule.passSeason(start - 1))).to.equal(0)
			expect((Schedule.passSeason(start))).to.equal(1)
			expect((Schedule.passSeason(start + Config.StormPass.Days * 86400))).to.equal(2)
		end)

		it("activates live events only inside their window", function()
			for _, ev in Config.LiveEvents do
				expect(#Schedule.activeEvents(ev.startUnix - 1)).to.equal(0)
				expect(Schedule.activeEvents(ev.startUnix)[1].id).to.equal(ev.id)
				expect(#Schedule.activeEvents(ev.endUnix)).to.equal(0)
			end
		end)
	end)
end
