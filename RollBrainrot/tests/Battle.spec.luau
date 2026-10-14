--!strict
-- Headless combat simulation: real Battle + Abilities + BossAttacks ticking at 10 Hz.
return function()
	local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
	local Battle = require(Server:WaitForChild("Combat"):WaitForChild("Battle"))

	local fakeOwner: any = { UserId = 1, Name = "Tester" }

	local function team(b: any, ids: { string }, level: number)
		for i, id in ids do
			local a = i / #ids * math.pi * 2
			b:addBrainrot(
				fakeOwner,
				tostring(i),
				{ id = id, mut = "Normal", lvl = level, t = 0 },
				Vector3.new(math.cos(a) * 8, 0, math.sin(a) * 8)
			)
		end
	end

	local function run(b: any, seconds: number, onEvent: ((any) -> ())?)
		local start = b.now -- units were created relative to the battle clock
		local t = 0
		while t < seconds do
			t += 0.1
			b:tick(start + t, 0.1)
			if onEvent then
				for _, ev in b.events do
					onEvent(ev)
				end
			end
			table.clear(b.events)
		end
	end

	describe("battle simulation", function()
		it("a starter team clears a wave of Goobers", function()
			local b = Battle.new(1, "Arena", Vector3.zero, 200)
			team(b, { "BananiniBongo", "PizzarinoMozzarino", "Cactoboom" }, 1)
			for i = 1, 10 do
				b:addMonster("Goober", Vector3.new(60 + i * 3, 0, (i - 5) * 4), 1, 1)
			end
			local abilities = 0
			run(b, 90, function(ev)
				if ev.t == "ab" then
					abilities += 1
				end
			end)
			expect(b:aliveCount("enemy")).to.equal(0)
			expect(abilities > 0).to.equal(true)
		end)

		it("bosses telegraph attacks and can be beaten by a strong team", function()
			local b = Battle.new(2, "Arena", Vector3.zero, 300)
			team(
				b,
				{
					"CosmocornoBrainrot",
					"VolcanicoElefanto",
					"SharkaleroJetto",
					"BombardiroGatoro",
					"FroggolinoGelatino",
				},
				10
			)
			local spawned = 0
			b.spawnFn = function(id: string, pos: Vector3)
				spawned += 1
				return b:addMonster(id, pos, 1, 1)
			end
			b:addMonster("ForestTitan", Vector3.new(0, 0, -120), 1, 1)
			local telegraphs, bossDied = 0, false
			b.UnitDied:Connect(function(u: any)
				if u.isBoss then
					bossDied = true
				end
			end)
			run(b, 240, function(ev)
				if ev.t == "tele" then
					telegraphs += 1
				end
			end)
			expect(telegraphs > 0).to.equal(true)
			expect(b:aliveCount("enemy")).to.equal(0)
			local _ = bossDied
		end)

		it("dead Brainrots respawn and units never leave the field", function()
			local b = Battle.new(3, "Arena", Vector3.zero, 80)
			team(b, { "BananiniBongo" }, 1)
			b:addMonster("RockBrute", Vector3.new(30, 0, 0), 5, 1)
			local died, revived = false, false
			run(b, 40, function(ev)
				if ev.t == "die" then
					died = true
				elseif ev.t == "revive" then
					revived = true
				end
			end)
			expect(died).to.equal(true)
			expect(revived).to.equal(true)
			for _, u in b.units do
				expect(Vector3.new(u.pos.X, 0, u.pos.Z).Magnitude <= 80).to.equal(true)
			end
		end)

		it("packs position snapshots under the unreliable size limit", function()
			local b = Battle.new(4, "Arena", Vector3.new(0, 0, -1320), 540)
			for i = 1, 250 do
				b:addMonster("Goober", Vector3.new(i, 0, -1320 + i), 1, 1)
			end
			local packets = b:packSnapshots()
			expect(#packets).to.equal(3)
			for _, p in packets do
				expect(buffer.len(p) <= 900).to.equal(true)
			end
			expect(buffer.readu16(packets[1], 2)).to.equal(100)
		end)
	end)
end
