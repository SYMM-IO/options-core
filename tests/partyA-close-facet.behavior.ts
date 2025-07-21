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
import { CloseIntentStruct, TradeStruct } from "../types/contracts/interfaces/ISymmio"
import { CloseIntentStatus } from "./option-enums"

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
			const latestBlockTime = await getLatestBlockTime()

			let request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlockTime + 120)
				.expirationTimestamp(latestBlockTime + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build()

			let request2 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlockTime + 120)
				.expirationTimestamp(latestBlockTime + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build()

			await partyA1.sendOpenIntent(request1)
			await partyA1.sendOpenIntent(request2)
			await partyA2.sendOpenIntent(request2)
			await partyB1.lockOpenIntent(1)
			await partyB1.fillOpenIntent(1, e(100), 7)
			await partyB2.lockOpenIntent(2)
			await partyB2.fillOpenIntent(2, e(100), 7)
		})

		it("Should fail when partyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			const latestBlockTime = await getLatestBlockTime()
			await expect(partyA2.sendCloseIntent(1, 100, 7, latestBlockTime + 140)).to.be.revertedWithCustomError(
				context.partyACloseFacet,
				"PartyAActionsPaused",
			)
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			const latestBlockTime = await getLatestBlockTime()
			await expect(partyA2.sendCloseIntent(1, 100, 7, latestBlockTime + 140)).to.be.revertedWithCustomError(context.partyACloseFacet, "GlobalPaused")
		})

		it("Should fail when msgSender not be PartyA", async function () {
			const latestBlockTime = await getLatestBlockTime()
			await expect(partyA1.sendCloseIntent(3, 100, 7, latestBlockTime + 140)).to.be.revertedWithCustomError(
				context.partyACloseFacet,
				"UnauthorizedSender",
			)
		})

		it("Should fail when instant action mode is active", async function () {
			await partyA1.bindToCounterParty(partyB1.getSigner)
			await partyA1.activateInstantActionMode()
			const latestBlockTime = await getLatestBlockTime()
			await expect(partyA1.sendCloseIntent(1, 100, 7, latestBlockTime + 140)).to.be.revertedWithCustomError(
				context.partyACloseFacet,
				"InstantModeActive",
			)
		})

		it("Should fail when msgSender not be PartyA", async function () {
			const latestBlockTime = await getLatestBlockTime()
			await expect(partyA2.sendCloseIntent(1, 100, 7, latestBlockTime + 140)).to.be.revertedWithCustomError(
				context.partyACloseFacet,
				"UnauthorizedSender",
			)
		})

		it("Should fail when Trade in Invalid state", async function () {
			const latestBlockTime = (await getLatestBlockTime()) + 100

			await partyA1.sendCloseIntent(1, e(100), 7, latestBlockTime)
			await partyB1.fillCloseIntent(1, e(100), 7)

			await expect(partyA1.sendCloseIntent(1, 1, 7, latestBlockTime)).to.be.revertedWithCustomError(context.partyACloseFacet, "InvalidState")
		})

		it("Should fail when deadline low", async function () {
			const latestBlockTime = await getLatestBlockTime()
			await expect(partyA1.sendCloseIntent(1, 100, 7, latestBlockTime)).to.be.revertedWithCustomError(context.partyACloseFacet, "LowDeadline")
		})

		it("Should fail when invalid quantity when quantity more than Trade Quantity", async function () {
			const latestBlockTime = await getLatestBlockTime()
			await partyA1.sendCloseIntent(1, e(5), 7, latestBlockTime + 140)
			await expect(partyA1.sendCloseIntent(1, e(96), 7, latestBlockTime + 140)).to.be.revertedWithCustomError(
				context.partyACloseFacet,
				"InvalidQuantity",
			)
		})

		it("Should fail when we have pending close Intent", async function () {
			const latestBlockTime = await getLatestBlockTime()
			await partyA1.sendCloseIntent(1, e(10), 7, latestBlockTime + 140)

			await network.provider.send("evm_setNextBlockTimestamp", [latestBlockTime + 160])
			await network.provider.send("evm_mine")

			await expect(partyA1.sendCloseIntent(1, e(100), 7, latestBlockTime + 200)).to.be.revertedWithCustomError(
				context.partyACloseFacet,
				"InvalidQuantity",
			)

			await partyA1.sendCancelCloseIntent(["1"])
			await expect(partyA1.sendCloseIntent(1, e(100), 7, latestBlockTime + 200)).not.to.be.reverted
		})

		it("Should fail when invalid Close Intent Count", async function () {
			await context.controlFacet.setMaxCloseOrdersLength(1)

			const latestBlockTime = await getLatestBlockTime()
			await partyA1.sendCloseIntent(1, 5, 7, latestBlockTime + 140)
			await expect(partyA1.sendCloseIntent(1, 7, 5, latestBlockTime + 140)).to.be.revertedWithCustomError(
				context.partyACloseFacet,
				"TooManyCloseOrders",
			)
		})

		it("Should Pass when sending Close Intent", async function () {
			const deadline = (await getLatestBlockTime()) + 140
			await partyA1.sendCloseIntent(1, e(10), 7, deadline)
			await expect(partyA1.sendCloseIntent(1, e(12), 5, deadline)).not.to.be.reverted

			let closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(2)
			let trade: TradeStruct = await context.viewFacet.getTrade(1)
			expect(closeIntent.tradeId).to.be.equal(1)
			expect(closeIntent.quantity).to.be.equal(e(12))
			expect(closeIntent.price).to.be.equal(5)
			expect(closeIntent.filledAmount).to.be.equal(0)
			expect(closeIntent.status).to.be.equal(CloseIntentStatus.PENDING)
			expect(closeIntent.createTimestamp).to.be.equal(await getLatestBlockTime())
			expect(closeIntent.deadline).to.be.equal(deadline)
			expect(closeIntent.feeStructure).to.be.deep.equal(trade.feeStructure)
		})
	})
}
