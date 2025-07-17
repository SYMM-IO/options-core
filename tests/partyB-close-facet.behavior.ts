import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { MarginType, TradeSide, TradeStatus } from "./option-enums"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { ZeroAddress } from "ethers"
import { partyAClose } from "../types/contracts/facets"
import { TradeStructOutput } from "../types/contracts/facets/ViewFacet/IViewFacet"
import exp from "constants"
import { CloseIntentStruct, SymbolStruct, TradeStruct } from "../types/contracts/interfaces/ISymmio"
import { getLatestBlockTime } from "../utils/time"

export function shouldBehaveLikePartyBCloseFacet(): void {
	let context: RunContext, partyA1: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyB1.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateralNL, e(100000), e(100000))

		const request = openIntentRequestBuilder()
			.partyBsWhiteList([partyB1.getSigner])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateralNL)
			.symbolId(1)
			.deadline((await getLatestBlockTime()) + 140)
			.expirationTimestamp((await getLatestBlockTime()) + 150)
			.exerciseFee({ cap: e(1), rate: "0" })
			.quantity(e(100))
			.price(7)
			.tradeSide(TradeSide.BUY)
			.marginType(MarginType.ISOLATED)
			.build()

		const requestCross = openIntentRequestBuilder()
			.partyBsWhiteList([partyB1.getSigner])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateralNL)
			.symbolId(1)
			.deadline((await getLatestBlockTime()) + 140)
			.expirationTimestamp((await getLatestBlockTime()) + 150)
			.exerciseFee({ cap: e(1), rate: "0" })
			.quantity(e(100))
			.price(7)
			.tradeSide(TradeSide.SELL)
			.marginType(MarginType.CROSS)
			.build()

		await partyA1.sendOpenIntent(request)
		await partyA1.sendOpenIntent(requestCross)
		await partyB1.lockOpenIntent(1)
		await partyB1.lockOpenIntent(2)
		await partyB1.fillOpenIntent(1, e(100), 7)
		await partyB1.fillOpenIntent(2, e(100), 7)
		await partyA1.sendCloseIntent(1, e(100), 7, (await getLatestBlockTime()) + 120)
		await partyA1.sendCloseIntent(2, e(100), 7, (await getLatestBlockTime()) + 120)
	})

	describe("fillCloseIntent", async function () {
		it("Should be failed when Globally Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(partyB1.fillCloseIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBOpenFacet, "GlobalPaused")
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(partyB1.fillCloseIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBOpenFacet, "PartyBActionsPaused")
		})

		it("Should failed when amount to fill not in range", async () => {
			const closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(1)
			console.log("Close Intent Quantity: ", closeIntent.quantity)
			console.log("Close Intent Filled Amount: ", closeIntent.filledAmount)

			await expect(partyB1.fillCloseIntent(1, e(101), 7)).to.revertedWithCustomError(context.partyBCloseFacet, "InvalidFillAmount")
			await expect(partyB1.fillCloseIntent(1, e(100), 7)).not.to.reverted
		})

		it("Should set the Trade as Closed when close Quantity match trade quantity", async () => {
			await expect(partyB1.fillCloseIntent(1, e(100), 7)).not.to.reverted
			let trade = await context.viewFacet.getTrade(1)

			console.log("Trade Status: ", trade.status == BigInt(TradeStatus.CLOSED) ? "Closed" : trade.status)
			expect(trade.status).to.be.equal(TradeStatus.CLOSED)
		})

		it("Should fail when Trade status not OPEN", async () => {
			let timeToTime = (await getLatestBlockTime()) + 120
			await expect(partyB1.fillCloseIntent(1, e(100), 7)).not.to.reverted
			await expect(partyA1.sendCloseIntent(1, e(1), 7, timeToTime)).to.be.revertedWithCustomError(context.partyACloseFacet, "InvalidState")
		})

		it("Should failed when Close Intent is expired", async () => {
			const newBlock = (await getLatestBlockTime()) + 150
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")
			//Close Intent Expired

			await expect(partyB1.fillCloseIntent(1, 1, 7)).to.revertedWithCustomError(context.partyBCloseFacet, "IntentExpired")
		})

		it("Should failed when Trade is expired", async () => {
			const newBlockTime = (await getLatestBlockTime()) + 150

			await partyA1.sendOpenIntent(
				openIntentRequestBuilder()
					.partyBsWhiteList([partyB1.getSigner])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateral)
					.symbolId(1)
					.deadline(newBlockTime)
					.expirationTimestamp(newBlockTime)
					.exerciseFee({ cap: e(1), rate: "0" })
					.quantity(e(100))
					.price(7)
					.build(),
			)

			await partyB1.lockOpenIntent(3)
			await partyB1.fillOpenIntent(3, 100, 7)
			await partyA1.sendCloseIntent(3, 100, 7, newBlockTime + 180) // longer deadline than option expire

			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTime])
			await network.provider.send("evm_mine")
			await expect(partyB1.fillCloseIntent(3, 1, 7)).to.revertedWithCustomError(context.partyBCloseFacet, "TradeExpired")
		})

		it("Should failed when Fill Close Intent price not in range For BUY Trades", async () => {
			await expect(partyB1.fillCloseIntent(1, e(96), 5)).to.revertedWithCustomError(context.partyBCloseFacet, "InvalidClosePrice")
			await expect(partyB1.fillCloseIntent(1, 96, 10)).not.to.revertedWithCustomError(context.partyBCloseFacet, "InvalidClosePrice")
		})

		it("Should failed when Fill Close Intent price not in range For SELL Trades", async () => {
			await expect(partyB1.fillCloseIntent(2, 96, 10)).to.revertedWithCustomError(context.partyBCloseFacet, "InvalidClosePrice")
			await expect(partyB1.fillCloseIntent(2, 96, 5)).not.to.revertedWithCustomError(context.partyBCloseFacet, "InvalidClosePrice")
		})

		it("Should change balances for parties as expected in Isolated mode(Buy Trade)", async () => {
			const closeIntentID = 1
			const closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(closeIntentID)
			closeIntent.quantity

			const quantity = BigInt(closeIntent.quantity) 
			const price = 8
			await expect(partyB1.fillCloseIntent(closeIntentID, quantity, price)).to.not.be.reverted	
		})

		it("Should change balances for parties as expected in Isolated mode", async () => {
			//take balance snapshot

			const closeIntentID = 1
			const closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(closeIntentID)
			closeIntent.quantity
			
			const partyBBalanceBefore = await context.viewFacet.getIsolatedBalance(partyB1.getSigner, context.collateral)
			const partyABalanceBefore = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral)
			
			const halfQuantity = BigInt(closeIntent.quantity) / 2n
			const price = 8 // party B says I can buy higher
			await expect(partyB1.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted

			// more than 2 intervals pass for schedules
			let newBlockTime = (await getLatestBlockTime()) + 36
			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTime])
			await network.provider.send("evm_mine")

			await expect(partyB1.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted

			const trade: TradeStruct = await context.viewFacet.getTrade(closeIntent.tradeId)
			const symbol: SymbolStruct = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			const partyBBalanceAfter = await context.viewFacet.getIsolatedBalance(trade.partyB, symbol.collateral)
			const premium = await context.viewFacet.getTradePremium(closeIntent.tradeId)
			let partyABalanceAfter = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral)
			let scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA1.getSigner, context.collateral, partyB1.getSigner)
			const pnl = (BigInt(price) * BigInt(2n * halfQuantity)) / BigInt(1000000000000000000)
			const finalPremium = (premium * 2n * halfQuantity) / BigInt(trade.tradeAgreements.quantity)

			console.log("PartyB balance before fill to close intent:", partyBBalanceBefore)
			console.log("PartyA balance before fill to close intent:", partyABalanceBefore)
			console.log("PartyB balance after fill to close intent:", partyBBalanceAfter)
			console.log("PartyA balance after fill to close intent:", partyABalanceAfter)
			console.log("PartyA balance Scheduled:", scheduleEntry.scheduled)
			console.log("PartyA balance Transitioning:", scheduleEntry.transitioning)
			console.log("PartyA balance Last Timestamp:", scheduleEntry.lastTransitionTimestamp)
			console.log("PartyA balance Release Interval:", scheduleEntry.releaseInterval)
			console.log("Trade agreement Quantity:", trade.tradeAgreements.quantity)
			console.log("Fill Close Intent Quantity:", halfQuantity)
			console.log("Fill Close Intent Price:", price)
			console.log("Premium Calculation:", finalPremium)
			console.log("PNL Calculation:", pnl)

			// base on close quantity that is 100(two 50) and the price 8, we expect the balances to be(2pnl as we have 2*50 quantity)
			expect(partyBBalanceAfter - partyBBalanceBefore).to.be.equal(finalPremium - pnl)

			//for party A we expect to have half of its output as the balance is scheduled and updated using sync function
			expect(partyABalanceAfter - partyABalanceBefore).to.be.equal(pnl / 2n)

			newBlockTime = (await getLatestBlockTime()) + 12
			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTime])
			await network.provider.send("evm_mine")

			expect(scheduleEntry.scheduled).to.be.equal(pnl / 2n)

			await context.accountFacet.syncBalances(context.collateral, partyA1.getSigner, [partyB1.getSigner])
			scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA1.getSigner, context.collateral, partyB1.getSigner)

			expect(scheduleEntry.transitioning).to.be.equal(pnl / 2n)

			newBlockTime = (await getLatestBlockTime()) + 12
			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTime])
			await network.provider.send("evm_mine")

			await context.accountFacet.syncBalances(context.collateral, partyA1.getSigner, [partyB1.getSigner])
			partyABalanceAfter = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral)
			scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA1.getSigner, context.collateral, partyB1.getSigner)

			console.log("PartyA balance after window sync:", partyABalanceAfter)
			console.log("PartyA balance Scheduled:", scheduleEntry.scheduled)
			console.log("PartyA balance Transitioning:", scheduleEntry.transitioning)
			console.log("PartyA balance Last Timestamp:", scheduleEntry.lastTransitionTimestamp)
			console.log("PartyA balance Release Interval:", scheduleEntry.releaseInterval)

			expect(partyABalanceAfter - partyABalanceBefore).to.be.equal(pnl)
		})

		it("Should change balances for parties as expected in Cross mode", async () => {})
	})
}
