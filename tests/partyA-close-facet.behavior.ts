import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { ZeroAddress } from "ethers"

export function shouldBehaveLikePartyACloseFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyB1 = new PartyB(context, context.signers.partyB1)
		await partyA1.setBalances("500")

		await context.controlFacet.setPartyBConfig(partyB1.getSigner(), {
			isActive: true,
			lossCoverage: 0,
			oracleId: 0,
			symbolType: 0
		})

		await context.controlFacet.setAffiliateStatus(context.signers.others[0], true)
     	partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)


		await partyB1.setBalances(e(100000), e(100000))
		await partyA1.setBalances(e(100000), e(100000))
	})

	describe("cancelOpenIntent", async function () {
		beforeEach(async () => {
			const latestBlock = await ethers.provider.getBlock("latest")

			await partyA1.sendOpenIntent(
				openIntentRequestBuilder()
					.partyBsWhiteList([partyB1.getSigner()])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateral)
					.symbolId(1)
					.deadline((latestBlock?.timestamp ?? 0) + 120)
					.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
					.exerciseFee({ cap: e(1), rate: "0" })
					.quantity(e(100))
					.price(7)
					.build(),
			)
		})

		it("Should fail when partyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await expect(partyA1.sendCancelOpenIntent(["1"])).to.be.revertedWith("Pausable: PartyA actions paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(partyA1.sendCancelOpenIntent(["1"])).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when intent status not be pending or locked", async function () {
			// TODO :::
		})

		it("Should fail when msgSender not be PartyA", async function () {
			await expect(partyA2.sendCancelOpenIntent(["1"])).to.be.revertedWith("PartyAFacet: Invalid sender")
		})

		it("Should fail when instance mode is active", async function () {
			await partyA1.activateInstantActionMode()
			await expect(partyA1.sendCancelOpenIntent(["1"])).to.be.revertedWith("Accessibility: Instant action mode is activated")
		})

		// it("Should set status to EXPIRED when deadline reached", async function () {
		// 	const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 150
		// 	await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
		// 	expect(await user.sendCancelOpenIntent(['1'])).to.be.not.reverted

		// 	const intent = await context.viewFacet.getOpenIntent(1)

		// 	expect(intent.status).to.be.equal(2)
		// })
	})
}
