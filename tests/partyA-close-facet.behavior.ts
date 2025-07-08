import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { getLatestBlockTime } from "../utils/time"

export function shouldBehaveLikePartyACloseFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		await context.controlFacet.setAffiliateStatus(context.signers.others[0], true)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyB1.setBalances(context.collateral, e(100000), e(100000))
		await partyB2.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateral, e(100000), e(100000))
		await partyA2.setBalances(context.collateral, e(100000), e(100000))
	})

	describe("sendCloseIntent", async function () {
		beforeEach(async () => {
			const latestBlock = await getLatestBlockTime()

			let request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build()

			await partyA1.sendOpenIntent(request)

			await partyA2.sendOpenIntent(
				openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.getSigner])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateral)
					.symbolId(1)
					.deadline(latestBlock + 120)
					.expirationTimestamp(latestBlock + 120)
					.exerciseFee({ cap: e(1), rate: "0" })
					.quantity(e(100))
					.price(7)
					.build(),
			)

			await partyB1.lockOpenIntent(1)
			await partyB1.fillOpenIntent(1, e(100), 7)
			await partyB2.lockOpenIntent(2)
			await partyB2.fillOpenIntent(2, e(100), 7)
			partyA1.sendOpenIntent(request)
		})

		it("Should fail when partyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			const latestBlock = await getLatestBlockTime()
			await expect(partyA2.sendCloseIntent(1, 7, 100, latestBlock + 140)).to.be.revertedWithCustomError(
				context.partyACloseFacet,
				"PartyAActionsPaused",
			)
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			const latestBlock = await getLatestBlockTime()
			await expect(partyA2.sendCloseIntent(1, 7, 100, latestBlock + 140)).to.be.revertedWithCustomError(context.partyACloseFacet, "GlobalPaused")
		})

		it("Should fail when msgSender not be PartyA", async function () {
			const latestBlock = await getLatestBlockTime()
			// await expect(partyA1.sendCloseIntent(2, 7, 100, (latestBlock) + 140)).to.be.revertedWithCustomError(
			// 	context.partyACloseFacet,
			// 	"UnauthorizedSender",
			// )
			//TODO ::: how to implement the test?
		})

		it("Should fail when instant action mode is active", async function () {
			await partyA1.bindToCounterParty(partyB1.getSigner)
			await partyA1.activateInstantActionMode()
			const latestBlock = await getLatestBlockTime()
			await expect(partyA1.sendCloseIntent(1, 7, 100, latestBlock + 140)).to.be.revertedWithCustomError(context.partyACloseFacet, "InstantModeActive")
		})

		it("Should fail when msgSender not be PartyA", async function () {
			const latestBlock = await getLatestBlockTime()
			await expect(partyA2.sendCloseIntent(1, 7, 100, latestBlock + 140)).to.be.revertedWithCustomError(
				context.partyACloseFacet,
				"UnauthorizedSender",
			)
		})

		it("Should fail when Trade in Invalid state", async function () {
			const latestBlock = await getLatestBlockTime()
			// await expect(partyA1.sendCloseIntent(3, 7, 100, latestBlock)).to.be.revertedWithCustomError(
			// 	context.partyACloseFacet,
			// 	"InvalidState",
			// )
			//TODO ::: how to implement the test?
		})

		it("Should fail when deadline low", async function () {
			const latestBlock = await getLatestBlockTime()
			await expect(partyA1.sendCloseIntent(1, 7, 100, latestBlock)).to.be.revertedWithCustomError(context.partyACloseFacet, "LowDeadline")
		})

		it("Should fail when invalid quantity", async function () {
			const latestBlock = await getLatestBlockTime()
			await partyA1.sendCloseIntent(1, 7, e(5), latestBlock + 140)
			await expect(partyA1.sendCloseIntent(1, 7, e(96), latestBlock + 140)).to.be.revertedWithCustomError(context.partyACloseFacet, "InvalidQuantity")
		})

		it("Should fail when invalid quantity", async function () {
			const latestBlock = await getLatestBlockTime()
			await partyA1.sendCloseIntent(1, 7, 5, latestBlock + 140)
			await expect(partyA1.sendCloseIntent(1, 7, 5, latestBlock + 140)).to.be.revertedWithCustomError(context.partyACloseFacet, "TooManyCloseOrders")
		})
	})
}
