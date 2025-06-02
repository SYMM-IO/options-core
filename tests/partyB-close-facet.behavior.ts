import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { MarginType, TradeSide } from "./option-enums"
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
			.marginType(MarginType.CROSS)
			.build()

		await partyA1.sendOpenIntent(request)
		await partyA1.sendOpenIntent(requestCross)
		await partyB1.lockOpenIntent(1)
		await partyB1.lockOpenIntent(2)
		await partyB1.fillOpenIntent(1, e(100), 7)
		await partyB1.fillOpenIntent(2, e(100), 7)
		await partyA1.sendCloseIntent(1, 7, e(100), (await getLatestBlockTime()) + 120)
		await partyA1.sendCloseIntent(2, 7, e(100), (await getLatestBlockTime()) + 120)
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
			await partyB1.fillCloseIntent(1, 5, 7)
			await expect(partyB1.fillCloseIntent(1, e(101), 7)).to.revertedWithCustomError(context.partyBCloseFacet, "InvalidFilledAmount")
			await expect(partyB1.fillCloseIntent(1, e(95), 7)).not.to.revertedWithCustomError(context.partyBCloseFacet, "InvalidFilledAmount")
		})

		it("Should failed when Close Intent is expired", async () => {
			const newBlock = (await getLatestBlockTime()) + 150
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			await expect(partyB1.fillCloseIntent(1, 96, 7)).to.revertedWithCustomError(context.partyBCloseFacet, "IntentExpired")
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
			await partyA1.sendCloseIntent(3, 7, 100, newBlockTime + 180) // longer deadline than option expire

			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTime])
			await network.provider.send("evm_mine")
			await expect(partyB1.fillCloseIntent(3, 96, 7)).to.revertedWithCustomError(context.partyBCloseFacet, "TradeExpired")
		})

		it("Should failed when price to fill not in range", async () => {
			let trade: TradeStructOutput = await context.viewFacet.getTrade(1)
			if (trade.tradeAgreements.tradeSide == e(TradeSide.BUY)) {
				await expect(partyB1.fillCloseIntent(1, e(96), 5)).to.revertedWithCustomError(context.partyBCloseFacet, "InvalidClosedPrice")
				expect(partyB1.fillCloseIntent(1, 96, 10)).not.to.revertedWithCustomError(context.partyBCloseFacet, "InvalidClosedPrice")
			} else if (trade.tradeAgreements.tradeSide == BigInt(TradeSide.SELL)) {
				await expect(partyB1.fillCloseIntent(1, 96, 10)).to.revertedWithCustomError(context.partyBCloseFacet, "InvalidClosedPrice")
				expect(partyB1.fillCloseIntent(1, 96, 5)).not.to.revertedWithCustomError(context.partyBCloseFacet, "InvalidClosedPrice")
			}
		})

		it("Should change balances for parties as expected in Isolated mode", async () => {
			//take balance snapshot
			const quantity = e(50)
			const price = 8
			const partyBBalanceBefore = await context.viewFacet.balanceOf(partyB1.getSigner, context.collateral)
			const partyABalanceBefore = await context.viewFacet.balanceOf(partyA1.getSigner, context.collateral)
			await expect(partyB1.fillCloseIntent(1, quantity, price)).to.not.be.reverted

			// some time pass for schedules
			const newBlockTime = (await getLatestBlockTime()) + 100
			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTime])
			await network.provider.send("evm_mine")

			// expect(partyBBalanceBefore - partyBBalanceAfter).to.be.equal(100) // pnl - premium
			await expect(partyB1.fillCloseIntent(1, quantity, price)).to.not.be.reverted

			const closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(1)
			const trade: TradeStruct = await context.viewFacet.getTrade(closeIntent.tradeId)
			const symbol: SymbolStruct = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			const partyBBalanceAfter = await context.viewFacet.balanceOf(trade.partyB, symbol.collateral)
			const premium = await context.viewFacet.getTradePremium(closeIntent.tradeId)
			const partyABalanceAfter = await context.viewFacet.balanceOf(partyA1.getSigner, context.collateral)

			console.log("PartyB balance before fill to close intent:", partyBBalanceBefore)
			console.log("PartyA balance before fill to close intent:", partyABalanceBefore)
			console.log("PartyB balance after fill to close intent:", partyBBalanceAfter)
			console.log("PartyA balance after fill to close intent:", partyABalanceAfter)
			console.log("Trade agreement Quantity:", trade.tradeAgreements.quantity)
			console.log("Fill Close Intent Quantity:", quantity)
			console.log("Fill Close Intent Price:", price)
			console.log("Calculation:", (premium * quantity) / BigInt(trade.tradeAgreements.quantity))

			let pnl = (BigInt(price) * BigInt(quantity)) / BigInt(1000000000000000000)

			// base on input quantity that is 100 and the price 8, we expect the balances to be
			expect(partyBBalanceAfter - partyBBalanceBefore).to.be.equal(premium - (pnl + pnl))

			//for party A we expect to have half of its output as the balance is scheduled and updated using sync function
			expect(partyABalanceAfter - partyABalanceBefore).to.be.equal(pnl)
		})

		it("Should change balances for parties as expected in Cross mode", async () => {})
	})
}
