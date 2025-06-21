import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { TradeSide } from "./option-enums"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { ZeroAddress } from "ethers"
import { partyAClose } from "../types/contracts/facets"
import { TradeStructOutput } from "../types/contracts/facets/ViewFacet/IViewFacet"
import { SettlementPriceSigStruct } from "../types/contracts/facets/TradeSettlement/ITradeSettlementFacet"
import { settlementSigBuilder } from "./models/builders/settlement.builder"
import { CloseIntentStruct, TradeStruct } from "../types/contracts/interfaces/ISymmio"
import { request } from "http"
import { getLatestBlockTime } from "../utils/time"

export function shouldBehaveLikeSettlementFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyB1.setBalances(context.collateral, e(100000), e(100000))
		await partyB2.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateral, e(100000), e(100000))
		await partyA2.setBalances(context.collateral, e(100000), e(100000))

		const request = openIntentRequestBuilder()
			.partyBsWhiteList([partyB1.getSigner])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateral)
			.symbolId(1)
			.deadline((await getLatestBlockTime()) + 140)
			.expirationTimestamp((await getLatestBlockTime()) + 150)
			.exerciseFee({ cap: e(1), rate: e(1) })
			.quantity(e(100))
			.strikePrice(60)
			.price(7)
			.build()

		await partyA1.sendOpenIntent(request)
		await partyB1.lockOpenIntent(1)
		await partyB1.fillOpenIntent(1, e(100), 7)
		await partyA1.sendCloseIntent(1, 7, e(50), (await getLatestBlockTime()) + 120)
		await partyB1.fillCloseIntent(1, e(50), 7)

		const newBlock = (await getLatestBlockTime()) + 170
		await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
		await network.provider.send("evm_mine")
	})

	describe("executeTrade", async function () {
		it("Should be failed when Globally Paused", async () => {
			const timestamp = await getLatestBlockTime()
			await context.controlFacet.pauseGlobal()

			const ID = 1
			const priceSig: SettlementPriceSigStruct = settlementSigBuilder().build()
			await expect(context.tradeSettlementFacet.executeTrade(ID, priceSig)).to.be.revertedWithCustomError(
				context.tradeSettlementFacet,
				"GlobalPaused",
			)
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			const timestamp = await getLatestBlockTime()

			const ID = 1
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 100,
				symbolId: 1,
				settlementPrice: 7,
				settlementTimestamp: timestamp,
				collateralPrice: 8,
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			await expect(context.tradeSettlementFacet.executeTrade(ID, priceSig)).to.be.revertedWithCustomError(
				context.tradeSettlementFacet,
				"PartyBActionsPaused",
			)
		})

		it("Should failed when signature symbol not as trade symbol", async () => {
			const timestamp = await getLatestBlockTime()

			const ID = 1
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 100,
				symbolId: 2,
				settlementPrice: 40,
				settlementTimestamp: timestamp,
				collateralPrice: 30,
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			await expect(context.tradeSettlementFacet.executeTrade(ID, priceSig)).to.be.revertedWithCustomError(
				context.tradeSettlementFacet,
				"MismatchedSymbolId",
			)
		})

		it("Should failed when trade has no open amount", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(1), rate: e(1) })
				.quantity(e(100))
				.strikePrice(60)
				.price(7)
				.build()

			await partyA1.sendOpenIntent(request)
			await partyB1.lockOpenIntent(2) // second (this) intent
			await partyB1.fillOpenIntent(2, e(100), 7)
			await partyA1.sendCloseIntent(2, 7, e(100), (await getLatestBlockTime()) + 120)
			let closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(2)
			console.log("Settlement Close Intent Quantity: ", closeIntent.quantity)
			console.log("Settlement Close Intent Filled Amount: ", closeIntent.filledAmount)

			await partyB1.fillCloseIntent(2, e(100), 7)
			closeIntent = await context.viewFacet.getCloseIntent(2)
			console.log("Settlement After Fill Close Intent Quantity: ", closeIntent.quantity)
			console.log("Settlement After Fill Close Intent Filled Amount: ", closeIntent.filledAmount)

			const timestamp = await getLatestBlockTime()
			const tradeID = 2
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 100,
				symbolId: 1,
				settlementPrice: 40,
				settlementTimestamp: timestamp,
				collateralPrice: 30,
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			await expect(context.tradeSettlementFacet.executeTrade(tradeID, priceSig)).to.be.revertedWithCustomError(
				context.tradeSettlementFacet,
				"InvalidState",
			)
		})

		it("Should be executed with option carried out as 'Isolated Buy' ", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.01), rate: e(1) })
				.quantity(e(100))
				.strikePrice(60)
				.price(7)
				.build()

			const intentID = 2
			const tradeID = 2

			await partyA2.sendOpenIntent(request)
			await partyB2.lockOpenIntent(intentID)
			const intentPremium = await context.viewFacet.getPremium(intentID)
			const partyBBalanceBeforeSettlementInit = await context.viewFacet.balanceOf(partyB2.getSigner, await context.collateral.getAddress())
			await partyB2.fillOpenIntent(intentID, e(100), 7)

			const closePrice = 7
			const closeQuantity = e(50)
			await partyA2.sendCloseIntent(tradeID, closePrice, closeQuantity, (await getLatestBlockTime()) + 120)
			const closeIntent = await context.viewFacet.getCloseIntent(1)
			await partyB2.fillCloseIntent(tradeID, closeIntent.quantity, closeIntent.price)

			const closePNL = (BigInt(closeIntent.price) * BigInt(closeIntent.quantity)) / BigInt(1000000000000000000)

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 180,
				symbolId: 1, // put option
				settlementPrice: 40,
				settlementTimestamp: timestamp,
				collateralPrice: 30,
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			const openAmount = await context.viewFacet.getOpenAmount(tradeID)
			let tradePremium = await context.viewFacet.getTradePremium(tradeID)
			const trade: TradeStruct = await context.viewFacet.getTrade(tradeID)

			let newBlock = Number(trade.tradeAgreements.expirationTimestamp) + 12
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			let tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)

			const pnl = await context.viewFacet.getPnL(tradeID, priceSig.settlementPrice, openAmount)
			const exerciseFee = await context.viewFacet.getExerciseFee(tradeID, priceSig.settlementPrice, pnl)

			const amountToTransfer = ethers.parseUnits((pnl - exerciseFee).toString(), 18) / BigInt(priceSig.collateralPrice)

			const optionSymbol = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			const partyABalanceBeforeSettlement = await context.viewFacet.balanceOf(partyA2.getSigner, await context.collateral.getAddress())
			const partyABalanceBeforeSettlementLocked = await context.viewFacet.getIsolatedLockedBalance(
				partyA2.getSigner,
				await context.collateral.getAddress(),
			)
			const partyBBalanceBeforeSettlement = await context.viewFacet.balanceOf(partyB2.getSigner, await context.collateral.getAddress())
			const partyBBalanceBeforeSettlementLocked = await context.viewFacet.getIsolatedLockedBalance(
				partyB2.getSigner,
				await context.collateral.getAddress(),
			)

			//Scheduling info
			const releaseInterval = await context.viewFacet.getReleaseInterval(partyA2.getSigner)
			let scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA2.getSigner, optionSymbol.collateral, partyB2.getSigner)

			console.log("Trade Open quantity:", openAmount)
			console.log("Trade Strike price:", trade.tradeAgreements.strikePrice)
			console.log("Trade Settlement price:", priceSig.settlementPrice)
			console.log("Trade Collateral price:", priceSig.collateralPrice)
			console.log("Trade PNL:", pnl)
			console.log("Intent Premium:", intentPremium)
			console.log("Overall Trade Premium:", tradePremium)
			console.log("This Trade Premium:", tradePremiumSettled)
			console.log("Schedule Interval:", releaseInterval)
			console.log("Schedule Entry Interval:", scheduleEntry.releaseInterval)
			console.log("Trade Exercise Fee calculated:", exerciseFee)
			console.log("Trade Exercise Fee, CAP:", trade.tradeAgreements.exerciseFee.cap)
			console.log("Trade Exercise Fee, RATE:", trade.tradeAgreements.exerciseFee.rate)
			console.log("Trade Value for PartyA(Amount to transfer):", amountToTransfer)
			console.log("Trade PartyA collateral balance:", partyABalanceBeforeSettlement)
			console.log("Trade PartyA collateral locked balance:", partyABalanceBeforeSettlementLocked)
			console.log("Trade PartyB collateral balance Init:", partyBBalanceBeforeSettlementInit)
			console.log("Trade PartyB collateral balance After Fill:", partyBBalanceBeforeSettlement)

			await expect(context.tradeSettlementFacet.executeTrade(tradeID, priceSig)).to.be.not.reverted

			// instant premium add to partyB balance
			const partyBBalanceAfterSettlement = await context.viewFacet.balanceOf(partyB2.getSigner, context.collateral)
			const partyABalanceAfterSettlement = await context.viewFacet.balanceOf(partyA2.getSigner, context.collateral)

			scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA2.getSigner, optionSymbol.collateral, partyB2.getSigner)

			let lastTimestamp = await getLatestBlockTime()
			newBlock = (await getLatestBlockTime()) + Number(releaseInterval) * 2
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			await context.controlFacet.syncTradeWindow(partyA2.getSigner, context.collateral, partyB2.getSigner)

			const partyABalanceAfterSettlementSchedule = await context.viewFacet.balanceOf(partyA2.getSigner, context.collateral)
			const partyBBalanceAfterSettlementSchedule = await context.viewFacet.balanceOf(partyB2.getSigner, context.collateral)

			console.log("Trade PartyB collateral balance After Settlement:", partyBBalanceAfterSettlement)
			console.log("Trade PartyB collateral balance After Settlement schedule:", partyBBalanceAfterSettlementSchedule)
			console.log("Trade PartyB collateral balance Diff from initial:", partyBBalanceBeforeSettlement - partyBBalanceAfterSettlementSchedule)
			console.log("Trade PartyA collateral balance After Settlement:", partyABalanceAfterSettlement)
			console.log("Trade PartyA collateral balance After Settlement schedule:", partyABalanceAfterSettlementSchedule)
			console.log("Trade PartyA collateral balance Diff from initial:", partyABalanceBeforeSettlement - partyBBalanceAfterSettlementSchedule)
			console.log("Schedule Entry Scheduled:", scheduleEntry.scheduled)
			console.log("Schedule Entry Transitioning:", scheduleEntry.transitioning)
			console.log("Schedule Entry last Timestamp:", scheduleEntry.lastTransitionTimestamp)
			console.log("Schedule Entry Release Interval:", scheduleEntry.releaseInterval)
			console.log("current Timestamp:", await getLatestBlockTime())
			console.log("last Timestamp:", lastTimestamp)

			// Party B
			expect(partyBBalanceAfterSettlement - partyBBalanceBeforeSettlement).to.be.equal(tradePremiumSettled - amountToTransfer)
			// Party A
			expect(partyABalanceAfterSettlementSchedule - partyABalanceBeforeSettlement).to.be.equal(amountToTransfer + closePNL)
		})

		it("Should be when executed with option carried out as 'Cross Buy' ", async () => {
			const timestamp = await getLatestBlockTime()
			const ID = 1
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 100,
				symbolId: 1,
				settlementPrice: 7,
				settlementTimestamp: timestamp,
				collateralPrice: 8,
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			await expect(context.tradeSettlementFacet.executeTrade(ID, priceSig)).to.be.not.reverted
		})

		it("Should be when executed with option carried out as 'Isolated Sell' ", async () => {
			const timestamp = await getLatestBlockTime()
			const ID = 1
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 100,
				symbolId: 1, // put option
				settlementPrice: 7,
				settlementTimestamp: timestamp,
				collateralPrice: 8,
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}
			await expect(context.tradeSettlementFacet.executeTrade(ID, priceSig)).to.be.not.reverted
		})

		it("Should be when executed with option carried out as 'Cross Sell' ", async () => {
			const timestamp = await getLatestBlockTime()
			const ID = 1
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 100,
				symbolId: 1,
				settlementPrice: 7,
				settlementTimestamp: timestamp,
				collateralPrice: 8,
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			expect(await context.tradeSettlementFacet.executeTrade(ID, priceSig)).to.be.not.reverted
		})
	})
}
