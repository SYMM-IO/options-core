import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import "@nomicfoundation/hardhat-ethers"
import { expect, use } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"

import { CloseIntentStruct, SettlementPriceSigStruct, TradeStruct } from "../types/contracts/interfaces/ISymmio"
import { getLatestBlockTime, moveTime } from "../utils/time"
import { settlementSigBuilder } from "./models/builders/settlement.builder"
import { parseUnits, ZeroAddress } from "ethers"
import { MarginType, OptionType, TradeSide, TradeStatus } from "./option-enums"

export function shouldBehaveLikeSettlementFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyB1.setBalances(context.collateral, e(100000), e(50000))
		await partyB2.setBalances(context.collateral, e(100000), e(50000))
		await partyA1.setBalances(context.collateral, e(100000), e(50000))
		await partyA2.setBalances(context.collateral, e(100000), e(50000))

		const request = openIntentRequestBuilder()
			.partyBsWhiteList([partyB1.address])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateral)
			.symbolId(1)
			.deadline((await getLatestBlockTime()) + 140)
			.expirationTimestamp((await getLatestBlockTime()) + 150)
			.exerciseFee({ cap: e(1), rate: e(1) })
			.quantity(e(100))
			.strikePrice(e(100))
			.price(e(10))
			.build()

		await partyA1.sendOpenIntent(request)
		await partyB1.lockOpenIntent(1)
		await partyB1.fillOpenIntent(1, e(100), e(10))

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
			await expect(context.tradeFacet.executeTrades([ID], priceSig)).to.be.revertedWithCustomError(context.tradeFacet, "GlobalPaused")
		})

		it("Should failed when ThirdParty action Paused", async () => {
			await context.controlFacet.pauseThirdPartyActions()
			const timestamp = await getLatestBlockTime()

			const ID = 1
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 100,
				symbolId: 1,
				settlementPrice: e(7),
				settlementTimestamp: timestamp,
				collateralPrice: e(8),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			await expect(context.tradeFacet.executeTrades([ID], priceSig)).to.be.revertedWithCustomError(context.tradeFacet, "ThirdPartyActionsPaused")
		})

		it("Should failed when signature symbol not as trade symbol", async () => {
			const timestamp = await getLatestBlockTime()

			const ID = 1
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 100,
				symbolId: 2,
				settlementPrice: e(40),
				settlementTimestamp: timestamp,
				collateralPrice: e(30),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			await expect(context.tradeFacet.executeTrades([ID], priceSig)).to.be.revertedWithCustomError(context.tradeFacet, "MismatchedSymbolId")
		})

		it("Should failed when trade has no open amount", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(1), rate: e(1) })
				.quantity(e(100))
				.strikePrice(e(60))
				.price(e(7))
				.build()

			await partyA1.sendOpenIntent(request)

			const lastIntentID = await context.viewFacet.getLastOpenIntentId()
			const intent = await context.viewFacet.getOpenIntent(lastIntentID)
			await partyB1.lockOpenIntent(lastIntentID) // second (this) intent
			await partyB1.fillOpenIntent(lastIntentID, intent.tradeAgreements.quantity, intent.price)

			await partyA1.sendCloseIntent(intent.id, intent.tradeAgreements.quantity, intent.price, (await getLatestBlockTime()) + 120)
			const closeIntentID = await context.viewFacet.getLastCloseIntentId()
			let closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(closeIntentID)
			console.log("Settlement Close Intent Quantity: ", closeIntent.quantity)
			console.log("Settlement Close Intent Filled Amount: ", closeIntent.filledAmount)

			await partyB1.fillCloseIntent(closeIntent.id, closeIntent.quantity, closeIntent.price)
			closeIntent = await context.viewFacet.getCloseIntent(closeIntent.id)
			console.log("Settlement After Fill Close Intent Quantity: ", closeIntent.quantity)
			console.log("Settlement After Fill Close Intent Filled Amount: ", closeIntent.filledAmount)

			const timestamp = await getLatestBlockTime()
			const tradeID = closeIntent.tradeId
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 100,
				symbolId: 1,
				settlementPrice: e(40),
				settlementTimestamp: timestamp,
				collateralPrice: e(30),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.be.revertedWithCustomError(context.tradeFacet, "InvalidState")
		})

		/////////////////////////// assumed values //////////////////////////////
		////////// collateral price = 1
		////////// option price = 10
		////////// fee token price = 1
		////////// strike price = 100
		////////// option type = 1 : PUT / 2 : CALL
		////////// affiliate and protocol fee : open intent = 0.001 / close intent = 0.003
		////////// solver fee : open intent = 0.001 / close intent = 0.01
		////////// execution fee = 1 (fix) + 0.001 (rate)
		it("Should be executed with option carried out as 'Isolated Buy' ", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.01), rate: e(1) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.build()

			await partyA2.setBalances(context.collateralNL, e(1000), e(500))
			await partyA2.sendOpenIntent(request)

			const openIntentId = await context.viewFacet.getLastOpenIntentId()

			await partyB2.lockOpenIntent(openIntentId)
			const intentPremium = await context.viewFacet.getOpenIntentPremium(openIntentId)
			const partyBBalanceBeforeSettlementInit = await context.viewFacet.getIsolatedBalance(partyB2.address, await context.collateral.getAddress())
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))

			const closePrice = e(10)
			const closeQuantity = e(50)
			const tradeID = await context.viewFacet.getLastTradeId()
			await partyA2.sendCloseIntent(tradeID, closeQuantity, closePrice, (await getLatestBlockTime()) + 120)

			const closeIntentId = await context.viewFacet.getLastCloseIntentId()
			const closeIntent = await context.viewFacet.getCloseIntent(closeIntentId)

			const partyAFeeBalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateralNL.getAddress())

			await partyB2.fillCloseIntent(closeIntentId, closeIntent.quantity, closeIntent.price)
			const closePNL = (BigInt(closeIntent.price) * BigInt(closeIntent.quantity)) / BigInt(1e18)

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 180,
				symbolId: 1, // put option
				settlementPrice: e(100),
				settlementTimestamp: timestamp,
				collateralPrice: e(10),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			const openAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			let tradePremium = await context.viewFacet.getTradePremium(tradeID)
			const trade: TradeStruct = await context.viewFacet.getTrade(tradeID)

			let newBlock = Number(trade.tradeAgreements.expirationTimestamp) + 12
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			let tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)

			const pnl = await context.viewFacet.getTradePnl(tradeID, priceSig.settlementPrice, openAmount)

			const exerciseFee = await context.viewFacet.getTradeExerciseFee(tradeID, priceSig.settlementPrice, pnl)
			const openFee = await context.viewFacet.getOpenIntentPlatformFee(openIntentId)
			const platformClosedFee = await context.viewFacet.getCloseIntentPlatformFee(closeIntentId, closeQuantity, closePrice)
			const openAffiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(openIntentId)
			const affiliateClosedFee = await context.viewFacet.getCloseIntentAffiliateFee(closeIntentId, closeQuantity, closePrice)
			const openIntent = await context.viewFacet.getOpenIntent(openIntentId)
			const openSolverFee = (openIntent.feeStructure.solverFee.openFee * openIntent.tradeAgreements.quantity * openIntent.price) / e(1) / e(1)
			const solverClosedFee = (closeIntent.feeStructure.solverFee.closeFee * closePrice * closeQuantity) / e(1) / e(1)

			const allClosedFees = platformClosedFee + affiliateClosedFee + solverClosedFee

			const optionSymbol = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			const partyABalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress())
			const partyABalanceBeforeSettlementLocked = await context.viewFacet.getIsolatedLockedBalance(
				partyA2.address,
				await context.collateral.getAddress(),
			)
			const partyBBalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyB2.address, await context.collateral.getAddress())
			const partyBBalanceBeforeSettlementLocked = await context.viewFacet.getIsolatedLockedBalance(
				partyB2.address,
				await context.collateral.getAddress(),
			)

			//Scheduling info
			const releaseInterval = await context.viewFacet.getReleaseInterval(partyA2.address)
			let scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA2.address, optionSymbol.collateral, partyB2.address)

			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.be.not.reverted

			// instant premium add to partyB balance
			const partyBBalanceAfterSettlement = await context.viewFacet.getIsolatedBalance(partyB2.address, context.collateral)
			console.log("Party A Balance 7", await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()))

			newBlock = (await getLatestBlockTime()) + Number(releaseInterval) * 2
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			await context.accountFacet.syncBalances(context.collateral, partyA2.address, [partyB2.address])

			const partyABalanceAfterSettlementSchedule = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateral)
			const partyAFeeBalanceAfterSettlement = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateralNL)

			console.log("Fee Balance Before Settlement:", partyAFeeBalanceBeforeSettlement)
			console.log("Fee Balance After Settlement:", partyAFeeBalanceAfterSettlement)

			// Party B
			expect(partyBBalanceAfterSettlement - partyBBalanceBeforeSettlement).to.be.equal(tradePremiumSettled - e(pnl.toString()))
			// Party A
			expect(partyABalanceAfterSettlementSchedule - partyABalanceBeforeSettlement).to.be.equal(closePNL)
			expect(partyAFeeBalanceBeforeSettlement - partyAFeeBalanceAfterSettlement).to.be.equal(allClosedFees)
		})

		it("Should be executed with option carried out as 'Isolated Buy' - Party A Fee Balances ", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.001), rate: e(0.1) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.solverFee({ openFee: e(0.0001), closeFee: e(0.0002) })
				.build()

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.0001), closeFee: e(0.0003) }])
			await context.controlFacet.setSymbolsPlatformFees([1], [{ openFee: e(0.0001), closeFee: e(0.0004) }])
			await partyA2.setBalances(context.collateralNL, e(1000), e(500))
			await partyA2.sendOpenIntent(request)

			const openIntentId = await context.viewFacet.getLastOpenIntentId()

			await partyB2.lockOpenIntent(openIntentId)
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))

			const closePrice = e(10)
			const closeQuantity = e(50)
			const tradeID = await context.viewFacet.getLastTradeId()
			await partyA2.sendCloseIntent(tradeID, closeQuantity, closePrice, (await getLatestBlockTime()) + 120)

			const closeIntentId = await context.viewFacet.getLastCloseIntentId()
			const closeIntent = await context.viewFacet.getCloseIntent(closeIntentId)

			await partyB2.fillCloseIntent(closeIntentId, closeIntent.quantity, closeIntent.price)

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 180,
				symbolId: 1, // put option
				settlementPrice: e(80),
				settlementTimestamp: timestamp,
				collateralPrice: e(10),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			const openAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			const tradePremium = await context.viewFacet.getTradePremium(tradeID)
			let trade: TradeStruct = await context.viewFacet.getTrade(tradeID)
			const symbol = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)

			const tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)
			const pnl = await context.viewFacet.getTradePnl(tradeID, priceSig.settlementPrice, openAmount)
			const exerciseFee = await context.viewFacet.getTradeExerciseFee(tradeID, priceSig.settlementPrice, pnl)
			const capFee = (BigInt(trade.tradeAgreements.exerciseFee.cap) * pnl) / parseUnits("1", 18)
			const rateFee = (BigInt(trade.tradeAgreements.exerciseFee.rate) * BigInt(priceSig.settlementPrice) * openAmount) / parseUnits("1", 36)

			console.log("openAmount:\n", openAmount)
			console.log("tradePremium:\n", tradePremium)
			console.log("trade quantity:\n", BigInt(trade.tradeAgreements.quantity))
			console.log("tradePremiumSettled:\n", tradePremiumSettled)
			console.log("Symbol Type:", symbol.optionType == BigInt(OptionType.CALL) ? "CALL" : "PUT")

			console.log("pnl:\n", pnl)
			console.log("exerciseFee:\n", exerciseFee)
			console.log("Cap Fee:\n", capFee)
			console.log("Rate Fee:\n", rateFee)

			const pnlInCollateral = (pnl * parseUnits("1", 18)) / BigInt(priceSig.collateralPrice)
			const platformSettledFee =
				(pnlInCollateral * BigInt(trade.feeStructure.platformFee.closeFee)) / BigInt(trade.feeStructure.tokenPriceInCollateral)
			const affiliateSettledFee =
				(pnlInCollateral * BigInt(trade.feeStructure.affiliateFee.closeFee)) / BigInt(trade.feeStructure.tokenPriceInCollateral)

			const allClosedFees = platformSettledFee + affiliateSettledFee
			console.log("Platform Fee:\n", platformSettledFee)
			console.log("Affiliate Fee:\n", affiliateSettledFee)

			const partyAFeeBalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateralNL.getAddress())

			await moveTime(180)
			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.be.not.reverted

			const partyAFeeBalanceAfterSettlement = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateralNL)

			console.log("Fee Balance Before Settlement:", partyAFeeBalanceBeforeSettlement)
			console.log("Fee Balance After Settlement:", partyAFeeBalanceAfterSettlement)

			expect(partyAFeeBalanceBeforeSettlement - partyAFeeBalanceAfterSettlement).to.be.equal(allClosedFees)
		})

		it("Should be executed with CALL option carried out as 'Isolated Buy' when execution is worthful- Party A Balances", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.003), rate: e(0.0002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.build()

			const timeAfterExpire = 170
			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.1), closeFee: e(0.2) }])
			await partyA2.setBalances(context.collateralNL, e(1000), e(500))

			console.log("Party A Initial Balance:\n", await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()))

			await partyA2.sendOpenIntent(request)
			const openIntentId = await context.viewFacet.getLastOpenIntentId()
			await partyB2.lockOpenIntent(openIntentId)

			console.log(
				"Party A Balance Before Fill: \n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			//Fill Open
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))
			const tradeID = await context.viewFacet.getLastTradeId()

			console.log(
				"Party A Balance After Fill Open: \n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + timeAfterExpire + 100,
				symbolId: 2, // call option
				settlementPrice: e(120),
				settlementTimestamp: timestamp,
				collateralPrice: e(1),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			const openAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			const tradePremium = await context.viewFacet.getTradePremium(tradeID)
			let trade: TradeStruct = await context.viewFacet.getTrade(tradeID)
			const symbol = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			let scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA2.address, symbol.collateral, partyB2.address)

			const tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)
			const pnl = await context.viewFacet.getTradePnl(tradeID, priceSig.settlementPrice, openAmount)
			const exerciseFee = await context.viewFacet.getTradeExerciseFee(tradeID, priceSig.settlementPrice, pnl)
			const capFee = (BigInt(trade.tradeAgreements.exerciseFee.cap) * pnl) / parseUnits("1", 18)
			const rateFee = (BigInt(trade.tradeAgreements.exerciseFee.rate) * BigInt(priceSig.settlementPrice) * openAmount) / parseUnits("1", 36)

			console.log("openAmount:\n", openAmount)
			console.log("tradePremium:\n", tradePremium)
			console.log("trade quantity:\n", BigInt(trade.tradeAgreements.quantity))
			console.log("tradePremiumSettled:\n", tradePremiumSettled)
			console.log("Symbol Type:", symbol.optionType == BigInt(OptionType.CALL) ? "CALL" : "PUT")

			console.log("pnl:\n", pnl)
			console.log("exerciseFee:\n", exerciseFee)
			console.log("Cap Fee:\n", capFee)
			console.log("Rate Fee:\n", rateFee)
			console.log("PNL - FEE:\n", pnl - exerciseFee)
			console.log("PNL - CAP:\n", pnl - capFee)
			console.log("PNL - RATE:\n", pnl - rateFee)

			console.log("Before Settlement")
			console.log("Schedule Release Balance Positions, Transitioning:", scheduleEntry.transitioning)
			console.log("Schedule Release Balance Positions, Scheduled:", scheduleEntry.scheduled)
			console.log("Schedule Release Balance Positions, Interval:", scheduleEntry.releaseInterval)

			const partyABalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress())

			//Execute Trade
			await moveTime(timeAfterExpire)
			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.be.not.reverted

			trade = await context.viewFacet.getTrade(tradeID)
			console.log("Trade Status:", trade.status == TradeStatus.EXERCISED ? "EXERCISED" : trade.status)
			console.log(
				"Party A Balance After Settlement Before Sync:\n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA2.address, symbol.collateral, partyB2.address)
			console.log("After Settlement")
			console.log("Schedule Release Balance Positions, Transitioning:", scheduleEntry.transitioning)
			console.log("Schedule Release Balance Positions, Scheduled:", scheduleEntry.scheduled)
			console.log("Schedule Release Balance Positions, Interval:", scheduleEntry.releaseInterval)

			const releaseInterval = await context.viewFacet.getReleaseInterval(partyA2.address)
			await moveTime(Number(releaseInterval) * 2)
			await context.accountFacet.syncBalances(context.collateral, partyA2.address, [partyB2.address])
			console.log(
				"Party A Balance After Settlement after Sync:\n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			expect(trade.status).to.be.equal(TradeStatus.EXERCISED)
			const partyABalanceAfterSettlementSchedule = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateral)
			expect(partyABalanceAfterSettlementSchedule - partyABalanceBeforeSettlement).to.be.equal(pnl - exerciseFee)
		})

		it("Should be executed with CALL option carried out as 'Isolated Buy' when execution is NOT Worthful-  Party A Balances", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.02), rate: e(0.002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.build()

			const timeAfterExpire = 170
			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.1), closeFee: e(0.2) }])
			await partyA2.setBalances(context.collateralNL, e(1000), e(500))

			console.log("Party A Initial Balance:\n", await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()))

			await partyA2.sendOpenIntent(request)
			const openIntentId = await context.viewFacet.getLastOpenIntentId()
			await partyB2.lockOpenIntent(openIntentId)

			console.log(
				"Party A Balance Before Fill: \n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			//Fill Open
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))
			const tradeID = await context.viewFacet.getLastTradeId()

			console.log(
				"Party A Balance After Fill Open: \n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + timeAfterExpire + 100,
				symbolId: 2, // call option
				settlementPrice: e(80), // means the settlement not worthful!!!
				settlementTimestamp: timestamp,
				collateralPrice: e(1),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			const openAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			const tradePremium = await context.viewFacet.getTradePremium(tradeID)
			let trade: TradeStruct = await context.viewFacet.getTrade(tradeID)
			const symbol = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			const tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)
			const pnl = await context.viewFacet.getTradePnl(tradeID, priceSig.settlementPrice, openAmount)
			const exerciseFee = await context.viewFacet.getTradeExerciseFee(tradeID, priceSig.settlementPrice, pnl)
			const capFee = (BigInt(trade.tradeAgreements.exerciseFee.cap) * pnl) / parseUnits("1", 18)
			const rateFee = (BigInt(trade.tradeAgreements.exerciseFee.rate) * BigInt(priceSig.settlementPrice) * openAmount) / parseUnits("1", 36)

			console.log("openAmount:\n", openAmount)
			console.log("tradePremium:\n", tradePremium)
			console.log("trade quantity:\n", BigInt(trade.tradeAgreements.quantity))
			console.log("tradePremiumSettled:\n", tradePremiumSettled)
			console.log("Symbol Type:", symbol.optionType == BigInt(OptionType.CALL) ? "CALL" : "PUT")

			console.log("pnl:\n", pnl)
			console.log("exerciseFee:\n", exerciseFee)
			console.log("Cap Fee:\n", capFee)
			console.log("Rate Fee:\n", rateFee)
			console.log("PNL - FEE:\n", pnl - exerciseFee)
			console.log("PNL - CAP:\n", pnl - capFee)
			console.log("PNL - RATE:\n", pnl - rateFee)

			const partyABalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress())

			//Execute Trade
			await moveTime(timeAfterExpire)
			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.be.not.reverted

			trade = await context.viewFacet.getTrade(tradeID)
			console.log("Trade Status:", trade.status == TradeStatus.EXPIRED ? "Expired" : trade.status)
			console.log(
				"Party A Balance After Settlement Before Sync:\n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			const releaseInterval = await context.viewFacet.getReleaseInterval(partyA2.address)
			await moveTime(Number(releaseInterval) * 2)
			await context.accountFacet.syncBalances(context.collateral, partyA2.address, [partyB2.address])
			console.log(
				"Party A Balance After Settlement after Sync:\n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			expect(trade.status).to.be.equal(TradeStatus.EXPIRED)
			const partyABalanceAfterSettlementSchedule = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateral)
			expect(partyABalanceAfterSettlementSchedule - partyABalanceBeforeSettlement).to.be.equal(0)
		})

		it("Should be executed with PUT option carried out as 'Isolated Buy' when execution is worthful-  Party A Balances", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1) //PUT
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.build()
			const timeAfterExpire = 150
			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.1), closeFee: e(0.2) }])
			await partyA2.setBalances(context.collateralNL, e(1000), e(500))

			console.log("Party A Initial Balance:\n", await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()))
			console.log(
				"Party A Initial Fee Balance:\n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateralNL.getAddress()),
			)

			await partyA2.sendOpenIntent(request)
			const openIntentId = await context.viewFacet.getLastOpenIntentId()
			await partyB2.lockOpenIntent(openIntentId)

			console.log(
				"Party A Balance Before Fill: \n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)
			console.log(
				"Party A Fee Balance Before Fill: \n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateralNL.getAddress()),
			)
			//Fill Open
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))
			const tradeID = await context.viewFacet.getLastTradeId()

			console.log(
				"Party A Balance After Fill Open: \n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)
			console.log(
				"Party A Fee Balance After Fill Open: \n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateralNL.getAddress()),
			)

			//Send Close
			const closePrice = e(10)
			const closeQuantity = e(50)
			await partyA2.sendCloseIntent(tradeID, closeQuantity, closePrice, (await getLatestBlockTime()) + 120)

			const closeIntentId = await context.viewFacet.getLastCloseIntentId()
			const closeIntent = await context.viewFacet.getCloseIntent(closeIntentId)
			await partyB2.fillCloseIntent(closeIntentId, closeIntent.quantity, closeIntent.price)

			console.log(
				"Party A Balance After Fill Close: \n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)
			console.log(
				"Party A Fee Balance After Fill Close: \n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateralNL.getAddress()),
			)

			const closePNL = (BigInt(closeIntent.price) * BigInt(closeIntent.quantity)) / BigInt(1e18)

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + timeAfterExpire + 1500,
				symbolId: 1, // put option
				settlementPrice: e(80),
				settlementTimestamp: timestamp + 200,
				collateralPrice: e(1),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			const openAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			let tradePremium = await context.viewFacet.getTradePremium(tradeID)
			const trade: TradeStruct = await context.viewFacet.getTrade(tradeID)
			let tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)

			console.log("openAmount:\n", openAmount)
			console.log("tradePremium:\n", tradePremium)
			console.log("trade quantity:\n", BigInt(trade.tradeAgreements.quantity))
			console.log("tradePremiumSettled:\n", tradePremiumSettled)

			const pnl = await context.viewFacet.getTradePnl(tradeID, priceSig.settlementPrice, openAmount)
			const exerciseFee = await context.viewFacet.getTradeExerciseFee(tradeID, priceSig.settlementPrice, pnl)
			const openFee = await context.viewFacet.getOpenIntentPlatformFee(openIntentId)
			const closedFee = await context.viewFacet.getCloseIntentPlatformFee(closeIntentId, closePrice, closeQuantity)
			const openAffiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(openIntentId)
			const closedAffiliateFee = await context.viewFacet.getCloseIntentAffiliateFee(closeIntentId, closePrice, closeQuantity)
			const openIntent = await context.viewFacet.getOpenIntent(openIntentId)
			const openSolverFee = (openIntent.feeStructure.solverFee.openFee * BigInt(trade.tradeAgreements.quantity) * openIntent.price) / e(1) / e(1)
			const closedSolverFee = (closeIntent.feeStructure.solverFee.closeFee * closePrice * closeQuantity) / e(1) / e(1)
			console.log("pnl:\n", pnl)
			console.log("exerciseFee:\n", exerciseFee)
			console.log("Platform open Fee:\n", openFee)
			console.log("Platform close Fee:\n", closedFee)
			console.log("openAffiliateFee:\n", openAffiliateFee)
			console.log("closedAffiliateFee:\n", closedAffiliateFee)
			console.log("openSolverFee:\n", openSolverFee)
			console.log("closedSolverFee:\n", closedSolverFee)

			const releaseInterval = await context.viewFacet.getReleaseInterval(partyA2.address)
			await moveTime(Number(releaseInterval) * 2)
			await context.accountFacet.syncBalances(context.collateral, partyA2.address, [partyB2.address])

			const partyABalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress())

			//Execute Trade
			await moveTime(Number(timeAfterExpire) + 12)
			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.not.be.reverted

			console.log(
				"Party A Balance After Settlement Before Sync:\n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			await moveTime(Number(releaseInterval) * 3)
			await context.accountFacet.syncBalances(context.collateral, partyA2.address, [partyB2.address])
			console.log(
				"Party A Balance After Settlement after Sync:\n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			const partyABalanceAfterSettlementSchedule = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateral)
			expect(partyABalanceAfterSettlementSchedule - partyABalanceBeforeSettlement).to.be.equal(pnl - exerciseFee)
		})

		it("Should be executed with PUT option carried out as 'Isolated Buy' when execution is worthful- Party B Balances", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1) //PUT
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.build()
			const timeAfterExpire = 150
			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.1), closeFee: e(0.2) }])
			await partyA2.setBalances(context.collateralNL, e(1000), e(500))

			await partyA2.sendOpenIntent(request)
			const openIntentId = await context.viewFacet.getLastOpenIntentId()
			await partyB2.lockOpenIntent(openIntentId)
			const intentPremium = await context.viewFacet.getOpenIntentPremium(openIntentId)
			const partyBBalanceBeforeSettlementInit = await context.viewFacet.getIsolatedBalance(partyB2.address, await context.collateral.getAddress())

			//Fill Open
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))
			const tradeID = await context.viewFacet.getLastTradeId()

			//Send Close
			const closePrice = e(10)
			const closeQuantity = e(50)
			await partyA2.sendCloseIntent(tradeID, closeQuantity, closePrice, (await getLatestBlockTime()) + 120)

			const closeIntentId = await context.viewFacet.getLastCloseIntentId()
			const closeIntent = await context.viewFacet.getCloseIntent(closeIntentId)
			await partyB2.fillCloseIntent(closeIntentId, closeIntent.quantity, closeIntent.price)

			const closePNL = (BigInt(closeIntent.price) * BigInt(closeIntent.quantity)) / BigInt(1e18)

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + timeAfterExpire + 1500,
				symbolId: 1, // put option
				settlementPrice: e(80),
				settlementTimestamp: timestamp + 200,
				collateralPrice: e(1),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			const openAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			let tradePremium = await context.viewFacet.getTradePremium(tradeID)
			const trade: TradeStruct = await context.viewFacet.getTrade(tradeID)
			let tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)

			console.log("trade quantity:\n", BigInt(trade.tradeAgreements.quantity))
			console.log("openAmount:\n", openAmount)
			console.log("tradePremium:\n", tradePremium)
			console.log("tradePremiumSettled:\n", tradePremiumSettled)

			const pnl = await context.viewFacet.getTradePnl(tradeID, priceSig.settlementPrice, openAmount)
			const exerciseFee = await context.viewFacet.getTradeExerciseFee(tradeID, priceSig.settlementPrice, pnl)
			const openFee = await context.viewFacet.getOpenIntentPlatformFee(openIntentId)
			const closedFee = await context.viewFacet.getCloseIntentPlatformFee(closeIntentId, closePrice, closeQuantity)
			const openAffiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(openIntentId)
			const closedAffiliateFee = await context.viewFacet.getCloseIntentAffiliateFee(closeIntentId, closePrice, closeQuantity)
			const openIntent = await context.viewFacet.getOpenIntent(openIntentId)
			const openSolverFee = (openIntent.feeStructure.solverFee.openFee * BigInt(trade.tradeAgreements.quantity) * openIntent.price) / e(1) / e(1)
			const closedSolverFee = (closeIntent.feeStructure.solverFee.closeFee * closePrice * closeQuantity) / e(1) / e(1)
			console.log("pnl:\n", pnl)
			console.log("exerciseFee:\n", exerciseFee)
			console.log("Platform open Fee:\n", openFee)
			console.log("Platform close Fee:\n", closedFee)
			console.log("openAffiliateFee:\n", openAffiliateFee)
			console.log("closedAffiliateFee:\n", closedAffiliateFee)
			console.log("openSolverFee:\n", openSolverFee)
			console.log("closedSolverFee:\n", closedSolverFee)

			const partyBBalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyB2.address, await context.collateral.getAddress())

			//Execute Trade
			await moveTime(Number(timeAfterExpire) + 12)
			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.not.be.reverted

			console.log(
				"Party B Balance After Settlement:\n",
				await context.viewFacet.getIsolatedBalance(partyB2.address, await context.collateral.getAddress()),
			)

			const partyBBalanceAfterSettlement = await context.viewFacet.getIsolatedBalance(partyB2.address, context.collateral)
			expect(partyBBalanceAfterSettlement - partyBBalanceBeforeSettlement).to.be.equal(tradePremiumSettled + exerciseFee - pnl)
		})

		it("Should be executed with PUT option carried out as 'Isolated Buy' when execution is NOT worthful- Party B Balances", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1) //PUT
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.build()
			const timeAfterExpire = 150
			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.1), closeFee: e(0.2) }])
			await partyA2.setBalances(context.collateralNL, e(1000), e(500))

			await partyA2.sendOpenIntent(request)
			const openIntentId = await context.viewFacet.getLastOpenIntentId()
			await partyB2.lockOpenIntent(openIntentId)
			const intentPremium = await context.viewFacet.getOpenIntentPremium(openIntentId)
			const partyBBalanceBeforeSettlementInit = await context.viewFacet.getIsolatedBalance(partyB2.address, await context.collateral.getAddress())

			//Fill Open
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))
			const tradeID = await context.viewFacet.getLastTradeId()

			//Send Close
			const closePrice = e(10)
			const closeQuantity = e(50)
			await partyA2.sendCloseIntent(tradeID, closeQuantity, closePrice, (await getLatestBlockTime()) + 120)

			const closeIntentId = await context.viewFacet.getLastCloseIntentId()
			const closeIntent = await context.viewFacet.getCloseIntent(closeIntentId)
			await partyB2.fillCloseIntent(closeIntentId, closeIntent.quantity, closeIntent.price)

			const closePNL = (BigInt(closeIntent.price) * BigInt(closeIntent.quantity)) / BigInt(1e18)

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + timeAfterExpire + 1500,
				symbolId: 1, // put option
				settlementPrice: e(120),
				settlementTimestamp: timestamp + 200,
				collateralPrice: e(1),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			const openAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			let tradePremium = await context.viewFacet.getTradePremium(tradeID)
			const trade: TradeStruct = await context.viewFacet.getTrade(tradeID)
			let tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)

			console.log("trade quantity:\n", BigInt(trade.tradeAgreements.quantity))
			console.log("openAmount:\n", openAmount)
			console.log("tradePremium:\n", tradePremium)
			console.log("tradePremiumSettled:\n", tradePremiumSettled)

			const pnl = await context.viewFacet.getTradePnl(tradeID, priceSig.settlementPrice, openAmount)
			const exerciseFee = await context.viewFacet.getTradeExerciseFee(tradeID, priceSig.settlementPrice, pnl)
			const openFee = await context.viewFacet.getOpenIntentPlatformFee(openIntentId)
			const closedFee = await context.viewFacet.getCloseIntentPlatformFee(closeIntentId, closePrice, closeQuantity)
			const openAffiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(openIntentId)
			const closedAffiliateFee = await context.viewFacet.getCloseIntentAffiliateFee(closeIntentId, closePrice, closeQuantity)
			const openIntent = await context.viewFacet.getOpenIntent(openIntentId)
			const openSolverFee = (openIntent.feeStructure.solverFee.openFee * BigInt(trade.tradeAgreements.quantity) * openIntent.price) / e(1) / e(1)
			const closedSolverFee = (closeIntent.feeStructure.solverFee.closeFee * closePrice * closeQuantity) / e(1) / e(1)
			console.log("pnl:\n", pnl)
			console.log("exerciseFee:\n", exerciseFee)
			console.log("Platform open Fee:\n", openFee)
			console.log("Platform close Fee:\n", closedFee)
			console.log("openAffiliateFee:\n", openAffiliateFee)
			console.log("closedAffiliateFee:\n", closedAffiliateFee)
			console.log("openSolverFee:\n", openSolverFee)
			console.log("closedSolverFee:\n", closedSolverFee)

			const partyBBalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyB2.address, await context.collateral.getAddress())

			//Execute Trade
			await moveTime(Number(timeAfterExpire) + 12)
			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.not.be.reverted

			console.log(
				"Party B Balance After Settlement:\n",
				await context.viewFacet.getIsolatedBalance(partyB2.address, await context.collateral.getAddress()),
			)

			const partyBBalanceAfterSettlement = await context.viewFacet.getIsolatedBalance(partyB2.address, context.collateral)
			expect(partyBBalanceAfterSettlement - partyBBalanceBeforeSettlement).to.be.equal(tradePremiumSettled)
		})

		it("Should be executed with PUT option carried out as 'Isolated Buy' when execution is NOT Worthful- Party A Balances", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.02), rate: e(0.002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.build()

			const timeAfterExpire = 170
			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.1), closeFee: e(0.2) }])
			await partyA2.setBalances(context.collateralNL, e(1000), e(500))

			console.log("Party A Initial Balance:\n", await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()))

			await partyA2.sendOpenIntent(request)
			const openIntentId = await context.viewFacet.getLastOpenIntentId()
			await partyB2.lockOpenIntent(openIntentId)

			console.log(
				"Party A Balance Before Fill: \n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			//Fill Open
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))
			const tradeID = await context.viewFacet.getLastTradeId()

			console.log(
				"Party A Balance After Fill Open: \n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + timeAfterExpire + 100,
				symbolId: 1, // put option
				settlementPrice: e(110), // means the settlement not worthful!!!
				settlementTimestamp: timestamp,
				collateralPrice: e(1),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			const openAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			const tradePremium = await context.viewFacet.getTradePremium(tradeID)
			let trade: TradeStruct = await context.viewFacet.getTrade(tradeID)
			const symbol = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			const tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)
			const pnl = await context.viewFacet.getTradePnl(tradeID, priceSig.settlementPrice, openAmount)
			const exerciseFee = await context.viewFacet.getTradeExerciseFee(tradeID, priceSig.settlementPrice, pnl)
			const capFee = (BigInt(trade.tradeAgreements.exerciseFee.cap) * pnl) / parseUnits("1", 18)
			const rateFee = (BigInt(trade.tradeAgreements.exerciseFee.rate) * BigInt(priceSig.settlementPrice) * openAmount) / parseUnits("1", 36)

			console.log("openAmount:\n", openAmount)
			console.log("tradePremium:\n", tradePremium)
			console.log("trade quantity:\n", BigInt(trade.tradeAgreements.quantity))
			console.log("tradePremiumSettled:\n", tradePremiumSettled)
			console.log("Symbol Type:", symbol.optionType == BigInt(OptionType.CALL) ? "CALL" : "PUT")

			console.log("pnl:\n", pnl)
			console.log("exerciseFee:\n", exerciseFee)
			console.log("Cap Fee:\n", capFee)
			console.log("Rate Fee:\n", rateFee)
			console.log("PNL - FEE:\n", pnl - exerciseFee)
			console.log("PNL - CAP:\n", pnl - capFee)
			console.log("PNL - RATE:\n", pnl - rateFee)

			const partyABalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress())

			//Execute Trade
			await moveTime(timeAfterExpire)
			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.be.not.reverted

			trade = await context.viewFacet.getTrade(tradeID)
			console.log("Trade Status:", trade.status == TradeStatus.EXPIRED ? "Expired" : trade.status)
			console.log(
				"Party A Balance After Settlement Before Sync:\n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			const releaseInterval = await context.viewFacet.getReleaseInterval(partyA2.address)
			await moveTime(Number(releaseInterval) * 2)
			await context.accountFacet.syncBalances(context.collateral, partyA2.address, [partyB2.address])
			console.log(
				"Party A Balance After Settlement after Sync:\n",
				await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress()),
			)

			expect(trade.status).to.be.equal(TradeStatus.EXPIRED)
			const partyABalanceAfterSettlementSchedule = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateral)
			expect(partyABalanceAfterSettlementSchedule - partyABalanceBeforeSettlement).to.be.equal(0)
		})

		it("Should be executed when executed with option carried out as 'Cross Buy'- Party A Balance ", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.003), rate: e(0.0002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.BUY)
				.build()

			const timeAfterExpire = 170
			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.1), closeFee: e(0.2) }])
			await partyA2.setBalances(context.collateralNL, e(1000), e(500))

			console.log(
				"Party A Initial Balance:\n",
				await context.viewFacet.getCrossBalance(partyA2.address, await context.collateral.getAddress(), partyB2.address),
			)

			await partyA2.sendOpenIntent(request)
			const openIntentId = await context.viewFacet.getLastOpenIntentId()
			await partyB2.lockOpenIntent(openIntentId)

			console.log(
				"Party A Balance Before Fill: \n",
				await context.viewFacet.getCrossBalance(partyA2.address, await context.collateral.getAddress(), partyB2.address),
			)

			//Fill Open
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))
			const tradeID = await context.viewFacet.getLastTradeId()

			console.log(
				"Party A Balance After Fill Open: \n",
				await context.viewFacet.getCrossBalance(partyA2.address, await context.collateral.getAddress(), partyB2.address),
			)

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + timeAfterExpire + 100,
				symbolId: 2, // call option
				settlementPrice: e(120),
				settlementTimestamp: timestamp,
				collateralPrice: e(1),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			const openAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			const tradePremium = await context.viewFacet.getTradePremium(tradeID)
			let trade: TradeStruct = await context.viewFacet.getTrade(tradeID)
			const symbol = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			let scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA2.address, symbol.collateral, partyB2.address)

			const tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)
			const pnl = await context.viewFacet.getTradePnl(tradeID, priceSig.settlementPrice, openAmount)
			const exerciseFee = await context.viewFacet.getTradeExerciseFee(tradeID, priceSig.settlementPrice, pnl)
			const capFee = (BigInt(trade.tradeAgreements.exerciseFee.cap) * pnl) / parseUnits("1", 18)
			const rateFee = (BigInt(trade.tradeAgreements.exerciseFee.rate) * BigInt(priceSig.settlementPrice) * openAmount) / parseUnits("1", 36)

			console.log("openAmount:\n", openAmount)
			console.log("tradePremium:\n", tradePremium)
			console.log("trade quantity:\n", BigInt(trade.tradeAgreements.quantity))
			console.log("tradePremiumSettled:\n", tradePremiumSettled)
			console.log("Symbol Type:", symbol.optionType == BigInt(OptionType.CALL) ? "CALL" : "PUT")

			console.log("pnl:\n", pnl)
			console.log("exerciseFee:\n", exerciseFee)
			console.log("Cap Fee:\n", capFee)
			console.log("Rate Fee:\n", rateFee)
			console.log("PNL - FEE:\n", pnl - exerciseFee)
			console.log("PNL - CAP:\n", pnl - capFee)
			console.log("PNL - RATE:\n", pnl - rateFee)

			console.log("Before Settlement")
			console.log("Schedule Release Balance Positions, Transitioning:", scheduleEntry.transitioning)
			console.log("Schedule Release Balance Positions, Scheduled:", scheduleEntry.scheduled)
			console.log("Schedule Release Balance Positions, Interval:", scheduleEntry.releaseInterval)

			const partyABalanceBeforeSettlement = await context.viewFacet.getCrossBalance(
				partyA2.address,
				await context.collateral.getAddress(),
				partyB2.address,
			)

			//Execute Trade
			await moveTime(timeAfterExpire)
			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.be.not.reverted

			trade = await context.viewFacet.getTrade(tradeID)
			console.log("Trade Status:", trade.status == TradeStatus.EXERCISED ? "EXERCISED" : trade.status)
			console.log(
				"Party A Balance After Settlement Before Sync:\n",
				await context.viewFacet.getCrossBalance(partyA2.address, await context.collateral.getAddress(), partyB2.address),
			)

			scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA2.address, symbol.collateral, partyB2.address)
			console.log("After Settlement")
			console.log("Schedule Release Balance Positions, Transitioning:", scheduleEntry.transitioning)
			console.log("Schedule Release Balance Positions, Scheduled:", scheduleEntry.scheduled)
			console.log("Schedule Release Balance Positions, Interval:", scheduleEntry.releaseInterval)

			const releaseInterval = await context.viewFacet.getReleaseInterval(partyA2.address)
			await moveTime(Number(releaseInterval) * 2)
			await context.accountFacet.syncBalances(context.collateral, partyA2.address, [partyB2.address])
			console.log(
				"Party A Balance After Settlement after Sync:\n",
				await context.viewFacet.getCrossBalance(partyA2.address, await context.collateral.getAddress(), partyB2.address),
			)

			expect(trade.status).to.be.equal(TradeStatus.EXERCISED)
			const partyABalanceAfterSettlementSchedule = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			expect(partyABalanceAfterSettlementSchedule.balance - partyABalanceBeforeSettlement.balance).to.be.equal(pnl - exerciseFee)
		})

		it("Should be executed when executed with option carried out as 'Cross Buy'- Party B Balance ", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.003), rate: e(0.0002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.BUY)
				.build()

			const timeAfterExpire = 170
			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.1), closeFee: e(0.2) }])
			await partyA2.setBalances(context.collateralNL, e(1000), e(500))

			await partyA2.sendOpenIntent(request)
			const openIntentId = await context.viewFacet.getLastOpenIntentId()
			await partyB2.lockOpenIntent(openIntentId)

			//Fill Open
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))
			const tradeID = await context.viewFacet.getLastTradeId()

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + timeAfterExpire + 100,
				symbolId: 2, // call option
				settlementPrice: e(120),
				settlementTimestamp: timestamp,
				collateralPrice: e(1),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			const openAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			const tradePremium = await context.viewFacet.getTradePremium(tradeID)
			let trade: TradeStruct = await context.viewFacet.getTrade(tradeID)
			const symbol = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			let scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA2.address, symbol.collateral, partyB2.address)

			const tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)
			const pnl = await context.viewFacet.getTradePnl(tradeID, priceSig.settlementPrice, openAmount)
			const exerciseFee = await context.viewFacet.getTradeExerciseFee(tradeID, priceSig.settlementPrice, pnl)
			const capFee = (BigInt(trade.tradeAgreements.exerciseFee.cap) * pnl) / parseUnits("1", 18)
			const rateFee = (BigInt(trade.tradeAgreements.exerciseFee.rate) * BigInt(priceSig.settlementPrice) * openAmount) / parseUnits("1", 36)

			console.log("openAmount:\n", openAmount)
			console.log("tradePremium:\n", tradePremium)
			console.log("trade quantity:\n", BigInt(trade.tradeAgreements.quantity))
			console.log("tradePremiumSettled:\n", tradePremiumSettled)
			console.log("Symbol Type:", symbol.optionType == BigInt(OptionType.CALL) ? "CALL" : "PUT")

			console.log("pnl:\n", pnl)
			console.log("exerciseFee:\n", exerciseFee)

			const partyBBalanceBeforeSettlement = await context.viewFacet.getCrossBalance(
				partyB2.address,
				await context.collateral.getAddress(),
				partyA2.address,
			)

			//Execute Trade
			await moveTime(timeAfterExpire)
			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.be.not.reverted

			trade = await context.viewFacet.getTrade(tradeID)
			expect(trade.status).to.be.equal(TradeStatus.EXERCISED)

			const partyBBalanceAfterSettlementSchedule = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)
			const balanceDiff = partyBBalanceAfterSettlementSchedule.balance - partyBBalanceBeforeSettlement.balance
			console.log("Balance Diff when PNL in Positive:", balanceDiff)

			expect(balanceDiff).to.be.equal(tradePremiumSettled + exerciseFee - pnl)
		})

		it("Should be executed when executed with option carried out as 'Cross Buy'- Party A Balance ", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.003), rate: e(0.0002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.SELL)
				.build()

			const timeAfterExpire = 170
			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.1), closeFee: e(0.2) }])
			await partyA2.setBalances(context.collateralNL, e(1000), e(500))

			console.log(
				"Party A Initial Balance:\n",
				await context.viewFacet.getCrossBalance(partyA2.address, await context.collateral.getAddress(), partyB2.address),
			)

			await partyA2.sendOpenIntent(request)
			const openIntentId = await context.viewFacet.getLastOpenIntentId()
			await partyB2.lockOpenIntent(openIntentId)

			console.log(
				"Party A Balance Before Fill: \n",
				await context.viewFacet.getCrossBalance(partyA2.address, await context.collateral.getAddress(), partyB2.address),
			)

			//Fill Open
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))
			const tradeID = await context.viewFacet.getLastTradeId()

			console.log(
				"Party A Balance After Fill Open: \n",
				await context.viewFacet.getCrossBalance(partyA2.address, await context.collateral.getAddress(), partyB2.address),
			)

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + timeAfterExpire + 100,
				symbolId: 2, // call option
				settlementPrice: e(120),
				settlementTimestamp: timestamp,
				collateralPrice: e(1),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			const openAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			const tradePremium = await context.viewFacet.getTradePremium(tradeID)
			let trade: TradeStruct = await context.viewFacet.getTrade(tradeID)
			const symbol = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			let scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA2.address, symbol.collateral, partyB2.address)

			const tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)
			const pnl = await context.viewFacet.getTradePnl(tradeID, priceSig.settlementPrice, openAmount)
			const exerciseFee = await context.viewFacet.getTradeExerciseFee(tradeID, priceSig.settlementPrice, pnl)
			const capFee = (BigInt(trade.tradeAgreements.exerciseFee.cap) * pnl) / parseUnits("1", 18)
			const rateFee = (BigInt(trade.tradeAgreements.exerciseFee.rate) * BigInt(priceSig.settlementPrice) * openAmount) / parseUnits("1", 36)

			console.log("openAmount:\n", openAmount)
			console.log("tradePremium:\n", tradePremium)
			console.log("trade quantity:\n", BigInt(trade.tradeAgreements.quantity))
			console.log("tradePremiumSettled:\n", tradePremiumSettled)
			console.log("Symbol Type:", symbol.optionType == BigInt(OptionType.CALL) ? "CALL" : "PUT")

			console.log("pnl:\n", pnl)
			console.log("exerciseFee:\n", exerciseFee)
			console.log("Cap Fee:\n", capFee)
			console.log("Rate Fee:\n", rateFee)
			console.log("PNL - FEE:\n", pnl - exerciseFee)
			console.log("PNL - CAP:\n", pnl - capFee)
			console.log("PNL - RATE:\n", pnl - rateFee)

			console.log("Before Settlement")
			console.log("Schedule Release Balance Positions, Transitioning:", scheduleEntry.transitioning)
			console.log("Schedule Release Balance Positions, Scheduled:", scheduleEntry.scheduled)
			console.log("Schedule Release Balance Positions, Interval:", scheduleEntry.releaseInterval)

			const partyABalanceBeforeSettlement = await context.viewFacet.getCrossBalance(
				partyA2.address,
				await context.collateral.getAddress(),
				partyB2.address,
			)

			//Execute Trade
			await moveTime(timeAfterExpire)
			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.be.not.reverted

			trade = await context.viewFacet.getTrade(tradeID)
			console.log("Trade Status:", trade.status == TradeStatus.EXERCISED ? "EXERCISED" : trade.status)
			console.log(
				"Party A Balance After Settlement Before Sync:\n",
				await context.viewFacet.getCrossBalance(partyA2.address, await context.collateral.getAddress(), partyB2.address),
			)

			scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA2.address, symbol.collateral, partyB2.address)
			console.log("After Settlement")
			console.log("Schedule Release Balance Positions, Transitioning:", scheduleEntry.transitioning)
			console.log("Schedule Release Balance Positions, Scheduled:", scheduleEntry.scheduled)
			console.log("Schedule Release Balance Positions, Interval:", scheduleEntry.releaseInterval)

			const releaseInterval = await context.viewFacet.getReleaseInterval(partyA2.address)
			await moveTime(Number(releaseInterval) * 2)
			await context.accountFacet.syncBalances(context.collateral, partyA2.address, [partyB2.address])
			console.log(
				"Party A Balance After Settlement after Sync:\n",
				await context.viewFacet.getCrossBalance(partyA2.address, await context.collateral.getAddress(), partyB2.address),
			)

			expect(trade.status).to.be.equal(TradeStatus.EXERCISED)

			const partyABalanceAfterSettlementSchedule = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			const balanceDiff = partyABalanceAfterSettlementSchedule.balance - partyABalanceBeforeSettlement.balance

			console.log("Balance Party A in Sell Before Settlement:", partyABalanceBeforeSettlement)
			console.log("Balance Party A in Sell After Settlement:", partyABalanceAfterSettlementSchedule)
			console.log("Balance Diff when PNL in Positive:", balanceDiff)

			expect(balanceDiff).to.be.equal(exerciseFee - pnl)
		})
	})
	describe("Transfer Trade", async function () {
		it("Should Fail to transfer trade because of global pause", async () => {
			await context.controlFacet.pauseGlobal()
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(partyA2.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"GlobalPaused",
			)
		})

		it("Should Fail to transfer trade because of party A pause", async () => {
			await context.controlFacet.pausePartyAActions()
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(partyA2.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"PartyAActionsPaused",
			)
		})

		it("Should Fail to transfer trade because of invalid party", async () => {
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA2.getSigner).transferTrade(partyA2.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"UnauthorizedSender",
			)
		})

		it("Should Fail to transfer trade because of unauthorized party", async () => {
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA2.getSigner).transferTrade(partyA2.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"UnauthorizedSender",
			)

			await expect(context.tradeFacet.connect(partyB2.getSigner).transferTrade(partyA2.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"UnauthorizedSender",
			)

			await expect(context.tradeFacet.connect(partyB1.getSigner).transferTrade(partyA2.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"UnauthorizedSender",
			)
		})

		it("Should Fail to transfer trade because of suspended party", async () => {
			await context.controlFacet.suspendAddress(partyA1.address, true)
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(partyA2.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"UserSuspended",
			)
		})

		it("Should Fail to transfer trade because of suspended receiver", async () => {
			await context.controlFacet.suspendAddress(partyA2.address, true)
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(partyA2.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"UserSuspended",
			)
		})

		it("Should Fail to transfer trade because of zero receiver", async () => {
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(ZeroAddress, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"ZeroAddress",
			)
		})

		it("Should Fail to transfer trade because of Party B receiver", async () => {
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(partyB1.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"ReceiverIsPartyB",
			)

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(partyB2.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"ReceiverIsPartyB",
			)
		})

		it("Should Fail to transfer trade because of invalid state", async () => {
			const tradeId = 1
			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 100,
				symbolId: 1,
				settlementPrice: e(100),
				settlementTimestamp: timestamp,
				collateralPrice: e(10),
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}
			await context.tradeFacet.executeTrades([tradeId], priceSig)

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(partyA2.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"InvalidState",
			)
		})

		it("Should Fail to transfer trade because of cross margin", async () => {
			const request2 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(1), rate: e(1) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.BUY)
				.build()

			await partyA1.sendOpenIntent(request2)
			await partyB1.lockOpenIntent(2)
			await partyB1.fillOpenIntent(2, e(100), e(10))

			const tradeId = 2
			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(partyA2.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"CrossTradeTransferNotAllowed",
			)
		})

		it("Should Fail to transfer trade because of Party B insolvent", async () => {
			const tradeId = 1

			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			await context.clearingHouse
				.connect(context.signers.clearingHouse)
				.flagIsolatedPartyBLiquidation(partyB1.address, context.collateral.getAddress())

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(partyA2.address, tradeId)).to.be.revertedWithCustomError(
				context.tradeFacet,
				"NotSolvent",
			)
		})

		it("Should Fail to transfer trade because of Party B insolvent", async () => {
			const tradeId = 1

			expect(await context.tradeFacet.connect(partyA1.getSigner).transferTrade(partyA2.address, tradeId)).not.to.reverted

			expect((await context.viewFacet.getTrade(tradeId)).partyA).be.equal(partyA2.address)
		})
	})
}
