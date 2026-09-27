--!strict
return function()
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local Config = require(Shared:WaitForChild("Config"))
	local DataTemplate = require(Shared:WaitForChild("DataTemplate"))
	local Migrations = require(Shared:WaitForChild("Migrations"))

	local NOW = 1_800_000_000

	local function v1Save(): any
		return {
			DataVersion = 1,
			Charge = 500,
			Pets = {
				{ uid = "a1", id = "DropletPup", tier = 1, source = "Egg", obtained = 1 },
				{ uid = "b2", id = "PuddleFrog", tier = 2, source = "Egg", obtained = 2 },
			},
			Boosts = { Luck = 120 },
			Upgrades = { JarCapacity = 3 },
		}
	end

	describe("migrate", function()
		it("walks every step up to the current version", function()
			local data, from = Migrations.migrate(v1Save(), Config.DataVersion, NOW)
			expect(from).to.equal(1)
			expect(data.DataVersion).to.equal(Config.DataVersion)
		end)

		it("v2 converts the pet array into a uid map", function()
			local data = Migrations.migrate(v1Save(), 2, NOW)
			expect(data.Pets.a1.id).to.equal("DropletPup")
			expect(data.Pets.b2.tier).to.equal(2)
			expect(data.Pets[1]).to.equal(nil)
		end)

		it("v3 converts boost durations to expiry times", function()
			local data = Migrations.migrate(v1Save(), 3, NOW)
			expect(data.Boosts.Luck).to.equal(NOW + 120)
		end)

		it("is idempotent for current saves", function()
			local fresh: any = DataTemplate.new()
			fresh.Boosts.Luck = NOW + 50
			local data = Migrations.migrate(fresh, Config.DataVersion, NOW)
			expect(data.Boosts.Luck).to.equal(NOW + 50)
		end)

		it("refuses saves from a newer version", function()
			expect(function()
				Migrations.migrate({ DataVersion = Config.DataVersion + 1 }, Config.DataVersion, NOW)
			end).to.throw("newer")
		end)

		it("treats missing DataVersion as v1", function()
			local data, from = Migrations.migrate({ Pets = {} }, Config.DataVersion, NOW)
			expect(from).to.equal(1)
			expect(data.DataVersion).to.equal(Config.DataVersion)
		end)
	end)

	describe("reconcile", function()
		it("fills missing keys without touching existing values", function()
			local data = Migrations.migrate(v1Save(), Config.DataVersion, NOW)
			Migrations.reconcile(data, DataTemplate.new() :: any)
			expect(data.Charge).to.equal(500)
			expect(data.Upgrades.JarCapacity).to.equal(3)
			expect(data.Upgrades.CatchSpeed).to.equal(0)
			expect(data.Stats.Caught).to.equal(0)
			expect(data.Daily.LastClaimDay).to.equal(-1)
			expect(data.UnlockedZones.DrizzleMeadows).to.equal(true)
		end)

		it("does not share tables with the template", function()
			local template = DataTemplate.new() :: any
			local a = Migrations.reconcile({}, template)
			local b = Migrations.reconcile({}, template)
			a.Stats.Caught = 99
			expect(b.Stats.Caught).to.equal(0)
			expect(template.Stats.Caught).to.equal(0)
		end)

		it("does not merge into arrays or maps with dynamic keys", function()
			local data = { Equipped = { "x" }, Pets = { z = { uid = "z" } } }
			Migrations.reconcile(data, DataTemplate.new() :: any)
			expect(#data.Equipped).to.equal(1)
			expect(data.Pets.z.uid).to.equal("z")
		end)
	end)
end
