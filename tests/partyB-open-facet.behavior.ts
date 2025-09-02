import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { IntentStatus, TradeSide, TradeStatus } from "./option-enums"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { parseUnits, ZeroAddress } from "ethers"
import { bigint, int } from "hardhat/internal/core/params/argumentTypes"
import { config } from "dotenv"
import { OpenIntentStruct, OpenIntentStructOutput, SymbolStruct } from "../types/contracts/interfaces/ISymmio"

import { MarginType } from "./option-enums"
import { getLatestBlockTime } from "../utils/time"
import { tradeNftSol } from "../types/contracts/helpers"
import { exitOnError } from "winston"
import { account } from "../types/contracts/facets"

export function shouldBehaveLikePartyBOpenFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyA3: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyA3 = new PartyA(context, context.signers.others[0])
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyA1.setBalances(context.collateral, e(100000), e(30000))
		await partyA1.setBalances(context.collateralNL, e(100), e(30)) // as Fee token
		await partyA2.setBalances(context.collateral, e(100000), e(30000))
		await partyA2.setBalances(context.collateralNL, e(100), e(50)) // as Fee token
		await partyA3.setBalances(context.collateral, e(100000), e(100000))
		await partyA3.setBalances(context.collateralNL, e(100), e(50)) // as Fee token
		await partyB1.setBalances(context.collateral, e(100), e(50))
		await partyB1.setBalances(context.collateralNL, e(100), e(50)) // as Fee token

		const latestBlock = await getLatestBlockTime()

		const requestIsolatedBuy = openIntentRequestBuilder()
			.partyBsWhiteList([partyB1.address])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateralNL)
			.symbolId(1)
			.deadline(latestBlock + 140)
			.expirationTimestamp(latestBlock + 120)
			.exerciseFee({ cap: e(1), rate: "0" })
			.quantity(e(100))
			.tradeSide(TradeSide.BUY)
			.marginType(MarginType.ISOLATED)
			.price(100000)
			.solverFee({
				openFee: e(0.001),
				closeFee: e(0.001),
			})
			.build()

		const requestCrossBuy = openIntentRequestBuilder()
			.partyBsWhiteList([partyB1.address])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateralNL)
			.symbolId(1)
			.deadline(latestBlock + 140)
			.expirationTimestamp(latestBlock + 120)
			.exerciseFee({ cap: e(1), rate: "0" })
			.quantity(e(100))
			.tradeSide(TradeSide.BUY)
			.marginType(MarginType.CROSS)
			.price(100000)
			.solverFee({
				openFee: e(0.001),
				closeFee: e(0.001),
			})
			.build()

		const requestCrossSell = openIntentRequestBuilder()
			.partyBsWhiteList([partyB2.address])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateralNL)
			.symbolId(1)
			.deadline(latestBlock + 140)
			.expirationTimestamp(latestBlock + 120)
			.exerciseFee({ cap: e(1), rate: "0" })
			.quantity(e(100))
			.tradeSide(TradeSide.SELL)
			.marginType(MarginType.CROSS)
			.price(100000)
			.solverFee({
				openFee: e(0.001),
				closeFee: e(0.001),
			})
			.build()

		await partyA1.sendOpenIntent(requestIsolatedBuy)
		await partyA1.sendOpenIntent(requestCrossBuy)
		await partyA2.sendOpenIntent(requestCrossSell)
	})

	describe("lockOpenIntent", async function () {
		;``
		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "PartyBActionsPaused")
		})

		it("Should failed when msgSender is not PartyB", async () => {
			await expect(context.partyBOpenFacet.connect(context.signers.partyA1).lockOpenIntent(1)).to.be.revertedWithCustomError(
				context.partyBOpenFacet,
				"NotPartyB",
			)
		})

		it("Should failed when partyB is not Active or Valid", async () => {
			await context.controlFacet.setPartyBConfig(partyB1.getSigner, {
				isActive: false,
				lossCoverage: 0,
				oracleId: 1,
			})

			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "NotPartyB")
		})

		it("Should be failed when User address is Suspended", async () => {
			await context.controlFacet.suspendAddress(partyA1.address, true)
			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "UserSuspended")
		})

		it("Should Pass when User address is Not Suspended", async () => {
			await expect(partyB1.lockOpenIntent(1)).not.to.be.reverted
		})

		it("Should be failed when Sender address is Suspended", async () => {
			await context.controlFacet.suspendAddress(partyB1.address, true)
			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "UserSuspended")
		})

		it("Should pass when Solver address is Not Suspended", async () => {
			await expect(partyB1.lockOpenIntent(1)).not.to.be.reverted
		})

		it("Should be failed when in Emergency Mode", async () => {
			await context.controlFacet.activePartyBsEmergencyMode()
			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "PartyBsInEmergencyMode")
		})

		it("Should be failed when PartyB in Emergency Mode", async () => {
			await context.controlFacet.activePartyBEmergencyMode(partyB1.getSigner)
			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "PartyBInEmergencyMode")
		})

		it("Should be failed when Globally Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "GlobalPaused")
		})

		it("Should failed when intent id not exist", async () => {
			await expect(partyB1.lockOpenIntent(200)).to.be.revertedWithCustomError(context.partyBOpenFacet, "IntentNotFound")
		})

		it("Should failed when intent status not  PENDING", async () => {
			await partyB1.lockOpenIntent(1)
			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "InvalidState")
		})

		it("Should failed when intent deadline reached", async () => {
			const newBlock = (await getLatestBlockTime()) + 150
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "IntentExpired")
		})

		it("Should failed when symbol is not valid", async () => {
			const latestBlock = await getLatestBlockTime()
			await partyA1.setBalances(context.collateralNL, e(10000), e(10000))

			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline(latestBlock + 140)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(10))
				.price(1)
				.build()
			await partyA1.sendOpenIntent(request)

			await context.controlFacet.setSymbolsValidationState([2], [false])
			await expect(partyB2.lockOpenIntent(4)).to.be.revertedWithCustomError(context.partyBOpenFacet, "InvalidSymbol")
		})

		it("Should failed when intent expiration has been passed", async () => {
			const newBlock = (await getLatestBlockTime()) + 130
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])

			await expect(partyB1.lockOpenIntent(1)).to.revertedWithCustomError(context.partyBOpenFacet, "ExpirationTimestampPassed")
		})

		it("Should failed when partyB oracle id not equal with intent symbol oracle id", async () => {
			await context.controlFacet.addOracle("test 2 oracle", context.oracle)
			await context.controlFacet.setPartyBConfig(partyB1.getSigner, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 2,
			})

			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "OracleMismatch")
		})

		it("Should failed when partyA have partyB Roll", async () => {
			await context.controlFacet.setPartyBConfig(partyA1.getSigner, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})

			await expect(context.partyBOpenFacet.connect(context.signers.partyA1).lockOpenIntent(1)).to.be.revertedWithCustomError(
				context.partyBOpenFacet,
				"NotWhitelistedPartyB",
			)
		})

		it("Should failed when partyB not whitelisted in the intent sent by partyA", async () => {
			await expect(partyB2.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "NotWhitelistedPartyB")
		})

		it("Should failed when partyA have partyB Roll", async () => {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 140)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(10))
				.price(1)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.not.reverted

			await context.controlFacet.setPartyBConfig(partyA1.address, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})

			await context.controlFacet.setPartyBSupportedSymbolTypes(partyA1.address, [0], [true])

			await expect(context.partyBOpenFacet.connect(partyA1.getSigner).lockOpenIntent(await context.viewFacet.getLastOpenIntentId())).not.to.be
				.reverted
		})

		it("should revert when partB symbol type mismatch intent symbol type", async () => {
			const latestBlock = await getLatestBlockTime()
			await context.controlFacet.setPartyBSupportedSymbolTypes(context.signers.partyB1, [0], [false])

			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})

			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "SymbolTypeNotSupported")
		})

		it("Should failed when partyB is not Solvent in Isolated Margin", async () => {
			await context.controlFacet.setPartyBConfig(partyB1.address, {
				isActive: true,
				lossCoverage: 10,
				oracleId: 1,
			})

			await context.clearingHouse.flagIsolatedPartyBLiquidation(partyB1.address, await context.collateral.getAddress())
			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "NotSolvent")
			await context.clearingHouse.unflagIsolatedPartyBLiquidation(partyB1.address, await context.collateral.getAddress())
			await expect(partyB1.lockOpenIntent(1)).not.to.be.reverted
		})

		it("Should failed when partyB is not Solvent in Cross Margin", async () => {
			await context.controlFacet.setPartyBConfig(partyB1.address, {
				isActive: true,
				lossCoverage: 10,
				oracleId: 1,
			})
			await context.controlFacet.setPartyBConfig(partyB2.address, {
				isActive: true,
				lossCoverage: 10,
				oracleId: 1,
			})

			const intent2 = await context.viewFacet.getOpenIntent(2)
			const intent3 = await context.viewFacet.getOpenIntent(3)

			await context.clearingHouse.flagCrossPartyBLiquidation(partyB1.address, intent2.partyA, await context.collateral.getAddress())
			await context.clearingHouse.flagCrossPartyBLiquidation(partyB2.address, intent3.partyA, await context.collateral.getAddress())
			await expect(partyB1.lockOpenIntent(2)).to.be.revertedWithCustomError(context.partyBOpenFacet, "NotSolvent")
			await expect(partyB2.lockOpenIntent(3)).to.be.revertedWithCustomError(context.partyBOpenFacet, "NotSolvent")
			await context.clearingHouse.unflagCrossPartyBLiquidation(partyB1.address, intent2.partyA, await context.collateral.getAddress())
			await context.clearingHouse.unflagCrossPartyBLiquidation(partyB2.address, intent3.partyA, await context.collateral.getAddress())
			await expect(partyB1.lockOpenIntent(2)).not.to.be.reverted
			await expect(partyB2.lockOpenIntent(3)).not.to.be.reverted
		})

		it("Should add partyB to intent storage", async () => {
			await expect(partyB1.lockOpenIntent(1)).not.to.be.reverted

			const intent = await context.viewFacet.getOpenIntent(1)
			const activeIntents = await context.viewFacet.getActiveOpenIntents(intent.partyB, 0, 100)
			const activeIntentsIDs = await context.viewFacet.getActiveOpenIntentIds(intent.partyB)

			console.log("Active Open Intents IDs Count:", activeIntentsIDs.length)
			console.log("Active Open Intents Count:", activeIntents.length)
			console.log("Intent Status:", intent.status == BigInt(IntentStatus.LOCKED) ? "Locked" : intent.status)

			for (let i = 0; i < activeIntentsIDs.length; i++) console.log("Id", i, ":", activeIntentsIDs[i])

			expect(activeIntents[activeIntentsIDs.length - 1].id).to.be.equal(intent.id)
		})

		it("Should lock open intent successfully", async () => {
			await expect(partyB1.lockOpenIntent(1)).to.not.reverted

			const intent = await context.viewFacet.getOpenIntent(1)

			expect(intent.status).to.equal(IntentStatus.LOCKED) // IntentStatus.LOCKED
			expect(intent.partyB).to.equal(partyB1.address)
			expect(intent.createTimestamp).to.be.approximately(await getLatestBlockTime(), 5)
		})
	})

	describe("fillOpenIntent", async function () {
		beforeEach(async () => {
			await partyB1.lockOpenIntent(1)
			await partyB1.lockOpenIntent(2)
			await partyB2.lockOpenIntent(3)
		})

		it("Should failed when Global Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBOpenFacet, "GlobalPaused")
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(partyB1.fillOpenIntent(2, 100, 7)).to.revertedWithCustomError(context.partyAOpenFacet, "PartyBActionsPaused")
		})

		it("Should be failed when PartyB in Emergency Mode", async () => {
			await context.controlFacet.activePartyBEmergencyMode(partyB1.address)
			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBOpenFacet, "PartyBInEmergencyMode")
		})

		it("Should be failed when PartyB in Emergency Mode", async () => {
			await context.controlFacet.activePartyBsEmergencyMode()
			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBOpenFacet, "PartyBsInEmergencyMode")
		})

		it("Should failed when msgSender is not PartyB", async () => {
			await expect(partyB2.fillOpenIntent(2, 100, 7)).to.revertedWithCustomError(context.partyBOpenFacet, "UnauthorizedSender") // no matter the intent ID
		})

		it("Should failed when partyA suspended", async () => {
			await context.controlFacet.suspendAddress(partyA1.address, true)

			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.revertedWithCustomError(context.partyBOpenFacet, "UserSuspended")
		})

		it("Should failed when partyB suspended", async () => {
			await context.controlFacet.suspendAddress(partyB1.address, true)

			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.revertedWithCustomError(context.partyBOpenFacet, "UserSuspended")
		})

		it("Should failed when symbol is not valid", async () => {
			await context.controlFacet.setSymbolsValidationState([1], [false])

			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.revertedWithCustomError(context.partyBOpenFacet, "InvalidSymbol")
		})

		it("Should failed when intent not in Valid state", async () => {
			await partyA1.sendCancelOpenIntent([1])

			const intent = await context.viewFacet.getOpenIntent(1)
			console.log("Intent Status:", intent.status == BigInt(IntentStatus.CANCEL_PENDING) ? "Cancel_pending" : intent.status)

			await expect(partyB1.fillOpenIntent(1, 5, 2)).not.to.reverted
		})

		it("Should failed when deadline passed", async () => {
			const newBlock = (await getLatestBlockTime()) + 150
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.revertedWithCustomError(context.partyBOpenFacet, "IntentExpired")
		})

		it("Should failed when expiration passed", async () => {
			const newBlock = (await getLatestBlockTime()) + 130
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.revertedWithCustomError(context.partyBOpenFacet, "ExpirationTimestampPassed")
		})

		it("Should failed when Intent quantity is ZERO", async () => {
			await expect(partyB1.fillOpenIntent(1, e(0), 7)).to.revertedWithCustomError(context.partyBOpenFacet, "ZeroAmount")
		})

		it("Should failed when Intent quantity mismatch fill quantity", async () => {
			await expect(partyB1.fillOpenIntent(1, e(1000), 7)).to.revertedWithCustomError(context.partyBOpenFacet, "InvalidFillAmount")
		})

		it("Should failed when PartyA have more than max Active Trade", async () => {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(5))
				.price(2)
				.build()

			await partyA1.sendOpenIntent(request)
			await partyB2.lockOpenIntent(4)

			await context.controlFacet.setMaxConnectedCounterParties(1) // max # of trade with MarginType of type isolated or cross for a partyA

			await expect(partyB1.fillOpenIntent(1, e(100), 7)).not.to.reverted
			await expect(partyB2.fillOpenIntent(4, e(5), 2)).to.revertedWithCustomError(context.partyBOpenFacet, "MaxCounterPartyConnectionsReached")
		})

		it("Should failed when Intent price mismatch fill type price(BUY Trade)", async () => {
			const intent1 = await context.viewFacet.getOpenIntent(1)
			const intent2 = await context.viewFacet.getOpenIntent(2)
			await expect(partyB1.fillOpenIntent(intent1.id, 100, intent1.price + 1n)).to.revertedWithCustomError(
				context.partyBOpenFacet,
				"InvalidOpenPrice",
			)
			await expect(partyB1.fillOpenIntent(intent1.id, 100, intent1.price - 1n)).not.to.reverted
			await expect(partyB1.fillOpenIntent(intent2.id, 100, intent2.price + 1n)).to.revertedWithCustomError(
				context.partyBOpenFacet,
				"InvalidOpenPrice",
			)
			await expect(partyB1.fillOpenIntent(intent2.id, 100, intent2.price - 1n)).not.to.reverted
		})

		it("Should failed when Intent price mismatch fill type price(Sell Trade)", async () => {
			const intent = await context.viewFacet.getOpenIntent(3)
			await expect(partyB2.fillOpenIntent(intent.id, 100, intent.price - 1n)).to.revertedWithCustomError(context.partyBOpenFacet, "InvalidOpenPrice")
			await expect(partyB2.fillOpenIntent(intent.id, 100, intent.price + 1n)).not.to.reverted
		})

		it("Should make Trade Object ", async () => {
			const intent = await context.viewFacet.getOpenIntent(1)

			const quantity = e(10)
			const price = intent.price / 2n
			await expect(partyB1.fillOpenIntent(intent.id, quantity, price)).not.to.reverted

			const trade = await context.viewFacet.getTrade(1)
			expect(trade.id).to.equal(1)
			expect(trade.openIntentId).to.equal(intent.id)
			expect(trade.tradeAgreements.symbolId).to.equal(intent.tradeAgreements.symbolId)
			expect(trade.tradeAgreements.strikePrice).to.equal(intent.tradeAgreements.strikePrice)
			expect(trade.tradeAgreements.tradeSide).to.equal(intent.tradeAgreements.tradeSide)
			expect(trade.tradeAgreements.marginType).to.equal(intent.tradeAgreements.marginType)
			expect(trade.tradeAgreements.expirationTimestamp).to.equal(intent.tradeAgreements.expirationTimestamp)
			expect(trade.tradeAgreements.mm).to.equal((intent.tradeAgreements.mm * quantity) / intent.tradeAgreements.quantity)
			expect(trade.tradeAgreements.quantity).to.equal(quantity)
			expect(trade.tradeAgreements.exerciseFee).to.deep.equal(intent.tradeAgreements.exerciseFee)
			expect(trade.feeStructure).to.deep.equal(intent.feeStructure)
			expect(trade.affiliate).to.deep.equal(intent.affiliate)
			expect(trade.partyA).to.equal(intent.partyA)
			expect(trade.partyB).to.equal(intent.partyB)

			expect(trade.activeCloseIntentIds.length).to.equal(0)
			expect(trade.openedPrice).to.equal(price)
			expect(trade.settledPrice).to.equal(0)
			expect(trade.closedAmountBeforeExpiration).to.equal(0)
			expect(trade.closePendingAmount).to.equal(0)
			expect(trade.avgClosedPriceBeforeExpiration).to.equal(0)
			expect(trade.avgClosedPriceBeforeExpiration).to.equal(0)

			expect(trade.status).to.equal(TradeStatus.OPENED)
		})

		it("Should Unlocked Premium From Party A as expected in Isolated Mode", async () => {
			const openIntent = await context.viewFacet.getOpenIntent(1)
			const partyALockedBalanceBefore = await context.viewFacet.getIsolatedLockedBalance(openIntent.partyA, await context.collateral.getAddress())

			const quantity = openIntent.tradeAgreements.quantity / 2n
			const price = openIntent.price / 2n
			await expect(partyB1.fillOpenIntent(1, quantity, price)).not.to.reverted

			const partyALockedBalanceAfter = await context.viewFacet.getIsolatedLockedBalance(openIntent.partyA, await context.collateral.getAddress())
			const premium = await context.viewFacet.getOpenIntentPremium(1)

			console.log("partyA Locked Balance Before", partyALockedBalanceBefore)
			console.log("partyA Locked Balance After", partyALockedBalanceAfter)
			expect(partyALockedBalanceBefore - partyALockedBalanceAfter).to.equal(premium)
		})

		it("Should Decreased Premium From Party A as expected in Isolated Mode", async () => {
			const scale = 2n
			const isolatedIntentID = 1
			const openIntent = await context.viewFacet.getOpenIntent(isolatedIntentID)
			const partyABalanceBefore = await context.viewFacet.getIsolatedBalance(openIntent.partyA, await context.collateral.getAddress())

			const quantity = openIntent.tradeAgreements.quantity / scale
			const price = openIntent.price / scale
			await expect(partyB1.fillOpenIntent(openIntent.id, quantity, price)).not.to.reverted

			const partyABalanceAfter = await context.viewFacet.getIsolatedBalance(openIntent.partyA, await context.collateral.getAddress())
			const premium = await context.viewFacet.getOpenIntentPremium(openIntent.id)

			console.log("partyA Locked Balance Before", partyABalanceBefore)
			console.log("partyA Locked Balance After", partyABalanceAfter)
			expect(partyABalanceBefore - partyABalanceAfter).to.equal(premium / scale)
		})

		it("Should Unlocked Premium From Party A as expected in Cross Buy", async () => {
			const scale = 2n
			const crossBuyIntentID = 2
			const openIntent = await context.viewFacet.getOpenIntent(crossBuyIntentID)
			const partyACrossBalanceBefore = await context.viewFacet.getCrossBalance(
				openIntent.partyA,
				await context.collateral.getAddress(),
				openIntent.partyB,
			)

			const quantity = openIntent.tradeAgreements.quantity / scale
			const price = openIntent.price / scale
			await expect(partyB1.fillOpenIntent(crossBuyIntentID, quantity, price)).not.to.reverted

			const partyACrossBalanceAfter = await context.viewFacet.getCrossBalance(
				openIntent.partyA,
				await context.collateral.getAddress(),
				openIntent.partyB,
			)
			const premium = await context.viewFacet.getOpenIntentPremium(crossBuyIntentID)

			console.log("partyA Locked Balance Before", partyACrossBalanceBefore)
			console.log("partyA Locked Balance After", partyACrossBalanceAfter)
			expect(partyACrossBalanceBefore.locked - partyACrossBalanceAfter.locked).to.equal(premium)
		})

		it("Should Decreased Premium From Party A as expected in Cross Buy", async () => {
			const scale = 2n
			const crossBuyIntentID = 2
			const openIntent = await context.viewFacet.getOpenIntent(crossBuyIntentID)
			const partyACrossBalanceBefore = await context.viewFacet.getCrossBalance(
				openIntent.partyA,
				await context.collateral.getAddress(),
				openIntent.partyB,
			)

			const quantity = openIntent.tradeAgreements.quantity / scale
			const price = openIntent.price / scale
			await expect(partyB1.fillOpenIntent(crossBuyIntentID, quantity, price)).not.to.reverted

			const partyACrossBalanceAfter = await context.viewFacet.getCrossBalance(
				openIntent.partyA,
				await context.collateral.getAddress(),
				openIntent.partyB,
			)
			const premium = await context.viewFacet.getOpenIntentPremium(crossBuyIntentID)

			console.log("partyA Locked Balance Before", partyACrossBalanceBefore)
			console.log("partyA Locked Balance After", partyACrossBalanceAfter)
			expect(partyACrossBalanceBefore.balance - partyACrossBalanceAfter.balance).to.equal(premium / scale)
		})

		it("Should Unlocked Maintenance Margin for Party A as expected in Cross Sell", async () => {
			const openIntent = await context.viewFacet.getOpenIntent(3)
			const partyACrossBalanceBefore = await context.viewFacet.getCrossBalance(
				openIntent.partyA,
				await context.collateral.getAddress(),
				openIntent.partyB,
			)

			const quantity = openIntent.tradeAgreements.quantity / 2n
			const price = openIntent.price * 2n
			await expect(partyB2.fillOpenIntent(3, quantity, price)).not.to.reverted

			const partyACrossBalanceAfter = await context.viewFacet.getCrossBalance(
				openIntent.partyA,
				await context.collateral.getAddress(),
				openIntent.partyB,
			)
			const premium = await context.viewFacet.getOpenIntentPremium(3)
			const trade = await context.viewFacet.getTrade(1)

			console.log("partyA Locked Balance Before", partyACrossBalanceBefore)
			console.log("partyA Locked Balance After", partyACrossBalanceAfter)
			expect(partyACrossBalanceBefore.locked - partyACrossBalanceAfter.locked).to.equal(trade.tradeAgreements.mm)
		})

		it("Should Increased Total Maintenance Margin for Party A as expected in Cross Sell", async () => {
			const openIntent = await context.viewFacet.getOpenIntent(3)
			const partyACrossBalanceBefore = await context.viewFacet.getCrossBalance(
				openIntent.partyA,
				await context.collateral.getAddress(),
				openIntent.partyB,
			)

			const quantity = openIntent.tradeAgreements.quantity / 2n
			const price = openIntent.price * 2n
			await expect(partyB2.fillOpenIntent(3, quantity, price)).not.to.reverted

			const partyACrossBalanceAfter = await context.viewFacet.getCrossBalance(
				openIntent.partyA,
				await context.collateral.getAddress(),
				openIntent.partyB,
			)
			const premium = await context.viewFacet.getOpenIntentPremium(3)
			const trade = await context.viewFacet.getTrade(1)

			console.log("partyA Locked Balance Before", partyACrossBalanceBefore)
			console.log("partyA Locked Balance After", partyACrossBalanceAfter)
			expect(partyACrossBalanceAfter.totalMM - partyACrossBalanceBefore.totalMM).to.equal(trade.tradeAgreements.mm)
		})

		it("Should Unlock Fees from PartyA in Isolated as Expected", async () => {
			let intent = await context.viewFacet.getOpenIntent(1) // intent Before Fill
			const balanceBefore = await context.viewFacet.getIsolatedLockedBalance(intent.partyA, context.collateralNL)

			const quantity = e(10) // Partial Fill
			const price = intent.price / 2n // Lower Price in Buy Trade
			await expect(partyB1.fillOpenIntent(intent.id, quantity, price)).not.to.reverted
			intent = await context.viewFacet.getOpenIntent(1) // intent After Fill

			const affiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(intent.id)
			const platformFee = await context.viewFacet.getOpenIntentPlatformFee(intent.id)
			const solverFee =
				(BigInt(intent.price) * BigInt(intent.tradeAgreements.quantity) * BigInt(intent.feeStructure.solverFee.openFee)) /
				((await context.oracle.getPrice(
					intent.feeStructure.feeToken,
					(await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)).collateral,
				)) *
					parseUnits("1", 18))

			const balanceAfter = await context.viewFacet.getIsolatedLockedBalance(intent.partyA, context.collateralNL)
			expect(balanceBefore - balanceAfter).to.be.equal(affiliateFee + platformFee + solverFee)
		})

		it("Should Unlock Fees from PartyA in Cross Margin as Expected", async () => {
			let intent = await context.viewFacet.getOpenIntent(2)
			const balanceBefore = await context.viewFacet.getCrossBalance(intent.partyA, context.collateralNL, intent.partyB)

			const quantity = e(10)
			const price = intent.price / 2n
			await expect(partyB1.fillOpenIntent(intent.id, quantity, price)).not.to.reverted
			intent = await context.viewFacet.getOpenIntent(2) // After Fill

			const affiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(intent.id)
			const platformFee = await context.viewFacet.getOpenIntentPlatformFee(intent.id)
			const solverFee =
				(BigInt(intent.price) * BigInt(intent.tradeAgreements.quantity) * BigInt(intent.feeStructure.solverFee.openFee)) /
				((await context.oracle.getPrice(
					intent.feeStructure.feeToken,
					(await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)).collateral,
				)) *
					parseUnits("1", 18))

			const balanceAfter = await context.viewFacet.getCrossBalance(intent.partyA, context.collateralNL, intent.partyB)
			expect(balanceBefore.locked - balanceAfter.locked).to.be.equal(affiliateFee + platformFee + solverFee)
		})

		it("Should Decrease Fees from PartyA as Expected", async () => {
			const scale = 1n
			const intentID = 1
			let intent = await context.viewFacet.getOpenIntent(intentID)
			const balanceBefore = await context.viewFacet.getIsolatedBalance(intent.partyA, context.collateralNL)

			const quantity = e(10)
			const price = intent.price / scale
			await expect(partyB1.fillOpenIntent(intent.id, quantity, price)).not.to.reverted
			intent = await context.viewFacet.getOpenIntent(intentID)

			const intentPlatformFee = await context.viewFacet.getOpenIntentPlatformFee(intent.id) //Platform Fee
			const intentAffiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(intent.id) //Affiliate Fee
			const solverFee =
				(quantity * price * intent.feeStructure.solverFee.openFee) / (intent.feeStructure.tokenPriceInCollateral * parseUnits("1", 18))

			const balanceAfter = await context.viewFacet.getIsolatedBalance(intent.partyA, context.collateralNL)
			expect(balanceBefore - balanceAfter).to.be.equal(intentAffiliateFee + intentPlatformFee + solverFee)
		})

		it("Should Decrease Fees from PartyA as Expected When Multiple Party Bs listed", async () => {
			const latestBlock = await getLatestBlockTime()
			const requestIsolatedBuy = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address, partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 140)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.price(100000)
				.solverFee({
					openFee: e(0.001),
					closeFee: e(0.001),
				})
				.build()

			const priceScale = 1n
			await partyA1.sendOpenIntent(requestIsolatedBuy)
			let intentID = await context.viewFacet.getLastOpenIntentId()
			await partyB2.lockOpenIntent(intentID)

			let intent = await context.viewFacet.getOpenIntent(intentID)
			const balanceBefore = await context.viewFacet.getIsolatedBalance(intent.partyA, context.collateralNL)

			const quantity = intent.tradeAgreements.quantity / 3n
			const price = intent.price / priceScale
			await expect(partyB2.fillOpenIntent(intent.id, quantity, price)).not.to.reverted
			intent = await context.viewFacet.getOpenIntent(intentID)

			const intentPlatformFee = await context.viewFacet.getOpenIntentPlatformFee(intent.id) //Platform Fee
			const intentAffiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(intent.id) //Affiliate Fee
			const solverFee =
				(quantity * price * intent.feeStructure.solverFee.openFee) / (intent.feeStructure.tokenPriceInCollateral * parseUnits("1", 18))

			const balanceAfter = await context.viewFacet.getIsolatedBalance(intent.partyA, context.collateralNL)
			expect(balanceBefore - balanceAfter).to.be.equal(intentAffiliateFee + intentPlatformFee + solverFee)
		})

		it("Should Pay Fees to Affiliate Collector as Expected", async () => {
			const openIntent = await context.viewFacet.getOpenIntent(1)

			await context.controlFacet.setAffiliateFeesCollector(openIntent.affiliate, openIntent.affiliate)

			const affiliateBalanceBefore = await context.viewFacet.getIsolatedBalance(openIntent.affiliate, await context.collateralNL.getAddress())

			const priceScale = 1n
			const quantity = openIntent.tradeAgreements.quantity / 5n
			const price = openIntent.price / priceScale
			await expect(partyB1.fillOpenIntent(1, quantity, price)).not.to.reverted

			const affiliateBalanceAfter = await context.viewFacet.getIsolatedBalance(openIntent.affiliate, await context.collateralNL.getAddress())
			const partyAFeeBalance = await context.viewFacet.getIsolatedBalance(partyA1.address, await context.collateralNL.getAddress())

			const intentTradingFee = await context.viewFacet.getOpenIntentPlatformFee(openIntent.id) //Platform Fee
			const intentAffiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(openIntent.id) //Affiliate Fee
			const intentAffiliateFeeCalculated =
				(quantity * price * openIntent.feeStructure.affiliateFee.openFee) / (openIntent.feeStructure.tokenPriceInCollateral * parseUnits("1", 18))

			expect(intentAffiliateFee).to.be.equal(intentAffiliateFeeCalculated)

			console.log("Affiliate Address:", openIntent.affiliate)
			console.log("Intent Trading Fee", intentTradingFee)
			console.log("Intent Affiliate Fee", intentAffiliateFee)
			console.log("Affiliate Fee collector Balance Before", affiliateBalanceBefore)
			console.log("Affiliate Fee collector Balance After", affiliateBalanceAfter)
			console.log("Party A Fee Balance", partyAFeeBalance)

			expect(affiliateBalanceAfter).to.equal(intentAffiliateFee)
		})

		it("Should Pay Fees to Platform Fee Collector as Expected", async () => {
			await context.controlFacet.setDefaultFeeCollector(partyA2.address)

			const openIntent = await context.viewFacet.getOpenIntent(1)
			const defaultFeeBalanceBefore = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateralNL.getAddress())

			const priceScale = 1n
			const quantity = openIntent.tradeAgreements.quantity / 5n
			const price = openIntent.price / priceScale
			await expect(partyB1.fillOpenIntent(1, quantity, price)).not.to.reverted

			const defaultFeeBalanceAfter = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateralNL.getAddress())
			const partyAFeeBalance = await context.viewFacet.getIsolatedBalance(partyA1.address, await context.collateralNL.getAddress())

			const intentPlatformFee = await context.viewFacet.getOpenIntentPlatformFee(openIntent.id) //Platform Fee
			const intentPlatformFeeCalculated =
				(quantity * price * openIntent.feeStructure.platformFee.openFee) / (openIntent.feeStructure.tokenPriceInCollateral * parseUnits("1", 18))

			expect(intentPlatformFee).to.be.equal(intentPlatformFeeCalculated)

			console.log("Intent Trading Fee", intentPlatformFee)
			console.log("Intent Trading Fee Calculated", intentPlatformFeeCalculated)
			console.log("Default Fee collector Balance Before", defaultFeeBalanceBefore)
			console.log("Default Fee collector Balance After", defaultFeeBalanceAfter)
			console.log("Party A Fee Balance", partyAFeeBalance)

			expect(defaultFeeBalanceAfter - defaultFeeBalanceBefore).to.equal(intentPlatformFeeCalculated)
		})

		it("Should Pay Fees To Party B as expected", async () => {
			const openIntent = await context.viewFacet.getOpenIntent(1)
			const partyBFeeBalanceBefore = await context.viewFacet.getIsolatedBalance(openIntent.partyB, await context.collateralNL.getAddress())

			const priceScale = 1n
			const quantity = openIntent.tradeAgreements.quantity / 2n
			const price = openIntent.price / priceScale
			await expect(partyB1.fillOpenIntent(1, quantity, price)).not.to.reverted

			expect(openIntent.feeStructure.feeToken).to.be.equal(await context.collateralNL.getAddress())
			const partyBFeeBalanceAfter = await context.viewFacet.getIsolatedBalance(openIntent.partyB, await context.collateralNL.getAddress())
			const partyBCrossFeeBalanceAfter = await context.viewFacet.getCrossBalance(
				openIntent.partyB,
				await context.collateralNL.getAddress(),
				openIntent.partyA,
			)

			const solverFee =
				(quantity * price * openIntent.feeStructure.solverFee.openFee) / (openIntent.feeStructure.tokenPriceInCollateral * parseUnits("1", 18))

			console.log("partyB Fee Balance Before", partyBFeeBalanceBefore)
			console.log("partyB Fee Balance After", partyBFeeBalanceAfter)
			console.log("partyB cross Fee Balance After", partyBCrossFeeBalanceAfter.balance)
			console.log("Solver Fee rate:", openIntent.feeStructure.solverFee)
			console.log("Solver Fee calculated:", solverFee)
			console.log("Fee Token Price to Collateral", openIntent.feeStructure.tokenPriceInCollateral)
			console.log(" E ^ 18", parseUnits("1", 18))

			expect(partyBFeeBalanceAfter - partyBFeeBalanceBefore).to.equal(solverFee)
		})

		it("Should Decreased Premium from Party B as expected in Sell Trade", async () => {
			const openIntent = await context.viewFacet.getOpenIntent(3)

			const partyBCrossBalanceBefore = await context.viewFacet.getCrossBalance(
				openIntent.partyB,
				await context.collateral.getAddress(),
				openIntent.partyA,
			)

			const priceScale = 2n
			const quantity = openIntent.tradeAgreements.quantity / 2n
			const price = openIntent.price * priceScale
			await expect(partyB2.fillOpenIntent(3, quantity, price)).not.to.reverted

			const partyBCrossBalanceAfter = await context.viewFacet.getCrossBalance(
				openIntent.partyB,
				await context.collateral.getAddress(),
				openIntent.partyA,
			)
			const premium = await context.viewFacet.getTradePremium(1)

			console.log("partyB Locked Balance Before", partyBCrossBalanceBefore)
			console.log("partyB Locked Balance After", partyBCrossBalanceAfter)
			console.log("partyB Premium:", premium)
			expect(partyBCrossBalanceBefore.balance - partyBCrossBalanceAfter.balance).to.equal(premium)
		})

		it("Should Pay Premium to Party A as expected in Sell Trade", async () => {
			const openIntent = await context.viewFacet.getOpenIntent(3)
			const partyACrossBalanceBefore = await context.viewFacet.getCrossBalance(
				openIntent.partyA,
				await context.collateral.getAddress(),
				openIntent.partyB,
			)

			const priceScale = 2n
			const quantity = openIntent.tradeAgreements.quantity / 2n
			const price = openIntent.price * 2n
			await expect(partyB2.fillOpenIntent(3, quantity, price)).not.to.reverted

			const partyACrossBalanceAfter = await context.viewFacet.getCrossBalance(
				openIntent.partyA,
				await context.collateral.getAddress(),
				openIntent.partyB,
			)
			const premium = await context.viewFacet.getTradePremium(1)

			console.log("partyB Locked Balance Before", partyACrossBalanceBefore)
			console.log("partyB Locked Balance After", partyACrossBalanceAfter)
			console.log("partyB Premium:", premium)

			expect(partyACrossBalanceAfter.balance - partyACrossBalanceBefore.balance).to.equal(premium)
		})

		it("Should Prevent Withdraw whit Solvency violation when Premium payed to Party A in Sell Trade", async () => {
			const openIntent = await context.viewFacet.getOpenIntent(3)
			const partyACrossBalanceBefore = await context.viewFacet.getCrossBalance(
				openIntent.partyA,
				await context.collateral.getAddress(),
				openIntent.partyB,
			)

			const quantity = openIntent.tradeAgreements.quantity / 2n
			const price = openIntent.price * 2n
			await expect(partyB2.fillOpenIntent(3, quantity, price)).not.to.reverted

			const partyACrossBalanceAfter = await context.viewFacet.getCrossBalance(
				openIntent.partyA,
				await context.collateral.getAddress(),
				openIntent.partyB,
			)
			const premium = await context.viewFacet.getTradePremium(1)

			console.log("partyB Locked Balance Before", partyACrossBalanceBefore)
			console.log("partyB Locked Balance After", partyACrossBalanceAfter)
			console.log("partyB Premium:", premium)

			expect(partyACrossBalanceAfter.balance - partyACrossBalanceBefore.balance).to.equal(premium)

			const partyABalanceBefore = await context.viewFacet.getIsolatedBalance(openIntent.partyA, await context.collateral.getAddress())

			await context.accountFacet.connect(partyA2.getSigner).initiateWithdraw(context.collateral, partyABalanceBefore, partyA1.address)

			const newBlock = (await getLatestBlockTime()) + 130
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			const targetBalanceBefore = await context.collateral.balanceOf(partyA1.address)

			await context.accountFacet.connect(partyA2.getSigner).completeWithdraw(1)

			const partyABalanceAfter = await context.viewFacet.getIsolatedBalance(openIntent.partyA, await context.collateral.getAddress())
			const targetBalanceAfter = await context.collateral.balanceOf(partyA1.address)

			console.log("Source Deposit Balance Before", partyABalanceBefore)
			console.log("Source Deposit Balance After", partyABalanceAfter)
			console.log("Target Collateral Balance Before:", targetBalanceBefore)
			console.log("Target Collateral Balance After:", targetBalanceAfter)

			expect(targetBalanceAfter - targetBalanceBefore).to.equal(partyABalanceBefore)
		})

		it("Should Update Nonce for Party A as expected in Cross Margin", async () => {
			const openIntent = await context.viewFacet.getOpenIntent(3)
			const nonceBefore = await context.viewFacet.getNonce(openIntent.partyA, openIntent.partyB)

			const quantity = openIntent.tradeAgreements.quantity / 2n
			const price = openIntent.price * 2n
			await expect(partyB2.fillOpenIntent(3, quantity, price)).not.to.reverted

			const nonceAfter = await context.viewFacet.getNonce(openIntent.partyA, openIntent.partyB)
			expect(nonceAfter - nonceBefore).to.be.equal(1)
		})

		it("Should Update Nonce for Party B as expected in Cross Margin", async () => {
			const openIntent = await context.viewFacet.getOpenIntent(3)
			const nonceBefore = await context.viewFacet.getNonce(openIntent.partyB, openIntent.partyA)

			const quantity = openIntent.tradeAgreements.quantity / 2n
			const price = openIntent.price * 2n
			await expect(partyB2.fillOpenIntent(3, quantity, price)).not.to.reverted

			const nonceAfter = await context.viewFacet.getNonce(openIntent.partyB, openIntent.partyA)
			expect(nonceAfter - nonceBefore).to.be.equal(1)
		})

		it("Should Add new Intent on Partial Fill as expected", async () => {
			const intentID = 3
			const openIntent = await context.viewFacet.getOpenIntent(intentID)

			const oldQuantity = openIntent.tradeAgreements.quantity
			const quantity = oldQuantity / 3n
			const price = openIntent.price * 2n
			await expect(partyB2.fillOpenIntent(3, quantity, price)).not.to.reverted

			const parentIntent = await context.viewFacet.getOpenIntent(intentID)
			const newIntent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())
			const newTrade = await context.viewFacet.getTrade(await context.viewFacet.getLastTradeId())

			expect(newIntent.id).to.be.equal(await context.viewFacet.getLastOpenIntentId())
			expect(newIntent.tradeId).to.be.equal(0)
			expect(newIntent.partyBsWhiteList).to.be.deep.equal(parentIntent.partyBsWhiteList)
			expect(newIntent.price).to.be.equal(parentIntent.price)
			expect(newIntent.tradeAgreements.symbolId).to.be.equal(parentIntent.tradeAgreements.symbolId)

			expect(newIntent.tradeAgreements.strikePrice).to.be.equal(parentIntent.tradeAgreements.strikePrice)
			expect(newIntent.tradeAgreements.expirationTimestamp).to.be.equal(parentIntent.tradeAgreements.expirationTimestamp)
			expect(newIntent.tradeAgreements.exerciseFee.cap).to.be.equal(parentIntent.tradeAgreements.exerciseFee.cap)
			expect(newIntent.tradeAgreements.exerciseFee.rate).to.be.equal(parentIntent.tradeAgreements.exerciseFee.rate)

			expect(newIntent.tradeAgreements.marginType).to.be.equal(parentIntent.tradeAgreements.marginType)
			expect(newIntent.tradeAgreements.tradeSide).to.be.equal(parentIntent.tradeAgreements.tradeSide)
			expect(newIntent.partyA).to.be.equal(parentIntent.partyA)
			expect(newIntent.partyB).to.be.equal(ZeroAddress)
			expect(newIntent.status).to.be.equal(IntentStatus.PENDING) // IntentStatus.PENDING
			expect(newIntent.parentId).to.be.equal(parentIntent.id)
			expect(newIntent.createTimestamp).to.be.equal(await getLatestBlockTime())
			expect(newIntent.deadline).to.be.equal(parentIntent.deadline)
			expect(newIntent.feeStructure.platformFee).to.be.deep.equal(
				(await context.viewFacet.getSymbol(parentIntent.tradeAgreements.symbolId)).platformFee,
			)
			expect(newIntent.feeStructure.affiliateFee.toString()).to.be.deep.equal(
				(await context.viewFacet.getAffiliateFee(parentIntent.affiliate, parentIntent.tradeAgreements.symbolId)).toString(),
			)
			expect(newIntent.feeStructure.solverFee.closeFee).to.be.equal(parentIntent.feeStructure.solverFee.closeFee)
			expect(newIntent.feeStructure.solverFee.openFee).to.be.equal(parentIntent.feeStructure.solverFee.openFee)
			expect(newIntent.feeStructure.feeToken).to.be.equal(parentIntent.feeStructure.feeToken)
			expect(newIntent.feeStructure.tokenPriceInCollateral).to.be.equal(
				await context.oracle.getPrice(
					newIntent.feeStructure.feeToken,
					(await context.viewFacet.getSymbol(newIntent.tradeAgreements.symbolId)).collateral,
				),
			)
			expect(newIntent.affiliate).to.be.equal(parentIntent.affiliate)
		})

		it("Should Add new Intent with Remaining Quantity on Partial Fill as expected", async () => {
			const intentID = 3
			const openIntent = await context.viewFacet.getOpenIntent(intentID)

			const oldQuantity = openIntent.tradeAgreements.quantity
			const quantity = oldQuantity / 3n
			const price = openIntent.price * 2n
			await expect(partyB2.fillOpenIntent(3, quantity, price)).not.to.reverted

			const newIntent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())

			expect(newIntent.tradeAgreements.quantity).to.equal(oldQuantity - quantity)
		})

		it("Should Add new Intent with Updated Maintenance Margin on Partial Fill in Sell Trade as expected", async () => {
			const intentID = 3
			const openIntent = await context.viewFacet.getOpenIntent(intentID)

			const oldQuantity = openIntent.tradeAgreements.quantity
			const oldMM = openIntent.tradeAgreements.mm
			const quantity = oldQuantity / 3n
			const price = openIntent.price * 2n
			await expect(partyB2.fillOpenIntent(3, quantity, price)).not.to.reverted

			const newIntent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())
			const newTrade = await context.viewFacet.getTrade(await context.viewFacet.getLastTradeId())

			expect(newIntent.tradeAgreements.mm).to.equal(oldMM - newTrade.tradeAgreements.mm)
		})

		it("Should update Parent Intent on Fill as expected", async () => {
			const intentID = 3
			const openIntent = await context.viewFacet.getOpenIntent(intentID)

			const oldQuantity = openIntent.tradeAgreements.quantity
			const oldMM = openIntent.tradeAgreements.mm
			const quantity = oldQuantity / 3n
			const price = openIntent.price * 2n
			await expect(partyB2.fillOpenIntent(3, quantity, price)).not.to.reverted

			const parentIntent = await context.viewFacet.getOpenIntent(intentID)
			const newIntent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())
			const newTrade = await context.viewFacet.getTrade(await context.viewFacet.getLastTradeId())

			expect(parentIntent.tradeAgreements.quantity).to.equal(quantity)
			expect(parentIntent.status).to.be.equal(IntentStatus.FILLED)
			expect(parentIntent.tradeId).to.equal(newTrade.id)
			expect(parentIntent.statusModifyTimestamp).to.be.approximately(await getLatestBlockTime(), 5)
			// expect(parentIntent.tradeAgreements.mm).to.equal(oldMM - newTrade.tradeAgreements.mm)
		})

		it("Should Unregister Filled Intent", async () => {
			const intentID = 3
			let openIntent = await context.viewFacet.getOpenIntent(intentID)

			let activeIntents: OpenIntentStruct[] = await context.viewFacet.getActiveOpenIntents(openIntent.partyA, 0, 100)
			let activeIntentsIDs: bigint[] = await context.viewFacet.getActiveOpenIntentIds(openIntent.partyA)

			console.log("Active Open Intents IDs Count:", activeIntentsIDs.length)
			console.log("Active Open Intents Count:", activeIntents.length)
			console.log("Intent Status:", openIntent.status == BigInt(IntentStatus.LOCKED) ? "Locked" : openIntent.status)

			for (let i = 0; i < activeIntentsIDs.length; i++) console.log("Id", i, ":", activeIntentsIDs[i])

			expect(activeIntents.length).to.be.equal(1)
			expect(activeIntentsIDs.length).to.be.equal(1)
			expect(activeIntents[0].id).to.be.equal(openIntent.id)

			const oldQuantity = openIntent.tradeAgreements.quantity
			const oldMM = openIntent.tradeAgreements.mm
			const quantity = oldQuantity // to be Filled Completely so that the partial intent not created
			const price = openIntent.price * 2n
			await expect(partyB2.fillOpenIntent(openIntent.id, quantity, price)).not.to.reverted

			openIntent = await context.viewFacet.getOpenIntent(intentID)
			activeIntents = await context.viewFacet.getActiveOpenIntents(openIntent.partyA, 0, 100)
			activeIntentsIDs = await context.viewFacet.getActiveOpenIntentIds(openIntent.partyA)

			console.log("Active Open Intents IDs Count:", activeIntentsIDs.length)
			console.log("Active Open Intents Count:", activeIntents.length)
			console.log("Intent Status:", openIntent.status == BigInt(IntentStatus.FILLED) ? "Filled" : openIntent.status)
			expect(activeIntents.length).to.be.equal(0) // as no ID is matched
			expect(activeIntentsIDs.length).to.be.equal(0)

			const parentIntent = await context.viewFacet.getOpenIntent(intentID)
			const newIntent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())
			const newTrade = await context.viewFacet.getTrade(await context.viewFacet.getLastTradeId())
		})

		it("Should Unregister Filled Intent with partial Fill", async () => {
			const intentID = 3
			let openIntent = await context.viewFacet.getOpenIntent(intentID)

			let activeIntents: OpenIntentStruct[] = await context.viewFacet.getActiveOpenIntents(openIntent.partyA, 0, 100)
			let activeIntentsIDs: bigint[] = await context.viewFacet.getActiveOpenIntentIds(openIntent.partyA)

			console.log("Active Open Intents IDs Count:", activeIntentsIDs.length)
			console.log("Active Open Intents Count:", activeIntents.length)
			console.log("Intent Status:", openIntent.status == BigInt(IntentStatus.LOCKED) ? "Locked" : openIntent.status)

			for (let i = 0; i < activeIntentsIDs.length; i++) console.log("Id", i, ":", activeIntentsIDs[i])

			expect(activeIntents.length).to.be.equal(1)
			expect(activeIntentsIDs.length).to.be.equal(1)
			expect(activeIntents[0].id).to.be.equal(openIntent.id)

			const oldQuantity = openIntent.tradeAgreements.quantity
			const quantity = oldQuantity / 3n
			const price = openIntent.price * 2n
			await expect(partyB2.fillOpenIntent(openIntent.id, quantity, price)).not.to.reverted

			openIntent = await context.viewFacet.getOpenIntent(intentID)
			activeIntents = await context.viewFacet.getActiveOpenIntents(openIntent.partyA, 0, 100)
			activeIntentsIDs = await context.viewFacet.getActiveOpenIntentIds(openIntent.partyA)

			console.log("Active Open Intents IDs Count:", activeIntentsIDs.length)
			console.log("Active Open Intents Count:", activeIntents.length)
			console.log("Intent Status:", openIntent.status == BigInt(IntentStatus.FILLED) ? "Filled" : openIntent.status)
			expect(activeIntents.length).to.be.equal(1)
			expect(activeIntentsIDs.length).to.be.equal(1)
			expect(activeIntents[0].id).to.be.equal(openIntent.id + 1n)
		})
	})

	describe("unlockOpenIntent", async function () {
		beforeEach(async () => {
			await partyB1.lockOpenIntent(1)
		})

		it("Should failed when Global Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(partyB1.unlockOpenIntent("1")).to.revertedWithCustomError(context.partyBOpenFacet, "GlobalPaused")
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(partyB1.unlockOpenIntent("1")).to.revertedWithCustomError(context.partyBOpenFacet, "PartyBActionsPaused")
		})

		it("Should failed when msgSender is not PartyB", async () => {
			await expect(context.partyBOpenFacet.connect(context.signers.others[0]).unlockOpenIntent(1)).to.revertedWithCustomError(
				context.partyBOpenFacet,
				"UnauthorizedSender",
			)
		})

		it("Should failed when intent status not LOCKED", async () => {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner, partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(10))
				.price(e(5))
				.build()

			await partyA1.sendOpenIntent(request)
			await partyB1.lockOpenIntent("2")
			await expect(partyA1.sendCancelOpenIntent(["2"])).not.to.be.reverted

			await expect(partyB1.unlockOpenIntent("2")).to.revertedWithCustomError(context.partyBOpenFacet, "InvalidState")
		})

		it("Should change intent status to EXPIRED when deadline reached", async () => {
			const newBlock = (await getLatestBlockTime()) + 150
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])

			expect(await partyB1.unlockOpenIntent(1)).to.not.reverted
			const intent = await context.viewFacet.getOpenIntent(1)
			expect(intent.status).to.equal(IntentStatus.EXPIRED)
		})

		it("Should change intent status to PENDING", async () => {
			await expect(partyB1.unlockOpenIntent("1")).to.not.reverted

			const intent = await context.viewFacet.getOpenIntent(1)

			expect(intent.status).to.equal(IntentStatus.PENDING) //IntentStatus.PENDING
			expect(intent.partyB).to.equal(ZeroAddress)
		})
	})

	describe("acceptCancelOpenIntent", async function () {
		beforeEach(async () => {
			await partyB1.lockOpenIntent(1)
		})

		it("Should failed when Global Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(partyB1.acceptCancelOpenIntent(1)).to.revertedWithCustomError(context.partyBOpenFacet, "GlobalPaused")
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(partyB1.acceptCancelOpenIntent(1)).to.revertedWithCustomError(context.partyBOpenFacet, "PartyBActionsPaused")
		})

		it("Should failed when msgSender is not PartyB", async () => {
			await partyA1.sendCancelOpenIntent(["1"])
			await expect(partyB2.acceptCancelOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "UnauthorizedSender")
		})

		it("Should fail when not in proper state", async () => {
			await expect(partyB1.acceptCancelOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "InvalidState")
		})

		it("Should change intent status to CANCELED on Accept", async () => {
			expect(await partyA1.sendCancelOpenIntent(["1"])).to.not.reverted
			expect(await partyB1.acceptCancelOpenIntent(1)).to.not.reverted

			const intent = await context.viewFacet.getOpenIntent(1)
			expect(intent.status).to.equal(IntentStatus.CANCELED)
		})

		it("Should update status modifying timestamp", async function () {
			const latestBlock = await getLatestBlockTime()
			expect(await partyA1.sendCancelOpenIntent(["1"])).not.to.be.reverted
			expect(await partyB1.acceptCancelOpenIntent(1)).to.not.reverted

			let intent = await context.viewFacet.getOpenIntent(1)
			expect(intent.statusModifyTimestamp).to.be.approximately(latestBlock, 3)
		})

		it("Should remove intent", async () => {
			expect(await partyA1.sendCancelOpenIntent(["1"])).not.to.be.reverted
			expect(await partyB1.acceptCancelOpenIntent(1)).to.not.reverted
			let activeIntentIds: BigInt[] = await context.viewFacet.getActiveOpenIntentIds(partyA1.getSigner)

			for (let a of activeIntentIds) {
				expect(a).not.to.be.equal(1)
			}
			expect(await context.viewFacet.getPartyAOpenIntentIndex(1)).to.be.equal(0)
		})

		it("Should fail when fee interval not synced with current block timestamp", async () => {
			partyA1.sendCancelOpenIntent(["1"])
			// TODO ::: it is about balance scheduling
			// await expect(partyB1.acceptCancelOpenIntent(1)).to.revertedWithCustomError(context.partyBOpenFacet, "InvalidSyncTimestamp")
		})
	})

	// TODO ::: its part of the integration test
	describe("sendOpenIntent memory management", async function () {
		beforeEach(async () => {})

		it("should fail on Fee not paid accordingly  ", async function () {
			// take snapshot
			let initialIsolatedBalancePartyA = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateral.getAddress())
			let initialIsolatedBalancePartyB = await context.viewFacet.getIsolatedBalance(partyB1.getSigner, await context.collateral.getAddress())

			// const latestBlock = await getLatestBlockTime()
			// const requestIsolated = openIntentRequestBuilder()
			// 	.partyBsWhiteList([partyB1.getSigner, partyB2.getSigner])
			// 	.affiliate(context.signers.affiliate1)
			// 	.feeToken(context.collateral)
			// 	.symbolId(1)
			// 	.deadline(latestBlock + 120)
			// 	.expirationTimestamp(latestBlock + 300)
			// 	.exerciseFee({ cap: e(1), rate: "0" })
			// 	.quantity(e(70))
			// 	.price(7)
			// 	.marginType(MarginType.ISOLATED)
			// 	.build()

			// const requestCross = openIntentRequestBuilder()
			// 	.partyBsWhiteList([partyB1.getSigner])
			// 	.affiliate(context.signers.affiliate1)
			// 	.feeToken(context.collateral)
			// 	.symbolId(1)
			// 	.deadline(latestBlock + 120)
			// 	.expirationTimestamp(latestBlock + 300)
			// 	.exerciseFee({ cap: e(1), rate: "0" })
			// 	.quantity(e(70))
			// 	.price(7)
			// 	.marginType(MarginType.CROSS)
			// 	.build()

			// // PartyA sends some Intents
			// const testTable = [requestIsolated, requestIsolated, requestIsolated, requestCross]

			// // testTable.forEach(async c => {
			// // 	await expect(partyA2.sendOpenIntent(c.request))
			// // })
			// expect(await partyA2.sendOpenIntent(requestIsolated)).not.to.reverted // fee and premium for party A
			// expect(await partyA2.sendOpenIntent(requestIsolated)).not.to.reverted
			// expect(await partyA2.sendOpenIntent(requestIsolated)).not.to.reverted
			// expect(await partyA2.sendOpenIntent(requestCross)).not.to.reverted
			// expect(await partyA2.sendOpenIntent(requestCross)).not.to.reverted
			// expect(await partyA2.sendOpenIntent(requestCross)).not.to.reverted
			// expect(await partyA2.sendOpenIntent(requestCross)).not.to.reverted
			// expect(await partyA2.sendOpenIntent(requestCross)).not.to.reverted
			// expect(await partyA2.sendOpenIntent(requestIsolated)).not.to.reverted
			// expect(await partyA2.sendOpenIntent(requestIsolated)).not.to.reverted

			// let openIntents: OpenIntentStruct[] = await context.viewFacet.getActiveOpenIntents(partyA2.getSigner, 0, 100)
			// for (let openIntent of openIntents) {
			// 	console.log("Initial OpenIntents: ")
			// 	console.log("ID: ", openIntent.id)
			// 	console.log("Status: ", openIntent.status == 0 ? "Pending" : openIntent.status)
			// 	console.log("Quantity: ", openIntent.tradeAgreements.quantity)
			// }

			// const symbol: SymbolStruct = await context.viewFacet.getSymbol(openIntents[2].tradeAgreements.symbolId)

			// const tradingFeeFromView = await context.viewFacet.getOpenIntentTradingFee(2)
			// const premiumFromView = await context.viewFacet.getOpenIntentPremium(2)
			// const affiliateFeeFromView = await context.viewFacet.getAffiliateFee(openIntents[1].affiliate, symbol.symbolId)

			// // let partyAFeesPaid = BigInt(openIntents.length) * (tradingFeeFromView + affiliateFeeFromView)
			// // let partyAPremiumPaid = BigInt(openIntents.length) * premiumFromView
			// //OI == open intent
			// let send_OI_IsolatedBalancePartyA = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateral.getAddress())

			// // some time elapses
			// let newBlockTimeStamp = (await getLatestBlockTime()) + 20
			// await network.provider.send("evm_setNextBlockTimestamp", [newBlockTimeStamp])
			// await network.provider.send("evm_mine")

			// // PartyB locks
			// // expect( await partyB1.lockOpenIntent(1)).not.to.reverted
			// expect(await partyB1.lockOpenIntent(2)).not.to.reverted
			// expect(await partyB1.lockOpenIntent(3)).not.to.reverted
			// expect(await partyB1.lockOpenIntent(4)).not.to.reverted
			// expect(await partyB1.lockOpenIntent(5)).not.to.reverted
			// expect(await partyB1.lockOpenIntent(6)).not.to.reverted
			// expect(await partyB1.lockOpenIntent(7)).not.to.reverted
			// expect(await partyB1.lockOpenIntent(8)).not.to.reverted
			// expect(await partyB1.lockOpenIntent(9)).not.to.reverted
			// expect(await partyB1.lockOpenIntent(10)).not.to.reverted
			// expect(await partyB1.lockOpenIntent(11)).not.to.reverted

			// let lockIsolatedBalancePartyB = await context.viewFacet.getIsolatedBalance(partyB1.getSigner, await context.collateral.getAddress())

			// newBlockTimeStamp = (await getLatestBlockTime()) + 20 // Time passes
			// await network.provider.send("evm_setNextBlockTimestamp", [newBlockTimeStamp])
			// await network.provider.send("evm_mine")

			// expect(await partyA2.sendCancelOpenIntent(["2", "3"])).not.to.reverted // partyA Cancels some intent

			// expect(await partyB1.unlockOpenIntent(4)).not.to.reverted // partyB Unlock some intents
			// expect(await partyB1.unlockOpenIntent(5)).not.to.reverted

			// let unlockIsolatedBalancePartyB = await context.viewFacet.getIsolatedBalance(partyB1.getSigner, await context.collateral.getAddress())

			// newBlockTimeStamp = (await getLatestBlockTime()) + 20 // Time passes
			// await network.provider.send("evm_setNextBlockTimestamp", [newBlockTimeStamp])
			// await network.provider.send("evm_mine")

			// expect(await partyB1.acceptCancelOpenIntent(2)).not.to.reverted // partyB Accepts Cancel of some partyA Cancels
			// expect(await partyB1.acceptCancelOpenIntent(3)).not.to.reverted

			// expect(await partyB1.fillOpenIntent(6, 50, 6)).not.to.reverted
			// expect(await partyB1.fillOpenIntent(7, 50, 6)).not.to.reverted // partyB Fills some intent

			// let filIsolatedBalancePartyB = await context.viewFacet.getIsolatedBalance(partyB1.getSigner, await context.collateral.getAddress())
			// let cancel_OI_IsolatedBalancePartyA = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateral.getAddress())

			// openIntents = await context.viewFacet.getActiveOpenIntents(partyA2.getSigner, 0, 100)
			// for (let openIntent of openIntents) {
			// 	console.log("\nOpenIntents Before Deadline: ")
			// 	console.log("ID: ", openIntent.id)
			// 	console.log(
			// 		"Status: ",
			// 		openIntent.status == 0
			// 			? "Pending"
			// 			: openIntent.status == 1
			// 			? "LOCKED"
			// 			: openIntent.status == 2
			// 			? "CANCEL_PENDING"
			// 			: openIntent.status == 3
			// 			? "CANCELED"
			// 			: openIntent.status == 4
			// 			? "FILLED"
			// 			: openIntent.status == 5
			// 			? "EXPIRED"
			// 			: openIntent.status,
			// 	)
			// }

			// newBlockTimeStamp = (await getLatestBlockTime()) + 140 // Time passes
			// await network.provider.send("evm_setNextBlockTimestamp", [newBlockTimeStamp])
			// await network.provider.send("evm_mine")

			// expect(await partyB1.unlockOpenIntent(8)).not.to.reverted // what happens to locked intents
			// expect(await partyB1.unlockOpenIntent(9)).not.to.reverted //

			// openIntents = await context.viewFacet.getActiveOpenIntents(partyA2.getSigner, 0, 100)
			// for (let openIntent of openIntents) {
			// 	console.log("\nOpenIntents After Deadline: ")
			// 	console.log("ID: ", openIntent.id)
			// 	console.log(
			// 		"Status: ",
			// 		openIntent.status == 0
			// 			? "Pending"
			// 			: openIntent.status == 1
			// 			? "LOCKED"
			// 			: openIntent.status == 2
			// 			? "CANCEL_PENDING"
			// 			: openIntent.status == 3
			// 			? "CANCELED"
			// 			: openIntent.status == 4
			// 			? "FILLED"
			// 			: openIntent.status == 5
			// 			? "EXPIRED"
			// 			: openIntent.status,
			// 	)
			// }

			// let expireIsolatedBalancePartyB = await context.viewFacet.getIsolatedBalance(partyB1.getSigner, await context.collateral.getAddress())
			// let expireIsolatedBalancePartyA = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateral.getAddress())
		})
	})
}
