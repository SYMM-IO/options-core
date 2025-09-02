import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { CloseIntentStatus, MarginType, TradeSide, TradeStatus } from "./option-enums"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { CloseIntentStruct, SymbolStruct, TradeStruct } from "../types/contracts/interfaces/ISymmio"
import { getLatestBlockTime } from "../utils/time"
import { parseEther, parseUnits } from "ethers"
import { closeIntentBuilder } from "./models/builders/close-intent.builder"
import { extendConfig, extendProvider } from "hardhat/config"
import { int } from "hardhat/internal/core/params/argumentTypes"
import { CloseIntentOpsMock__factory } from "../types"

export function shouldBehaveLikePartyBCloseFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyA3: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA1)
		partyA3 = new PartyA(context, context.signers.others[0])
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyB1.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateralNL, e(100000), e(100000))
		await partyA2.setBalances(context.collateral, e(100000), e(100000))
		await partyA2.setBalances(context.collateralNL, e(100000), e(100000))
		await partyA3.setBalances(context.collateral, e(100000), e(100000))
		await partyA3.setBalances(context.collateralNL, e(100000), e(100000))

		const request = openIntentRequestBuilder()
			.partyBsWhiteList([partyB1.getSigner])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateralNL)
			.symbolId(1)
			.deadline((await getLatestBlockTime()) + 140)
			.expirationTimestamp((await getLatestBlockTime()) + 150)
			.exerciseFee({ cap: e(1), rate: "0" })
			.quantity(e(100))
			.price(7000)
			.tradeSide(TradeSide.BUY)
			.marginType(MarginType.ISOLATED)
			.build()

		const requestCrossBuy = openIntentRequestBuilder()
			.partyBsWhiteList([partyB1.getSigner])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateralNL)
			.symbolId(1)
			.deadline((await getLatestBlockTime()) + 140)
			.expirationTimestamp((await getLatestBlockTime()) + 150)
			.exerciseFee({ cap: e(1), rate: "0" })
			.quantity(e(100))
			.price(7000)
			.tradeSide(TradeSide.BUY)
			.marginType(MarginType.CROSS)
			.build()

		const requestCrossSell = openIntentRequestBuilder()
			.partyBsWhiteList([partyB2.getSigner])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateralNL)
			.symbolId(1)
			.deadline((await getLatestBlockTime()) + 140)
			.expirationTimestamp((await getLatestBlockTime()) + 150)
			.exerciseFee({ cap: e(0.5), rate: "0" })
			.quantity(e(100))
			.price(7000)
			.tradeSide(TradeSide.SELL)
			.marginType(MarginType.CROSS)
			.build()

		await partyA1.sendOpenIntent(request)
		await partyA1.sendOpenIntent(requestCrossBuy)
		await partyA2.sendOpenIntent(requestCrossSell)

		const openIntent1 = await context.viewFacet.getOpenIntent(1)
		const openIntent2 = await context.viewFacet.getOpenIntent(2)
		const openIntent3 = await context.viewFacet.getOpenIntent(3)

		await partyB1.lockOpenIntent(openIntent1.id)
		await partyB1.lockOpenIntent(openIntent2.id)
		await partyB2.lockOpenIntent(openIntent3.id)

		await partyB1.fillOpenIntent(openIntent1.id, e(100), request.price)
		await partyB1.fillOpenIntent(openIntent2.id, e(100), requestCrossBuy.price)
		await partyB2.fillOpenIntent(openIntent3.id, e(100), requestCrossSell.price)

		const trade1 = await context.viewFacet.getTrade(1)
		const trade2 = await context.viewFacet.getTrade(2)
		const trade3 = await context.viewFacet.getTrade(3)

		const quantity1 = trade1.tradeAgreements.quantity / 10n
		const quantity2 = trade2.tradeAgreements.quantity / 5n
		const quantity3 = trade3.tradeAgreements.quantity / 2n

		const price1 = trade1.openedPrice + 100n
		const price2 = trade2.openedPrice - 100n
		const priceSell3 = trade3.openedPrice + 100n
		const priceSell4 = trade3.openedPrice - 100n

		await partyA1.sendCloseIntent(openIntent1.id, quantity1, price1, (await getLatestBlockTime()) + 120)
		await partyA1.sendCloseIntent(openIntent2.id, quantity2, price2, (await getLatestBlockTime()) + 120)
		await partyA2.sendCloseIntent(openIntent3.id, quantity3, priceSell3, (await getLatestBlockTime()) + 120)
		await partyA2.sendCloseIntent(openIntent3.id, quantity3, priceSell4, (await getLatestBlockTime()) + 120)
	})

	describe("Accept Cancel Open Intent", async function () {
		beforeEach(async () => {
			await expect(partyA1.sendCancelCloseIntent(["1"])).not.to.reverted
		})

		it("Should be failed when Globally Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(partyB1.acceptCancelCloseIntent(1)).to.be.revertedWithCustomError(context.partyBCloseFacet, "GlobalPaused")
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(partyB1.acceptCancelCloseIntent(1)).to.be.revertedWithCustomError(context.partyBCloseFacet, "PartyBActionsPaused")
		})

		it("Should fail when Close Intent status as expected", async () => {
			await expect(partyB1.acceptCancelCloseIntent(2)).to.be.revertedWithCustomError(context.partyACloseFacet, "InvalidState")
		})

		it("Should failed when not Authorized Owner", async () => {
			const closeIntent = await context.viewFacet.getCloseIntent(1)

			expect(closeIntent.status).to.be.equal(CloseIntentStatus.CANCEL_PENDING)
			await expect(partyB2.acceptCancelCloseIntent(1)).to.be.revertedWithCustomError(context.partyBCloseFacet, "UnauthorizedSender")
		})

		it("Should Update State to 'CANCELED' on ACCEPT Cancel Close Intent", async function () {
			await expect(partyB1.acceptCancelCloseIntent(1)).not.to.be.reverted

			const closeIntent = await context.viewFacet.getCloseIntent(1)
			expect(closeIntent.status).to.be.equal(CloseIntentStatus.CANCELED)
			expect(partyB1.fillCloseIntent(1, closeIntent.quantity, closeIntent.price)).to.revertedWithCustomError(context.partyACloseFacet, "InvalidState")
		})

		it("Should Update Timestamp on Cancel Close Intent", async function () {
			await expect(partyB1.acceptCancelCloseIntent(1)).not.to.be.reverted

			const closeIntent = await context.viewFacet.getCloseIntent(1)
			expect(closeIntent.statusModifyTimestamp).to.be.equal(await getLatestBlockTime())
		})

		it("Should Update Trade Close Pending Amount on Expire", async function () {
			const tradeBefore = await context.viewFacet.getTrade(1)

			await expect(partyB1.acceptCancelCloseIntent(1)).not.to.be.reverted

			const closeIntent = await context.viewFacet.getCloseIntent(1)
			const tradeAfter = await context.viewFacet.getTrade(1)

			console.log("Close Intent Amount:", closeIntent.quantity)
			console.log("Trade Quantity:", tradeAfter.tradeAgreements.quantity)
			console.log("Trade Close Pending Before:", tradeBefore.closePendingAmount)
			console.log("Trade Close Pending After:", tradeAfter.closePendingAmount)

			expect(tradeBefore.closePendingAmount - tradeAfter.closePendingAmount).to.be.equal(closeIntent.quantity)
		})
	})
	describe("fillCloseIntent", async function () {
		it("Should be failed when Globally Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(partyB1.fillCloseIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBCloseFacet, "GlobalPaused")
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(partyB1.fillCloseIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBCloseFacet, "PartyBActionsPaused")
		})

		it("Should failed when not Authorized Owner", async () => {
			await expect(partyB2.fillCloseIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBCloseFacet, "UnauthorizedSender")
		})

		it("Should failed when amount to fill not in range", async () => {
			const closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(1)
			console.log("Close Intent Quantity: ", closeIntent.quantity)
			console.log("Close Intent Filled Amount: ", closeIntent.filledAmount)

			const quantity = closeIntent.quantity
			const price = closeIntent.price

			await expect(partyB1.fillCloseIntent(closeIntent.id, BigInt(quantity) + 1n, closeIntent.price)).to.revertedWithCustomError(
				context.partyBCloseFacet,
				"InvalidFillAmount",
			)
			await expect(partyB1.fillCloseIntent(closeIntent.id, quantity, closeIntent.price)).not.to.reverted
		})

		it("Should set the Trade as Closed when close Quantity match trade quantity", async () => {
			const newBlockTime = (await getLatestBlockTime()) + 150

			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(newBlockTime)
				.expirationTimestamp(newBlockTime)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build()

			await partyA1.sendOpenIntent(request)
			const lastIntentID = await context.viewFacet.getLastOpenIntentId()
			const intent = await context.viewFacet.getOpenIntent(lastIntentID)

			await partyB1.lockOpenIntent(lastIntentID)
			await partyB1.fillOpenIntent(lastIntentID, intent.tradeAgreements.quantity, intent.price)

			const lastTradeID = await context.viewFacet.getLastTradeId()
			let trade = await context.viewFacet.getTrade(lastTradeID)
			await partyA1.sendCloseIntent(lastTradeID, trade.tradeAgreements.quantity, trade.openedPrice, newBlockTime + 180) // longer deadline than option expire

			const lastCloseID = await context.viewFacet.getLastCloseIntentId()
			let closeIntent = await context.viewFacet.getCloseIntent(lastCloseID)

			await expect(partyB1.fillCloseIntent(closeIntent.id, closeIntent.quantity, closeIntent.price + 100n)).not.to.reverted

			closeIntent = await context.viewFacet.getCloseIntent(lastCloseID)
			trade = await context.viewFacet.getTrade(lastTradeID)

			console.log("Trade ID:", trade.id)
			console.log("Trade Quantity:", trade.tradeAgreements.quantity)
			console.log("Trade Status: ", trade.status == BigInt(TradeStatus.CLOSED) ? "Closed" : trade.status)

			console.log("Close ID:", closeIntent.id)
			console.log("Close Trade ID:", closeIntent.tradeId)
			console.log("Close Intent Quantity:", closeIntent.quantity)
			console.log("Close Intent Filled Amount:", closeIntent.filledAmount)
			console.log("Close Intent Status: ", closeIntent.status == BigInt(CloseIntentStatus.FILLED) ? "Filled" : trade.status)

			expect(closeIntent.filledAmount).to.equal(closeIntent.quantity)
			expect(closeIntent.quantity).to.be.equal(trade.tradeAgreements.quantity)
			expect(closeIntent.status).to.equal(CloseIntentStatus.FILLED)
			expect(trade.status).to.be.equal(TradeStatus.CLOSED)
		})

		it("Should fail when Trade status not OPEN", async () => {
			// make the Trade Closed
			const newBlockTime = (await getLatestBlockTime()) + 150

			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(newBlockTime)
				.expirationTimestamp(newBlockTime)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build()

			await partyA1.sendOpenIntent(request)
			const lastIntentID = await context.viewFacet.getLastOpenIntentId()
			const intent = await context.viewFacet.getOpenIntent(lastIntentID)

			await partyB1.lockOpenIntent(lastIntentID)
			await partyB1.fillOpenIntent(lastIntentID, intent.tradeAgreements.quantity, intent.price)

			const lastTradeID = await context.viewFacet.getLastTradeId()
			let trade = await context.viewFacet.getTrade(lastTradeID)
			await partyA1.sendCloseIntent(lastTradeID, trade.tradeAgreements.quantity, trade.openedPrice, newBlockTime + 180) // longer deadline than option expire

			const lastCloseID = await context.viewFacet.getLastCloseIntentId()
			let closeIntent = await context.viewFacet.getCloseIntent(lastCloseID)

			await expect(partyB1.fillCloseIntent(closeIntent.id, closeIntent.quantity, closeIntent.price + 100n)).not.to.reverted

			closeIntent = await context.viewFacet.getCloseIntent(lastCloseID)
			trade = await context.viewFacet.getTrade(lastTradeID)

			await expect(partyA1.sendCloseIntent(trade.id, e(1), trade.openedPrice + 1n, newBlockTime)).to.be.revertedWithCustomError(
				context.partyACloseFacet,
				"InvalidState",
			)
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

			const lastId = await context.viewFacet.getLastOpenIntentId()

			await partyB1.lockOpenIntent(lastId)
			await partyB1.fillOpenIntent(lastId, 100, 7)

			const tradeId = await context.viewFacet.getLastTradeId()

			await partyA1.sendCloseIntent(tradeId, 100, 7, newBlockTime + 180) // longer deadline than option expire

			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTime + 12])
			await network.provider.send("evm_mine")

			const lastCloseId = await context.viewFacet.getLastCloseIntentId()
			await expect(partyB1.fillCloseIntent(lastCloseId, 1, 7)).to.revertedWithCustomError(context.partyBCloseFacet, "TradeExpired")
		})

		it("Should failed when Fill Close Intent price not in range For BUY Trades", async () => {
			const closeIntent1 = await context.viewFacet.getCloseIntent(1)
			const closeIntent2 = await context.viewFacet.getCloseIntent(2)

			await expect(partyB1.fillCloseIntent(closeIntent1.id, closeIntent1.quantity, closeIntent1.price - 1n)).to.revertedWithCustomError(
				context.partyBCloseFacet,
				"InvalidClosePrice",
			)
			await expect(partyB1.fillCloseIntent(closeIntent1.id, closeIntent1.quantity, closeIntent1.price + 1n)).not.to.reverted

			await expect(partyB1.fillCloseIntent(closeIntent2.id, closeIntent2.quantity, closeIntent2.price - 1n)).to.revertedWithCustomError(
				context.partyBCloseFacet,
				"InvalidClosePrice",
			)
			await expect(partyB1.fillCloseIntent(closeIntent2.id, closeIntent2.quantity, closeIntent2.price + 1n)).not.to.reverted
		})

		it("Should failed when Fill Close Intent price not in range For SELL Trades", async () => {
			const closeIntent3 = await context.viewFacet.getCloseIntent(3)
			const trade = await context.viewFacet.getTrade(closeIntent3.tradeId)

			await expect(partyB2.fillCloseIntent(closeIntent3.id, closeIntent3.quantity, closeIntent3.price + 1n)).to.revertedWithCustomError(
				context.partyBCloseFacet,
				"InvalidClosePrice",
			)
			await expect(partyB2.fillCloseIntent(closeIntent3.id, closeIntent3.quantity, closeIntent3.price - 1n)).not.to.reverted
		})

		it("Should ADD profit to Party A balances as expected in Isolated mode(Buy Trade)", async () => {
			//take balance snapshot

			const division = 2n
			const closeIntentID = 1
			const closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(closeIntentID)
			closeIntent.quantity

			const partyBBalanceBefore = await context.viewFacet.getIsolatedBalance(partyB1.getSigner, context.collateral)
			const partyABalanceBefore = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral)

			const halfQuantity = BigInt(closeIntent.quantity) / division
			const price = BigInt(closeIntent.price) + 1000n // Close Premium
			await expect(partyB1.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted

			// more than 2 intervals pass for schedules
			let newBlockTime = (await getLatestBlockTime()) + 36
			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTime])
			await network.provider.send("evm_mine")

			await expect(partyB1.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted

			const trade: TradeStruct = await context.viewFacet.getTrade(closeIntent.tradeId)
			const symbol: SymbolStruct = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			const partyBBalanceAfter = await context.viewFacet.getIsolatedBalance(trade.partyB, symbol.collateral)
			let partyABalanceAfter = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral)
			const premium = await context.viewFacet.getTradePremium(closeIntent.tradeId)
			let scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA1.getSigner, context.collateral, partyB1.getSigner)

			const partyAProfit = (BigInt(price) * BigInt(division * halfQuantity)) / parseUnits("1", 18)
			const finalPremium = (premium * division * halfQuantity) / BigInt(trade.tradeAgreements.quantity)

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
			console.log("PartyA profit Calculation:", partyAProfit)

			//for party A we expect to have half of its output as the balance is scheduled and updated using sync function
			expect(partyABalanceAfter - partyABalanceBefore).to.be.equal(partyAProfit / division)

			newBlockTime = (await getLatestBlockTime()) + 12
			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTime])
			await network.provider.send("evm_mine")

			expect(scheduleEntry.scheduled).to.be.equal(partyAProfit / division)

			await context.accountFacet.syncBalances(context.collateral, partyA1.getSigner, [partyB1.getSigner])
			scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA1.getSigner, context.collateral, partyB1.getSigner)

			expect(scheduleEntry.transitioning).to.be.equal(partyAProfit / division)

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

			expect(partyABalanceAfter - partyABalanceBefore).to.be.equal(partyAProfit)
		})

		it("Should Change Party B balances as expected(finalPremium - partyAProfit) in Isolated mode(Buy Trade)", async () => {
			//take balance snapshot

			const division = 2n
			const closeIntentID = 1
			const closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(closeIntentID)
			closeIntent.quantity

			const partyBBalanceBefore = await context.viewFacet.getIsolatedBalance(partyB1.getSigner, context.collateral)
			const partyABalanceBefore = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral)

			const halfQuantity = BigInt(closeIntent.quantity) / division
			const price = BigInt(closeIntent.price) + 1000n // party B says I can buy higher
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

			const partyAProfit = (BigInt(price) * division * halfQuantity) / parseUnits("1", 18)
			const finalPremium = (premium * division * halfQuantity) / BigInt(trade.tradeAgreements.quantity)

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
			console.log("PartyA profit Calculation:", partyAProfit)

			// base on close quantity that is 100(two 50) and the price 8, we expect the balances to be(2pnl as we have 2*50 quantity)
			expect(partyBBalanceAfter - partyBBalanceBefore).to.be.equal(finalPremium - partyAProfit)
		})

		it("Should Add Profit to Party A balances as expected in Cross mode(Buy Trade)", async () => {
			const division = 2n
			const closeIntentID = 2
			const closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(closeIntentID)

			//take balance snapshot
			const partyACrossBalanceBefore = await context.viewFacet.getCrossBalance(partyA1.address, context.collateral, partyB1.address)
			let partyBCrossBalanceBefore = await context.viewFacet.getCrossBalance(partyB1.address, context.collateral, partyA1.address)

			const halfQuantity = BigInt(closeIntent.quantity) / division
			const price = BigInt(closeIntent.price) + 1000n // party B says I can buy higher
			await expect(partyB1.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted
			await expect(partyB1.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted

			const trade: TradeStruct = await context.viewFacet.getTrade(closeIntent.tradeId)
			const premium = await context.viewFacet.getTradePremium(closeIntent.tradeId)
			let partyACrossBalanceAfter = await context.viewFacet.getCrossBalance(partyA1.getSigner, context.collateral, partyB1.address)
			let partyBCrossBalanceAfter = await context.viewFacet.getCrossBalance(partyB1.address, context.collateral, partyA1.address)

			const partyAProfit = (BigInt(price) * division * halfQuantity) / parseUnits("1", 18)
			const finalPremium = (premium * division * halfQuantity) / BigInt(trade.tradeAgreements.quantity)

			console.log("PartyA Cross balance before fill to close intent:", partyACrossBalanceBefore)
			console.log("PartyA Cross balance after fill to close intent:", partyACrossBalanceAfter)
			console.log("PartyB Cross balance before fill to close intent:", partyBCrossBalanceBefore)
			console.log("PartyB Cross balance after fill to close intent:", partyBCrossBalanceAfter)
			console.log("Trade agreement Quantity:", trade.tradeAgreements.quantity)
			console.log("Fill Close Intent Quantity:", halfQuantity * division)
			console.log("Fill Close Intent Price:", price)
			console.log("Premium Calculation:", finalPremium)
			console.log("PNL Calculation:", partyAProfit)
			console.log("Diff:", partyAProfit - finalPremium)

			expect(partyACrossBalanceAfter.balance - partyACrossBalanceBefore.balance).to.be.equal(partyAProfit) // It must be positive as is Profit
		})

		it("Should Change Party B Cross balances as expected(finalPremium - partyAProfit) in Cross mode(Buy Trade)", async () => {
			const division = 2n
			const closeIntentID = 2
			const closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(closeIntentID)

			//take balance snapshot
			let partyBCrossBalanceBefore = await context.viewFacet.getCrossBalance(partyB1.address, context.collateral, partyA1.address)

			const halfQuantity = BigInt(closeIntent.quantity) / division
			const price = BigInt(closeIntent.price) + 1000n // party B says I can buy higher
			await expect(partyB1.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted
			await expect(partyB1.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted

			const trade: TradeStruct = await context.viewFacet.getTrade(closeIntent.tradeId)
			const premium = await context.viewFacet.getTradePremium(closeIntent.tradeId)
			let partyBCrossBalanceAfter = await context.viewFacet.getCrossBalance(partyB1.address, context.collateral, partyA1.address)

			const SCALE = parseUnits("1", 18)
			const partyAProfit = (BigInt(price) * halfQuantity * division) / SCALE
			const finalPremium = (premium * division * halfQuantity) / BigInt(trade.tradeAgreements.quantity)

			console.log("PartyB Cross balance before fill to close intent:", partyBCrossBalanceBefore)
			console.log("PartyB Cross balance after fill to close intent:", partyBCrossBalanceAfter)
			console.log("Trade agreement Quantity:", trade.tradeAgreements.quantity)
			console.log("Fill Close Intent Quantity:", halfQuantity * division)
			console.log("Fill Close Intent Price:", price)
			console.log("Premium Calculation:", finalPremium)
			console.log("PNL Calculation:", partyAProfit)
			console.log("Diff:", partyAProfit - finalPremium)

			expect(partyBCrossBalanceAfter.balance - partyBCrossBalanceBefore.balance).to.be.equal(finalPremium - partyAProfit)
		})

		it("Should change Party B Cross balances as expected(party A Profit - final Premium) in Cross mode(Sell Trade)", async () => {
			const division = 2n
			const priceDiff = 100n
			const closeIntentID = 3
			const closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(closeIntentID)

			//take balance snapshot
			const partyACrossBalanceBefore = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			let partyBCrossBalanceBefore = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)

			const halfQuantity = BigInt(closeIntent.quantity) / division
			const price = BigInt(closeIntent.price) - priceDiff
			await expect(partyB2.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted
			await expect(partyB2.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted

			const trade: TradeStruct = await context.viewFacet.getTrade(closeIntent.tradeId)
			const symbol: SymbolStruct = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			const premium = await context.viewFacet.getTradePremium(closeIntent.tradeId)
			let partyACrossBalanceAfter = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			let partyBCrossBalanceAfter = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)

			// const partyAProfit = (BigInt(price) * BigInt(2n * halfQuantity)) / BigInt(1000000000000000000)
			// const scale = parseEther("1")
			// const SCALE = 1_000_000_000_000_000_000n
			const SCALE = parseUnits("1", 18)
			const partyBProfit = (BigInt(price) * halfQuantity * division) / SCALE
			const finalPremium = (premium * division * halfQuantity) / BigInt(trade.tradeAgreements.quantity)

			console.log("PartyA Cross balance before fill to close intent:", partyACrossBalanceBefore)
			console.log("PartyA Cross balance after fill to close intent:", partyACrossBalanceAfter)
			console.log("PartyB Cross balance before fill to close intent:", partyBCrossBalanceBefore)
			console.log("PartyB Cross balance after fill to close intent:", partyBCrossBalanceAfter)
			console.log("Trade agreement Quantity:", trade.tradeAgreements.quantity)
			console.log("Fill Close Intent Quantity:", halfQuantity * division)
			console.log("Fill Close Intent Price:", price)
			console.log("Premium Payed to Party A:", finalPremium)
			console.log("PartyB  Profit:", partyBProfit)
			console.log("PartyB vs PartyA Diff(negative means Party A Profit):", partyBProfit - finalPremium)

			expect(partyBCrossBalanceAfter.balance - partyBCrossBalanceBefore.balance).to.be.equal(partyBProfit)
		})

		it("Should change Party A MM balances as expected(Decrease TotalMM) in Cross mode(Sell Trade)", async () => {
			const division = 2n
			const priceDiff = 100n
			const closeIntentID = 3
			const closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(closeIntentID)

			//take balance snapshot
			const partyACrossBalanceBefore = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)

			const halfQuantity = BigInt(closeIntent.quantity) / division
			const price = BigInt(closeIntent.price) - priceDiff
			await expect(partyB2.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted
			await expect(partyB2.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted

			const trade: TradeStruct = await context.viewFacet.getTrade(closeIntent.tradeId)
			let partyACrossBalanceAfter = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)

			console.log("PartyA Cross balance before fill to close intent:", partyACrossBalanceBefore)
			console.log("PartyA Cross balance after fill to close intent:", partyACrossBalanceAfter)
			const SCALE = parseUnits("1", 18)
			const finalMM = (BigInt(trade.tradeAgreements.mm) * halfQuantity * division) / BigInt(trade.tradeAgreements.quantity)

			expect(partyACrossBalanceBefore.totalMM - partyACrossBalanceAfter.totalMM).to.be.equal(finalMM)
		})

		it("Should change Party A Cross balances as expected in Cross mode(Sell Trade)", async () => {
			const division = 2n
			const priceDiff = 100n
			const closeIntentID = 3
			const closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(closeIntentID)

			//take balance snapshot
			const partyACrossBalanceBefore = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			const partyBCrossBalanceBefore = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)

			const halfQuantity = BigInt(closeIntent.quantity) / division
			const price = BigInt(closeIntent.price) - priceDiff // party B says I can sell lower
			await expect(partyB2.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted
			await expect(partyB2.fillCloseIntent(closeIntentID, halfQuantity, price)).to.not.be.reverted

			const trade: TradeStruct = await context.viewFacet.getTrade(closeIntent.tradeId)
			const symbol: SymbolStruct = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			const premium = await context.viewFacet.getTradePremium(closeIntent.tradeId)
			const partyACrossBalanceAfter = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			const partyBCrossBalanceAfter = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)

			const SCALE = parseUnits("1", 18)
			const partyBProfit = (BigInt(price) * halfQuantity * division) / SCALE
			const finalPremium = (premium * halfQuantity * division) / BigInt(trade.tradeAgreements.quantity)

			console.log("PartyA Cross balance before fill to close intent:", partyACrossBalanceBefore)
			console.log("PartyA Cross balance after fill to close intent:", partyACrossBalanceAfter)
			console.log("PartyB Cross balance before fill to close intent:", partyBCrossBalanceBefore)
			console.log("PartyB Cross balance after fill to close intent:", partyBCrossBalanceAfter)
			console.log("Trade agreement Quantity:", trade.tradeAgreements.quantity)
			console.log("Fill Close Intent Quantity:", halfQuantity * 2n)
			console.log("Fill Close Intent Price:", price)
			console.log("Premium Calculation:", finalPremium)
			console.log("PNL Calculation:", partyBProfit)
			console.log("Diff:", partyBProfit - finalPremium)

			expect(partyACrossBalanceBefore.balance - partyACrossBalanceAfter.balance).to.be.equal(partyBProfit)
		})

		it("Should pay fees to affiliate collector as expected", async () => {
			const division = 2n
			const priceDiff = 100n
			const closeIntentId = 1
			const closeIntent = await context.viewFacet.getCloseIntent(closeIntentId)
			const openTrade = await context.viewFacet.getTrade(closeIntent.tradeId)

			await context.controlFacet.setAffiliateFeesCollector(openTrade.affiliate, openTrade.affiliate)

			const affiliateBalanceBefore = await context.viewFacet.getIsolatedBalance(openTrade.affiliate, await context.collateralNL.getAddress())

			const price = closeIntent.price + priceDiff
			const quantity = closeIntent.quantity / division
			await expect(partyB1.fillCloseIntent(closeIntent.id, quantity, price)).not.to.reverted

			const affiliateBalanceAfter = await context.viewFacet.getIsolatedBalance(openTrade.affiliate, await context.collateralNL.getAddress())
			const partyAFeeBalance = await context.viewFacet.getIsolatedBalance(partyA1.address, await context.collateralNL.getAddress())

			const intentTradingFee = await context.viewFacet.getCloseIntentPlatformFee(closeIntent.id, quantity, price) //Platform Fee
			const intentAffiliateFee = await context.viewFacet.getCloseIntentAffiliateFee(closeIntent.id, quantity, price) //Affiliate Fee

			const affiliateFeeCalculated =
				(quantity * price * closeIntent.feeStructure.affiliateFee.closeFee) / (openTrade.feeStructure.tokenPriceInCollateral * parseUnits("1", 18))

			console.log("Affiliate Address:", openTrade.affiliate)
			console.log("Intent Trading Fee", intentTradingFee)
			console.log("Intent Affiliate Fee", intentAffiliateFee)
			console.log("Calculated Intent Affiliate Fee", affiliateFeeCalculated)
			console.log("Affiliate Fee collector Balance Before", affiliateBalanceBefore)
			console.log("Affiliate Fee collector Balance After", affiliateBalanceAfter)
			console.log("Party A Fee Balance", partyAFeeBalance)

			expect(affiliateFeeCalculated).to.be.equal(intentAffiliateFee)

			expect(affiliateBalanceAfter - affiliateBalanceBefore).to.equal(intentAffiliateFee)
		})

		it("Should pay fees to Protocol Fee Collector as Expected", async () => {
			const division = 2n
			const priceDiff = 100n
			const closeIntentId = 1
			await context.controlFacet.setDefaultFeeCollector(partyA3.address)
			const defaultFeeBalanceBefore = await context.viewFacet.getIsolatedBalance(partyA3.address, await context.collateralNL.getAddress())

			const closeIntent = await context.viewFacet.getCloseIntent(closeIntentId)
			const openTrade = await context.viewFacet.getTrade(closeIntent.tradeId)
			const partyAFeeBalanceBefore = await context.viewFacet.getIsolatedBalance(openTrade.partyA, await context.collateralNL.getAddress())

			const quantity = closeIntent.quantity / division
			const price = closeIntent.price + priceDiff
			await expect(partyB1.fillCloseIntent(closeIntent.id, quantity, price)).not.to.reverted

			const defaultFeeBalanceAfter = await context.viewFacet.getIsolatedBalance(partyA3.address, await context.collateralNL.getAddress())
			const partyAFeeBalanceAfter = await context.viewFacet.getIsolatedBalance(openTrade.partyA, await context.collateralNL.getAddress())

			const intentPlatformFee = await context.viewFacet.getCloseIntentPlatformFee(closeIntent.id, quantity, price) //Platform Fee
			const intentAffiliateFee = await context.viewFacet.getCloseIntentAffiliateFee(closeIntent.id, quantity, price) //Affiliate Fee

			const platformFeeCalculated =
				(quantity * price * closeIntent.feeStructure.platformFee.closeFee) / (openTrade.feeStructure.tokenPriceInCollateral * parseUnits("1", 18))

			console.log("Intent Platform Fee", intentPlatformFee)
			console.log("Calculated Intent Platform Fee", platformFeeCalculated)
			console.log("Default Fee collector Balance Before", defaultFeeBalanceBefore)
			console.log("Default Fee collector Balance After", defaultFeeBalanceAfter)
			console.log("Diff", defaultFeeBalanceAfter - defaultFeeBalanceBefore)
			console.log("Party A Fee Balance Before", partyAFeeBalanceBefore)
			console.log("Party A Fee Balance After", partyAFeeBalanceAfter)

			expect(platformFeeCalculated).to.be.equal(intentPlatformFee)

			expect(defaultFeeBalanceAfter - defaultFeeBalanceBefore).to.equal(intentPlatformFee)
		})

		it("Should pay solver fees To Party B as expected in Isolated Margin", async () => {
			const division = 2n
			const priceDiff = 100n
			const closeIntentId = 1
			const closeIntent = await context.viewFacet.getCloseIntent(closeIntentId)
			const openTrade = await context.viewFacet.getTrade(closeIntent.tradeId)
			const partyBFeeBalanceBefore = await context.viewFacet.getIsolatedBalance(openTrade.partyB, await context.collateralNL.getAddress())

			const quantity = closeIntent.quantity / division
			const price = closeIntent.price + priceDiff
			await expect(partyB1.fillCloseIntent(closeIntent.id, quantity, price)).not.to.reverted

			const partyBFeeBalanceAfter = await context.viewFacet.getIsolatedBalance(openTrade.partyB, await context.collateralNL.getAddress())

			const solverFeePaid =
				(quantity * price * closeIntent.feeStructure.solverFee.closeFee) / (openTrade.feeStructure.tokenPriceInCollateral * parseUnits("1", 18))
			console.log("partyB Fee Balance Before", partyBFeeBalanceBefore)
			console.log("partyB Fee Balance After", partyBFeeBalanceAfter)
			console.log("Solver Fee rate:", openTrade.feeStructure.solverFee)
			console.log("Solver Fee calculated:", solverFeePaid)
			console.log("Fee Token Price to Collateral", openTrade.feeStructure.tokenPriceInCollateral)

			expect(partyBFeeBalanceAfter - partyBFeeBalanceBefore).to.equal(solverFeePaid)
		})

		it("Should pay solver fees To Party B as expected in BUY Cross Margin", async () => {
			const division = 2n
			const priceDiff = 100n
			const closeIntentId = 2
			const closeIntent = await context.viewFacet.getCloseIntent(closeIntentId)
			const openTrade = await context.viewFacet.getTrade(closeIntent.tradeId)
			const partyBFeeBalanceBefore = await context.viewFacet.getCrossBalance(
				openTrade.partyB,
				await context.collateralNL.getAddress(),
				openTrade.partyA,
			)

			const quantity = closeIntent.quantity / division
			const price = closeIntent.price + priceDiff
			await expect(partyB1.fillCloseIntent(2, quantity, price)).not.to.reverted

			const partyBFeeBalanceAfter = await context.viewFacet.getCrossBalance(
				openTrade.partyB,
				await context.collateralNL.getAddress(),
				openTrade.partyA,
			)

			const solverFeePaid =
				(quantity * price * closeIntent.feeStructure.solverFee.closeFee) / (openTrade.feeStructure.tokenPriceInCollateral * parseUnits("1", 18))
			console.log("partyB Fee Balance Before", partyBFeeBalanceBefore)
			console.log("partyB Fee Balance After", partyBFeeBalanceAfter)
			console.log("Solver Fee rate:", openTrade.feeStructure.solverFee)
			console.log("Solver Fee calculated:", solverFeePaid)
			console.log("Fee Token Price to Collateral", openTrade.feeStructure.tokenPriceInCollateral)

			expect(partyBFeeBalanceAfter.balance - partyBFeeBalanceBefore.balance).to.equal(solverFeePaid)
		})
	})
}
