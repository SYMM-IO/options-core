import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { ZeroAddress } from "ethers"

export function shouldBehaveLikePartyBFacet(): void {
	let context: RunContext, partyA1: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyB1.setBalances(e(100000), e(100000))
		await partyA1.setBalances(e(100000), e(100000))

		const latestBlock = await ethers.provider.getBlock("latest")
		await partyA1.sendOpenIntent(
			openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner()])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 140)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build(),
		)
	})

	describe("lockOpenIntent", async function () {
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

		it("Should failed when intent status not  PENDING", async () => {
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
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 140)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build()

			await partyA1.sendOpenIntent(request)

			await context.controlFacet.setPartyBConfig(partyA1.getSigner(), {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})

			await expect(context.partyBFacet.connect(partyA1.getSigner()).lockOpenIntent(2)).to.revertedWith("LibPartyB: PartyA can't be partyB too")
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

			// TODO ::: check intentLayout states
		})
	})

	describe("unlockOpenIntent", async function () {
		beforeEach(async () => {
			await context.partyBFacet.connect(partyB1.getSigner()).lockOpenIntent(1)
		})

		it("Should failed when Global Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(partyB1.unlockOpenIntent("1")).to.revertedWith("Pausable: Global paused")
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(partyB1.unlockOpenIntent("1")).to.revertedWith("Pausable: PartyB actions paused")
		})

		it("Should failed when msgSender is not PartyB", async () => {
			await expect(context.partyBFacet.connect(context.signers.others[0]).unlockOpenIntent(1)).to.revertedWith("Accessibility: Should be partyB of Intent")
		})

		it("Should failed when intent status not LOCKED", async () => {
			await partyA1.sendCancelOpenIntent(["1"])
			await expect(partyB1.unlockOpenIntent("1")).to.revertedWith("LibPartyB: Invalid state")
		})

		it("Should failed when PartyB is in the liquidation process", async () => {
			//TODO :::
		})

		it("Should change intent status to EXPIRED when deadline reached", async () => {
			// TODO :::
			// const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 150
			// await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			// expect(await context.partyBFacet.connect(partyB1.getSigner()).unlockOpenIntent(1)).to.not.reverted
			// const intent = await context.viewFacet.getOpenIntent(1)
			// expect(intent.status).to.equal(3)
		})

		it("Should change intent status to PENDING", async () => {
			expect(await partyB1.unlockOpenIntent("1")).to.not.reverted

			const intent = await context.viewFacet.getOpenIntent(1)

			expect(intent.status).to.equal(0) //IntentStatus.PENDING
			expect(intent.partyB).to.equal(ZeroAddress)
		})
	})

	describe("fillOpenIntent", async function () {
		beforeEach(async () => {
			await partyB1.lockOpenIntent("1")
		})

		it("Should failed when Global Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.revertedWith("Pausable: Global paused")
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.revertedWith("Pausable: PartyB actions paused")
		})

		it("Should failed when msgSender is not PartyB", async () => {
			await expect(partyB2.fillOpenIntent(1, 100, 7)).to.revertedWith(
				"Accessibility: Should be partyB of Intent",
			)
		})

		it("Should failed when partyA suspended", async () => {
			await context.controlFacet.suspendAddress(partyA1.getSigner(), true)
			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.revertedWith("PartyBFacet: PartyA is suspended")
		})
	})
}
