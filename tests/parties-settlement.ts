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
				"InvalidSymbolId",
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
			await partyB1.lockOpenIntent(2)
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
			const ID = 1
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

			//TODO
			// await expect(context.tradeSettlementFacet.executeTrade(ID, priceSig)).to.be.revertedWithCustomError(
			// 	context.tradeSettlementFacet,
			// 	"InvalidSymbolId",
			// )
		})

		it("Should be when executed with option carried out as 'Isolated Buy' ", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
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

			await partyA2.sendOpenIntent(request)
			await partyB2.lockOpenIntent(2)
			const intentPremium = await context.viewFacet.getPremium(2)
			await partyB2.fillOpenIntent(2, e(100), 7)

			await partyA2.sendCloseIntent(2, 7, e(50), (await getLatestBlockTime()) + 120)
			await partyB2.fillCloseIntent(2, e(50), 7)

			const timestamp = await getLatestBlockTime()
			const ID = 2
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

			const newBlock = (await getLatestBlockTime()) + 170
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			const openAmount = await context.viewFacet.getOpenAmount(2)
			const premium = await context.viewFacet.getTradePremium(2)

			const trade: TradeStruct = await context.viewFacet.getTrade(2)
			const pnl = await context.viewFacet.getPnL(2, priceSig.settlementPrice, openAmount)
			const exerciseFee = await context.viewFacet.getExerciseFee(2, priceSig.settlementPrice, pnl)

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

			console.log("Trade Open quantity:", openAmount)
			console.log("Trade Strike price:", trade.tradeAgreements.strikePrice)
			console.log("Trade Settlement price:", priceSig.settlementPrice)
			console.log("Trade PNL:", pnl)
			console.log("Intent Premium:", intentPremium)
			console.log("Trade Premium:", premium)
			console.log("Trade Exercise Fee calculated:", exerciseFee)
			console.log("Trade Exercise Fee, CAP:", trade.tradeAgreements.exerciseFee.cap)
			console.log("Trade Exercise Fee, RATE:", trade.tradeAgreements.exerciseFee.rate)
			console.log("Trade PartyA collateral balance:", partyABalanceBeforeSettlement)
			console.log("Trade PartyA collateral locked balance:", partyABalanceBeforeSettlementLocked)
			console.log("Trade PartyB collateral balance:", partyBBalanceBeforeSettlement)
			console.log("Trade PartyB collateral locked balance:", partyBBalanceBeforeSettlementLocked)

			expect(await context.tradeSettlementFacet.executeTrade(ID, priceSig)).to.be.not.reverted
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
