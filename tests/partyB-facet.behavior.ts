import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { User } from "./models/user.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"

export function shouldBehaveLikePartyBFacet(): void {
	let context: RunContext, user: User, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		user = new User(context, context.signers.user)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)
		await user.setBalances("500")

		await context.controlFacet.setPartyBConfig(partyB1.getSigner(), {
			isActive: true,
			lossCoverage: 0,
			oracleId: 1,
		})

		await context.controlFacet.setPartyBConfig(partyB2.getSigner(), {
			isActive: true,
			lossCoverage: 0,
			oracleId: 1,
		})

		await context.controlFacet.setAffiliateStatus(context.signers.others[0], true)

		await context.controlFacet.addOracle("test orancel", context.oracle)
		await context.controlFacet.setPriceOracleAddress(context.oracle)
		await context.controlFacet.addSymbol("BTC", 0, 1, context.collateral, true, 0)
		await context.controlFacet.setMaxConnectedPartyBs(1)
		await partyB1.setBalances(e(100000))
		await user.setBalances(e(100000))

		await context.accountFacet.connect(partyB1.getSigner()).deposit(context.collateral, e(100000))
		await context.accountFacet.connect(user.getSigner()).deposit(context.collateral, e(100000))

		const latestBlock = await ethers.provider.getBlock("latest")
		const request = openIntentRequestBuilder()
			.partyBsWhiteList([partyB1.getSigner()])
			.affiliate(partyB1.getSigner())
			.feeToken(context.collateral)
			.symbolId(1)
			.deadline((latestBlock?.timestamp ?? 0) + 140)
			.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
			.exerciseFee({ cap: e(1), rate: "0" })
			.affiliate(context.signers.others[0])
			.quantity(e(100))
			.price(7)
			.build()

		await user.sendOpenIntent(request)
	})

	describe("lockOpenIntent", async function () {
		beforeEach(async () => {})

		it("Should failed when Global Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(context.partyBFacet.lockOpenIntent(1)).to.revertedWith("Pausable: Global paused")
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(context.partyBFacet.lockOpenIntent(1)).to.revertedWith("Pausable: PartyB actions paused")
		})

		it("Should failed when msgSender is not PartyB", async () => {
			await expect(context.partyBFacet.lockOpenIntent(1)).to.revertedWith("Accessibility: Should be partyB")
		})

		it("Should failed when intent status not be PENDING", async () => {
			//TODO :::
		})

		it("Should failed when intent deadline reached", async () => {
			const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 150
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])

			await expect(context.partyBFacet.connect(partyB1.getSigner()).lockOpenIntent(1)).to.revertedWith("LibPartyB: Intent is expired")
		})

		it("Should failed when symbol is not valid", async () => {
			//TODO :::
		})

		it("Should failed when intent expiration has been passed", async () => {
			const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 130
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])

			await expect(context.partyBFacet.connect(partyB1.getSigner()).lockOpenIntent(1)).to.revertedWith(
				"LibPartyB: Requested expiration has been passed",
			)
		})

		it("Should failed when intent id not exist", async () => {
			await expect(context.partyBFacet.connect(partyB1.getSigner()).lockOpenIntent(2)).to.revertedWith("LibPartyB: Invalid intentId")
		})

		it("Should failed when partyB oracle id not equal with symbol oracle id", async () => {
			await context.controlFacet.setPartyBConfig(partyB1.getSigner(), {
				isActive: true,
				lossCoverage: 0,
				oracleId: 0,
			})

			await expect(context.partyBFacet.connect(partyB1.getSigner()).lockOpenIntent(1)).to.revertedWith("LibPartyB: Oracle not matched")
		})

		it("Should failed when partyB be equal to PartyA", async () => {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([])
				.affiliate(partyB1.getSigner())
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 140)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.affiliate(context.signers.others[0])
				.quantity(e(100))
				.price(7)
				.build()

			await user.sendOpenIntent(request)

			await context.controlFacet.setPartyBConfig(user.getSigner(), {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})

			await expect(context.partyBFacet.connect(user.getSigner()).lockOpenIntent(2)).to.revertedWith("LibPartyB: PartyA can't be partyB too")
		})

		it("Should failed when partyB not whitelisted", async () => {
			await expect(context.partyBFacet.connect(partyB2.getSigner()).lockOpenIntent(1)).to.revertedWith("LibPartyB: Sender isn't whitelisted")
		})

		it("Should failed when PartyB is in the liquidation process", async () => {
			//TODO :::
		})

		it("Should lock open intent successfully", async () => {
			await expect(context.partyBFacet.connect(partyB1.getSigner()).lockOpenIntent(1)).to.not.reverted
			
			const intent = await context.viewFacet.getOpenIntent(1)

			expect(intent.status).to.equal(1) // IntentStatus.LOCKED
			expect(intent.partyB).to.equal(partyB1.getSigner())

			// check intentLayout states
		})
	})
}
