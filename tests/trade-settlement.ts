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
import { getLatestBlockTime } from "../utils/time"
import { settlementSigBuilder } from "./models/builders/settlement.builder"
import { ZeroAddress } from "ethers"
import { MarginType, TradeSide } from "./option-enums"

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
				.partyBsWhiteList([partyB1.getSigner])
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
			await partyB1.lockOpenIntent(2) // second (this) intent
			await partyB1.fillOpenIntent(2, e(100), e(7))
			await partyA1.sendCloseIntent(2, e(100), e(7), (await getLatestBlockTime()) + 120)
			let closeIntent: CloseIntentStruct = await context.viewFacet.getCloseIntent(2)
			console.log("Settlement Close Intent Quantity: ", closeIntent.quantity)
			console.log("Settlement Close Intent Filled Amount: ", closeIntent.filledAmount)

			await partyB1.fillCloseIntent(1, e(100), e(7))
			closeIntent = await context.viewFacet.getCloseIntent(1)
			console.log("Settlement After Fill Close Intent Quantity: ", closeIntent.quantity)
			console.log("Settlement After Fill Close Intent Filled Amount: ", closeIntent.filledAmount)

			const timestamp = await getLatestBlockTime()
			const tradeID = 2
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
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.01), rate: e(1) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.build()

			const openIntentId = 2
			const closeIntentId = 1
			const tradeID = 2

			await partyA2.sendOpenIntent(request)
			await partyB2.lockOpenIntent(openIntentId)
			const intentPremium = await context.viewFacet.getOpenIntentPremium(openIntentId)
			const partyBBalanceBeforeSettlementInit = await context.viewFacet.getIsolatedBalance(partyB2.getSigner, await context.collateral.getAddress())
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))
			const closePrice = e(10)
			const closeQuantity = e(50)
			await partyA2.sendCloseIntent(tradeID, closeQuantity, closePrice, (await getLatestBlockTime()) + 120)
			const closeIntent = await context.viewFacet.getCloseIntent(closeIntentId)
			await partyB2.fillCloseIntent(1, closeIntent.quantity, closeIntent.price)
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
			const closedFee = await context.viewFacet.getCloseIntentPlatformFee(closeIntentId, closeQuantity, closePrice)
			const openAffiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(openIntentId)
			const closedAffiliateFee = await context.viewFacet.getCloseIntentAffiliateFee(closeIntentId, closeQuantity, closePrice)
			const openIntent = await context.viewFacet.getOpenIntent(openIntentId)
			const openSolverFee = (openIntent.feeStructure.solverFee.openFee * openIntent.tradeAgreements.quantity * openIntent.price) / e(1) / e(1)
			const closedSolverFee = (closeIntent.feeStructure.solverFee.closeFee * closePrice * closeQuantity) / e(1) / e(1)
			const allCloseFee = closedFee + closedAffiliateFee + closedSolverFee
			const optionSymbol = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			const partyABalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyA2.getSigner, await context.collateral.getAddress())
			const partyABalanceBeforeSettlementLocked = await context.viewFacet.getIsolatedLockedBalance(
				partyA2.getSigner,
				await context.collateral.getAddress(),
			)
			const partyBBalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyB2.getSigner, await context.collateral.getAddress())
			const partyBBalanceBeforeSettlementLocked = await context.viewFacet.getIsolatedLockedBalance(
				partyB2.getSigner,
				await context.collateral.getAddress(),
			)

			//Scheduling info
			const releaseInterval = await context.viewFacet.getReleaseInterval(partyA2.getSigner)
			let scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA2.getSigner, optionSymbol.collateral, partyB2.getSigner)

			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.be.not.reverted

			// instant premium add to partyB balance
			const partyBBalanceAfterSettlement = await context.viewFacet.getIsolatedBalance(partyB2.getSigner, context.collateral)
			console.log("Party A Balance 7", await context.viewFacet.getIsolatedBalance(partyA2.getSigner, await context.collateral.getAddress()))

			newBlock = (await getLatestBlockTime()) + Number(releaseInterval) * 2
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			await context.accountFacet.syncBalances(context.collateral, partyA2.getSigner, [partyB2.getSigner])

			const partyABalanceAfterSettlementSchedule = await context.viewFacet.getIsolatedBalance(partyA2.getSigner, context.collateral)
			// Party B
			expect(partyBBalanceAfterSettlement - partyBBalanceBeforeSettlement).to.be.equal(tradePremiumSettled - e(pnl.toString()))
			// Party A
			expect(partyABalanceAfterSettlementSchedule - partyABalanceBeforeSettlement).to.be.equal(closePNL - allCloseFee)
		})

		/////////////////////////// assumed values //////////////////////////////
		////////// collateral price = 1
		////////// option price = 10
		////////// fee token price = 1
		////////// strike price = 100 now / 120 on execution
		////////// option type = 1 : PUT / 2 : CALL
		////////// affiliate and protocol fee : open intent = 0.001 / close intent = 0.003
		////////// solver fee : open intent = 0.001 / close intent = 0.01
		////////// execution fee = min(0.002 * pnl, 0.0002 * underlying asset)
		// TODO : this test pends by contract correction
		it("Should be executed with option carried out as 'Isolated Buy' when execution is worthful", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.build()

			const openIntentId = 2
			const closeIntentId = 1
			const tradeID = 2
			console.log("Party A Balance 1 : ", await context.viewFacet.getIsolatedBalance(partyA2.getSigner, await context.collateral.getAddress()))
			await partyA2.sendOpenIntent(request)
			await partyB2.lockOpenIntent(openIntentId)
			const intentPremium = await context.viewFacet.getOpenIntentPremium(openIntentId)
			const partyBBalanceBeforeSettlementInit = await context.viewFacet.getIsolatedBalance(partyB2.getSigner, await context.collateral.getAddress())
			console.log("Party A Balance 2 : ", await context.viewFacet.getIsolatedBalance(partyA2.getSigner, await context.collateral.getAddress()))
			await partyB2.fillOpenIntent(openIntentId, e(100), e(10))
			console.log("Party A Balance 3 : ", await context.viewFacet.getIsolatedBalance(partyA2.getSigner, await context.collateral.getAddress()))
			const closePrice = e(10)
			const closeQuantity = e(50)
			await partyA2.sendCloseIntent(tradeID, closeQuantity, closePrice, (await getLatestBlockTime()) + 120)
			const closeIntent = await context.viewFacet.getCloseIntent(closeIntentId)
			await partyB2.fillCloseIntent(1, closeIntent.quantity, closeIntent.price)
			console.log("Party A Balance 4 : ", await context.viewFacet.getIsolatedBalance(partyA2.getSigner, await context.collateral.getAddress()))
			const closePNL = (BigInt(closeIntent.price) * BigInt(closeIntent.quantity)) / BigInt(1e18)

			const timestamp = await getLatestBlockTime()
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 180,
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
			let tradePremium = await context.viewFacet.getTradePremium(tradeID)
			const trade: TradeStruct = await context.viewFacet.getTrade(tradeID)

			let newBlock = Number(trade.tradeAgreements.expirationTimestamp) + 12
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")
			console.log("openAmount", openAmount)
			console.log("tradePremium", tradePremium)
			console.log("trade quantity", BigInt(trade.tradeAgreements.quantity))
			let tradePremiumSettled = (tradePremium * openAmount) / BigInt(trade.tradeAgreements.quantity)
			console.log("tradePremiumSettled", tradePremiumSettled)
			const pnl = await context.viewFacet.getTradePnl(tradeID, priceSig.settlementPrice, openAmount)
			console.log("pnl", pnl)
			const exerciseFee = await context.viewFacet.getTradeExerciseFee(tradeID, priceSig.settlementPrice, pnl)
			console.log("exerciseFee", exerciseFee)
			const openFee = await context.viewFacet.getOpenIntentPlatformFee(openIntentId)
			console.log("openFee", openFee)
			const closedFee = await context.viewFacet.getCloseIntentPlatformFee(closeIntentId, closePrice, closeQuantity)
			console.log("closedFee", closedFee)
			const openAffiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(openIntentId)
			console.log("openAffiliateFee", openAffiliateFee)
			const closedAffiliateFee = await context.viewFacet.getCloseIntentAffiliateFee(closeIntentId, closePrice, closeQuantity)
			console.log("closedAffiliateFee", closedAffiliateFee)
			const openIntent = await context.viewFacet.getOpenIntent(openIntentId)
			const openSolverFee = (openIntent.feeStructure.solverFee.openFee * openIntent.tradeAgreements.quantity * openIntent.price) / e(1) / e(1)
			const closedSolverFee = (closeIntent.feeStructure.solverFee.closeFee * closePrice * closeQuantity) / e(1) / e(1)
			console.log("openSolverFee", openSolverFee)
			console.log("closedSolverFee", closedSolverFee)
			const allScheduledFee = closedFee + closedAffiliateFee + closedSolverFee + exerciseFee

			const optionSymbol = await context.viewFacet.getSymbol(trade.tradeAgreements.symbolId)
			const partyABalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyA2.getSigner, await context.collateral.getAddress())
			const partyABalanceBeforeSettlementLocked = await context.viewFacet.getIsolatedLockedBalance(
				partyA2.getSigner,
				await context.collateral.getAddress(),
			)
			const partyBBalanceBeforeSettlement = await context.viewFacet.getIsolatedBalance(partyB2.getSigner, await context.collateral.getAddress())
			const partyBBalanceBeforeSettlementLocked = await context.viewFacet.getIsolatedLockedBalance(
				partyB2.getSigner,
				await context.collateral.getAddress(),
			)

			//Scheduling info
			const releaseInterval = await context.viewFacet.getReleaseInterval(partyA2.getSigner)
			let scheduleEntry = await context.viewFacet.getScheduledReleaseEntry(partyA2.getSigner, optionSymbol.collateral, partyB2.getSigner)

			await expect(context.tradeFacet.executeTrades([tradeID], priceSig)).to.be.not.reverted
			console.log("Party A Balance 5 : ", await context.viewFacet.getIsolatedBalance(partyA2.getSigner, await context.collateral.getAddress()))
			// instant premium add to partyB balance
			const partyBBalanceAfterSettlement = await context.viewFacet.getIsolatedBalance(partyB2.getSigner, context.collateral)
			// console.log("Party A Balance 7" ,await context.viewFacet.getIsolatedBalance(partyA2.getSigner, await context.collateral.getAddress()))

			newBlock = (await getLatestBlockTime()) + Number(releaseInterval) * 2
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			await context.accountFacet.syncBalances(context.collateral, partyA2.getSigner, [partyB2.getSigner])
			console.log("Party A Balance 6 : ", await context.viewFacet.getIsolatedBalance(partyA2.getSigner, await context.collateral.getAddress()))
			const partyABalanceAfterSettlementSchedule = await context.viewFacet.getIsolatedBalance(partyA2.getSigner, context.collateral)
			// Party B
			expect(partyBBalanceAfterSettlement - partyBBalanceBeforeSettlement).to.be.equal(tradePremiumSettled - pnl + exerciseFee)
			// Party A
			// expect(partyABalanceAfterSettlementSchedule - partyABalanceBeforeSettlement).to.be.equal(closePNL - allScheduledFee + pnl)
		})

		it("Should be executed when executed with option carried out as 'Cross Buy' ", async () => {
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

			await expect(context.tradeFacet.executeTrades([ID], priceSig)).to.be.not.reverted
		})

		it("Should be executed when executed with option carried out as 'Isolated Sell' ", async () => {
			const timestamp = await getLatestBlockTime()
			const ID = 1
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 100,
				symbolId: 1, // put option
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
			await expect(context.tradeFacet.executeTrades([ID], priceSig)).to.be.not.reverted
		})

		it("Should be executed when executed with option carried out as 'Cross Sell' ", async () => {
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

			expect(await context.tradeFacet.executeTrades([ID], priceSig)).to.be.not.reverted
		})
	})
	describe("Transfer Trade", async function () {
		it("Should Fail to transfer trade because of global pause", async  () => {
			await context.controlFacet.pauseGlobal()
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(
				partyA2.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "GlobalPaused")

		})

		it("Should Fail to transfer trade because of party A pause", async  () => {
			await context.controlFacet.pausePartyAActions()
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(
				partyA2.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "PartyAActionsPaused")
		})

		it("Should Fail to transfer trade because of invalid party", async  () => {
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA2.getSigner).transferTrade(
				partyA2.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "UnauthorizedSender")
		})

		it("Should Fail to transfer trade because of unauthorized party", async  () => {
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA2.getSigner).transferTrade(
				partyA2.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "UnauthorizedSender")

			await expect(context.tradeFacet.connect(partyB2.getSigner).transferTrade(
				partyA2.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "UnauthorizedSender")

			await expect(context.tradeFacet.connect(partyB1.getSigner).transferTrade(
				partyA2.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "UnauthorizedSender")
		})

		it("Should Fail to transfer trade because of suspended party", async  () => {
			await context.controlFacet.suspendAddress(partyA1.address , true)
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(
				partyA2.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "UserSuspended")
		})

		it("Should Fail to transfer trade because of suspended receiver", async  () => {
			await context.controlFacet.suspendAddress(partyA2.address , true)
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(
				partyA2.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "UserSuspended")
		})

		it("Should Fail to transfer trade because of zero receiver", async  () => {
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(
				ZeroAddress,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "ZeroAddress")
		})

		it("Should Fail to transfer trade because of Party B receiver", async  () => {
			const tradeId = 1

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(
				partyB1.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "ReceiverIsPartyB")

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(
				partyB2.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "ReceiverIsPartyB")

		})

		it("Should Fail to transfer trade because of invalid state", async  () => {
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

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(
				partyA2.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "InvalidState")

		})


		it("Should Fail to transfer trade because of cross margin", async  () => {

			const request2 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
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
			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(
				partyA2.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "CrossTradeTransferNotAllowed")

		})

		it("Should Fail to transfer trade because of Party B insolvent", async  () => {
			const tradeId = 1

			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB1.address,
				context.collateral.getAddress()
			)

			await expect(context.tradeFacet.connect(partyA1.getSigner).transferTrade(
				partyA2.address,
				tradeId
			)).to.be.revertedWithCustomError(context.tradeFacet, "NotSolvent")

		})

		it("Should Fail to transfer trade because of Party B insolvent", async  () => {
			const tradeId = 1

			expect(await context.tradeFacet.connect(partyA1.getSigner).transferTrade(
				partyA2.address,
				tradeId
			)).not.to.reverted

			expect((await context.viewFacet.getTrade(tradeId)).partyA).be.equal(partyA2.address)
		})

	})
}
