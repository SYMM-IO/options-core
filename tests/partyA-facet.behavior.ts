import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { User } from "./models/user.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers } from "hardhat"
import { e } from "../utils/e"

export function shouldBehaveLikePartyAFacet(): void {
	let context: RunContext, user: User, partyB: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		user = new User(context, context.signers.user)
		partyB = new PartyB(context, context.signers.user2)
		await user.setBalances("500")

		await context.controlFacet.setPartyBConfig(partyB.getSigner(), {
			isActive: true,
			lossCoverage: 0,
			oracleId: 0,
		})

		await context.controlFacet.setAffiliateStatus(context.signers.others[0], true)

	})

	describe("sendOpenIntent", async function () {
		beforeEach(async () => {
			await context.controlFacet.addOracle("test orancel", context.signers.others[0])
			await context.controlFacet.addSymbol("BTC", 0, 1, context.collateral, true, 0)
		})
		it("Should fail when partyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			const request = openIntentRequestBuilder().partyBsWhiteList([partyB.getSigner()]).affiliate(partyB.getSigner()).build()
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("Pausable: PartyA actions paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			const request = openIntentRequestBuilder().partyBsWhiteList([partyB.getSigner()]).affiliate(partyB.getSigner()).build()
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when symbolId be wrong", async function () {
			const request = openIntentRequestBuilder().partyBsWhiteList([partyB.getSigner()]).affiliate(partyB.getSigner()).symbolId(2).build()
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Symbol is not valid")
		})

		it("Should fail when deadline be low", async function () {
			const request = openIntentRequestBuilder().partyBsWhiteList([partyB.getSigner()]).affiliate(partyB.getSigner()).symbolId(1).build()
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Low deadline")
		})

		it("Should fail when expiration timestamp be low", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.build()
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Low expiration timestamp")
		})

		it("Should fail when cap for exercise fee be high", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(2), rate: "0" })
				.build()
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: High cap for exercise fee")
		})

		it("Should fail when instance mode is active", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await context.controlFacet.setInstantActionsMode(user.getSigner(), true)
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Instant action mode is activated")
		})

		it("Should fail when affiliate be zero address or invalid", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })

			await expect(user.sendOpenIntent(request.build())).to.be.revertedWith("PartyAFacet: Invalid affiliate")

			request.affiliate(context.signers.others[1])
			await expect(user.sendOpenIntent(request.build())).to.be.revertedWith("PartyAFacet: Invalid affiliate")

			await context.controlFacet.setAffiliateStatus(context.signers.others[1], true)
			await expect(user.sendOpenIntent(request.build())).to.be.not.revertedWith("PartyAFacet: Invalid affiliate")
		})

		it("Should fail when partyA bound to a partyB that is not in whitelisted partyB", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([context.signers.partyB2])
				.affiliate(partyB.getSigner())
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.affiliate(context.signers.others[0])
				.build()

			await context.accountFacet.connect(user.getSigner()).bindToPartyB(partyB.getSigner())
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: User is bound to another PartyB")
		})

		it("Should fail when sender in whitelisted partyB", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([user.getSigner()])
				.affiliate(partyB.getSigner())
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.affiliate(context.signers.others[0])
				.build()

			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Sender isn't allowed in partyBWhiteList")
		})

		it("TODO", async function () {
			// TODO ::: check balances
		})
	})
}
