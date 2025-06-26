import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { IntentStatus, TradeSide } from "./option-enums"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { ZeroAddress } from "ethers"
import { bigint, int } from "hardhat/internal/core/params/argumentTypes"
import { config } from "dotenv"
import { OpenIntentStruct, OpenIntentStructOutput, SymbolStruct } from "../types/contracts/interfaces/ISymmio"

import { MarginType } from "./option-enums"
import { getLatestBlockTime } from "../utils/time"

export function shouldBehaveLikePartyBOpenFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyA1.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateralNL, e(100000), e(100000)) // as Fee token
		await partyA2.setBalances(context.collateral, e(100000), e(100000))

		const latestBlock = await getLatestBlockTime()
		await partyA1.sendOpenIntent(
			openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 140)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build(),
		)
	})

	describe("lockOpenIntent", async function () {
		it("Should be failed when Sender address is Suspended", async () => {
			await context.controlFacet.suspendAddress(partyB1.getSigner, true)
			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "UserSuspended")
		})

		it("Should be failed when in Emergency Mode", async () => {
			await context.controlFacet.activeEmergencyMode()
			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "EmergencyMode")
		})

		it("Should be failed when PartyB in Emergency Mode", async () => {
			await context.controlFacet.activePartyBEmergencyStatus(partyB1.getSigner)
			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "PartyBInEmergencyMode")
		})

		it("Should be failed when Globally Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(context.partyBOpenFacet.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "GlobalPaused")
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(context.partyBOpenFacet.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "PartyBActionsPaused")
		})

		it("Should failed when msgSender is not PartyB", async () => {
			await expect(context.partyBOpenFacet.connect(context.signers.partyA1).lockOpenIntent(1)).to.be.revertedWithCustomError(
				context.partyBOpenFacet,
				"NotPartyB",
			)
		})

		it("Should failed when partyA have partyB Roll", async () => {
			await context.controlFacet.setPartyBConfig(partyA1.getSigner, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 2,
				symbolType: 0,
			})

			await expect(context.partyBOpenFacet.connect(context.signers.partyA1).lockOpenIntent(1)).to.be.revertedWithCustomError(
				context.partyBOpenFacet,
				"SelfTradeNotAllowed",
			)
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

			await context.controlFacet.setSymbolState(2, false)
			await expect(partyB2.lockOpenIntent(2)).to.be.revertedWithCustomError(context.partyBOpenFacet, "InvalidSymbol")
		})

		it("should revert when partB symbol type mismatch intent symbol type", async () => {
			const latestBlock = await getLatestBlockTime()

			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
				symbolType: 1, // another category of symbols
			})

			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "SymbolTypeMismatch")
		})

		it("Should failed when intent expiration has been passed", async () => {
			const newBlock = (await getLatestBlockTime()) + 130
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])

			await expect(partyB1.lockOpenIntent(1)).to.revertedWithCustomError(context.partyBOpenFacet, "ExpirationTimestampPassed")
		})

		it("Should failed when intent id not exist", async () => {
			await expect(partyB1.lockOpenIntent(200)).to.be.revertedWithCustomError(context.partyBOpenFacet, "IntentNotFound")
		})

		it("Should failed when partyB oracle id not equal with intent symbol oracle id", async () => {
			await context.controlFacet.setPartyBConfig(partyB1.getSigner, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 2,
				symbolType: 0,
			})

			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "OracleMismatch")
		})

		it("Should failed when partyB is not Active or Valid", async () => {
			await context.controlFacet.setPartyBConfig(partyB1.getSigner, {
				isActive: false,
				lossCoverage: 0,
				oracleId: 1,
				symbolType: 0,
			})

			await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "NotPartyB")
		})

		it("Should failed when partyB not whitelisted in the intent sent by partyA", async () => {
			await expect(partyB2.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "NotWhitelistedPartyB")
		})

		it("Should failed when partyB is not Solvent", async () => {
			//requireSolventPartyB
			// await context.clearingHouse.flagIsolatedPartyBLiquidation(context.signers.partyB1,context.collateral)
			// await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "NotSolvent")
			//TODO ::: it is implemented after clearing house development
		})

		it("Should add partyB to intent storage", async () => {
			// await expect(partyB1.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "NotSolvent")
			//TODO ::: it is implemented after clearing house development
		})

		it("Should lock open intent successfully", async () => {
			await expect(partyB1.lockOpenIntent(1)).to.not.reverted

			const intent = await context.viewFacet.getOpenIntent(1)

			expect(intent.status).to.equal(1) // IntentStatus.LOCKED
			expect(intent.partyB).to.equal(partyB1.getSigner)

			// TODO ::: check intentLayout states
		})
	})

	describe("fillOpenIntent", async function () {
		beforeEach(async () => {
			await partyB1.lockOpenIntent(1)
		})

		it("Should failed when Global Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBOpenFacet, "GlobalPaused")
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(partyB1.fillOpenIntent(2, 100, 7)).to.revertedWithCustomError(context.partyAOpenFacet, "PartyBActionsPaused")
		})

		it("Should be failed when in Emergency Mode", async () => {
			await context.controlFacet.activeEmergencyMode()
			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBOpenFacet, "EmergencyMode")
		})

		it("Should be failed when PartyB in Emergency Mode", async () => {
			await context.controlFacet.activePartyBEmergencyStatus(partyB1.getSigner)
			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBOpenFacet, "PartyBInEmergencyMode")
		})

		it("Should be failed when in Emergency Mode", async () => {
			await context.controlFacet.activeEmergencyMode()
			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBOpenFacet, "EmergencyMode")
		})

		it("Should be failed when PartyB in Emergency Mode", async () => {
			await context.controlFacet.activePartyBEmergencyStatus(partyB1.getSigner)
			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.be.revertedWithCustomError(context.partyBOpenFacet, "PartyBInEmergencyMode")
		})

		it("Should failed when msgSender is not PartyB", async () => {
			await expect(partyB2.fillOpenIntent(2, 100, 7)).to.revertedWithCustomError(context.partyBOpenFacet, "UnauthorizedSender") // no matter the intent ID
		})

		it("Should failed when partyA suspended", async () => {
			await context.controlFacet.suspendAddress(partyA1.getSigner, true)

			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.revertedWithCustomError(context.partyBOpenFacet, "UserSuspended")
		})

		it("Should failed when partyB suspended", async () => {
			await context.controlFacet.suspendAddress(partyB1.getSigner, true)

			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.revertedWithCustomError(context.partyBOpenFacet, "UserSuspended")
		})

		it("Should failed when symbol is not valid", async () => {
			await context.controlFacet.setSymbolState(1, false)

			await expect(partyB1.fillOpenIntent(1, 100, 7)).to.revertedWithCustomError(context.partyBOpenFacet, "InvalidSymbol")
		})

		it("Should failed when intent not in Valid state", async () => {
			await partyA2.setBalances(context.collateral, e(100000), e(100000))

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

			await partyA2.sendOpenIntent(request)
			await partyB2.lockOpenIntent(2)
			await partyA2.sendCancelOpenIntent(["2"])

			// await expect(partyB2.fillOpenIntent(2, 5, 2)).to.revertedWithCustomError(context.partyBOpenFacet, "InvalidState")
			//TODO ::: should find a way to call the fill intent with an invalid state
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

		it("Should failed when Intent quantity mismatch fill quantity", async () => {
			await expect(partyB1.fillOpenIntent(1, e(1000), 7)).to.revertedWithCustomError(context.partyBOpenFacet, "InvalidAmount")
			await expect(partyB1.fillOpenIntent(1, e(0), 7)).to.revertedWithCustomError(context.partyBOpenFacet, "InvalidAmount")
		})

		it("Should failed when Intent price mismatch fill type price", async () => {
			let intent: OpenIntentStructOutput = await context.viewFacet.getOpenIntent(1)
			if (intent.tradeAgreements.tradeSide == BigInt(TradeSide.BUY)) {
				await expect(partyB1.fillOpenIntent(1, 100, 8)).to.revertedWithCustomError(context.partyBOpenFacet, "InvalidOpenPrice")
				await expect(partyB1.fillOpenIntent(1, 100, 5)).not.to.revertedWithCustomError(context.partyBOpenFacet, "InvalidOpenPrice")
			} else if (intent.tradeAgreements.tradeSide == BigInt(TradeSide.SELL)) {
				await expect(partyB1.fillOpenIntent(1, 100, 5)).to.revertedWithCustomError(context.partyBOpenFacet, "InvalidOpenPrice")
				await expect(partyB1.fillOpenIntent(1, 100, 8)).not.to.revertedWithCustomError(context.partyBOpenFacet, "InvalidOpenPrice")
			}
		})

		it("Should fail when partyA active trades more than max active trades", async function () {
			let timestamp = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner, partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(timestamp + 120)
				.expirationTimestamp(timestamp + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(10))
				.price(e(5))
				.build()

			await partyA1.sendOpenIntent(request)
			await partyB1.lockOpenIntent(2)

			await expect(partyB1.fillOpenIntent(2, 10, 5)).not.to.be.revertedWithCustomError(context.partyBOpenFacet, "TooManyActiveTradesForPartyA")
		})

		it("Should failed when PartyA have more than max Active Trade", async () => {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(10))
				.price(e(5))
				.build()

			await context.controlFacet.setMaxConnectedCounterParties(1) // max # of trade with MarginType of type isolated or cross for a partyA
			expect(await partyB1.fillOpenIntent(1, e(100), 7)).not.to.reverted
			expect(await partyA1.sendOpenIntent(request)).not.to.reverted
			expect(await partyB2.lockOpenIntent(2)).not.to.reverted
			await expect(partyB2.fillOpenIntent(2, 10, 5)).to.revertedWithCustomError(context.partyBOpenFacet, "MaxCounterPartyConnectionsReached")
		})

		it("Should failed when Intent price mismatch fill type price", async () => {
			// partyB1.setBalances(context.collateral, e(50), e(50))
			// await expect(partyB1.fillOpenIntent(1, 100, 2)).to.revertedWithCustomError(context.partyBOpenFacet, "InsufficientLockedBalance")
			//TODO ::: what are the balance requirements of PartyB
		})

		it("Should make Trade Object ", async () => {
			// Manage trading fees for affiliators and fee collectors
			// update the state  and layout of intent for counterparties (full or partial fill)
			// successfully add the trade object for counter parties
			// update account balance relationship
			//
			//TODO ::: should work as expected
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

		it("Should failed when PartyB is in the liquidation process", async () => {
			//TODO ::: as title
		})

		it("Should change intent status to EXPIRED when deadline reached", async () => {
			// TODO ::: as title
			// const newBlock = await getLatestBlockTime() + 150
			// await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			// expect(await context.partyBOpenFacet.connect(partyB1.getSigner).unlockOpenIntent(1)).to.not.reverted
			// const intent = await context.viewFacet.getOpenIntent(1)
			// expect(intent.status).to.equal(3)
		})

		it("Should change intent status to PENDING", async () => {
			expect(await partyB1.unlockOpenIntent("1")).to.not.reverted

			const intent = await context.viewFacet.getOpenIntent(1)

			expect(intent.status).to.equal(0) //IntentStatus.PENDING
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

			const latestBlock = await getLatestBlockTime()
			const requestIsolated = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner, partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 300)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(70))
				.price(7)
				.marginType(MarginType.ISOLATED)
				.build()

			const requestCross = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 300)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(70))
				.price(7)
				.marginType(MarginType.CROSS)
				.build()

			// PartyA sends some Intents
			const testTable = [requestIsolated, requestIsolated, requestIsolated, requestCross]

			// testTable.forEach(async c => {
			// 	await expect(partyA2.sendOpenIntent(c.request))
			// })
			expect(await partyA2.sendOpenIntent(requestIsolated)).not.to.reverted // fee and premium for party A
			expect(await partyA2.sendOpenIntent(requestIsolated)).not.to.reverted
			expect(await partyA2.sendOpenIntent(requestIsolated)).not.to.reverted
			expect(await partyA2.sendOpenIntent(requestCross)).not.to.reverted
			expect(await partyA2.sendOpenIntent(requestCross)).not.to.reverted
			expect(await partyA2.sendOpenIntent(requestCross)).not.to.reverted
			expect(await partyA2.sendOpenIntent(requestCross)).not.to.reverted
			expect(await partyA2.sendOpenIntent(requestCross)).not.to.reverted
			expect(await partyA2.sendOpenIntent(requestIsolated)).not.to.reverted
			expect(await partyA2.sendOpenIntent(requestIsolated)).not.to.reverted

			let openIntents: OpenIntentStruct[] = await context.viewFacet.getActiveOpenIntents(partyA2.getSigner, 0, 100)
			for (let openIntent of openIntents) {
				console.log("Initial OpenIntents: ")
				console.log("ID: ", openIntent.id)
				console.log("Status: ", openIntent.status == 0 ? "Pending" : openIntent.status)
				console.log("Quantity: ", openIntent.tradeAgreements.quantity)
			}

			const symbol: SymbolStruct = await context.viewFacet.getSymbol(openIntents[2].tradeAgreements.symbolId)

			const tradingFeeFromView = await context.viewFacet.getTradingFee(2)
			const premiumFromView = await context.viewFacet.getPremium(2)
			const affiliateFeeFromView = await context.viewFacet.getAffiliateFee(openIntents[1].affiliate,symbol.symbolId)

			let partyAFeesPaid = BigInt(openIntents.length) * (tradingFeeFromView + affiliateFeeFromView)
			let partyAPremiumPaid = BigInt(openIntents.length) * premiumFromView
			//OI == open intent
			let send_OI_IsolatedBalancePartyA = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateral.getAddress())

			// some time elapses
			let newBlockTimeStamp = (await getLatestBlockTime()) + 20
			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTimeStamp])
			await network.provider.send("evm_mine")

			// PartyB locks
			// expect( await partyB1.lockOpenIntent(1)).not.to.reverted
			expect(await partyB1.lockOpenIntent(2)).not.to.reverted
			expect(await partyB1.lockOpenIntent(3)).not.to.reverted
			expect(await partyB1.lockOpenIntent(4)).not.to.reverted
			expect(await partyB1.lockOpenIntent(5)).not.to.reverted
			expect(await partyB1.lockOpenIntent(6)).not.to.reverted
			expect(await partyB1.lockOpenIntent(7)).not.to.reverted
			expect(await partyB1.lockOpenIntent(8)).not.to.reverted
			expect(await partyB1.lockOpenIntent(9)).not.to.reverted
			expect(await partyB1.lockOpenIntent(10)).not.to.reverted
			expect(await partyB1.lockOpenIntent(11)).not.to.reverted

			let lockIsolatedBalancePartyB = await context.viewFacet.getIsolatedBalance(partyB1.getSigner, await context.collateral.getAddress())

			newBlockTimeStamp = (await getLatestBlockTime()) + 20 // Time passes
			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTimeStamp])
			await network.provider.send("evm_mine")

			expect(await partyA2.sendCancelOpenIntent(["2", "3"])).not.to.reverted // partyA Cancels some intent

			expect(await partyB1.unlockOpenIntent(4)).not.to.reverted // partyB Unlock some intents
			expect(await partyB1.unlockOpenIntent(5)).not.to.reverted

			let unlockIsolatedBalancePartyB = await context.viewFacet.getIsolatedBalance(partyB1.getSigner, await context.collateral.getAddress())

			newBlockTimeStamp = (await getLatestBlockTime()) + 20 // Time passes
			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTimeStamp])
			await network.provider.send("evm_mine")

			expect(await partyB1.acceptCancelOpenIntent(2)).not.to.reverted // partyB Accepts Cancel of some partyA Cancels
			expect(await partyB1.acceptCancelOpenIntent(3)).not.to.reverted

			expect(await partyB1.fillOpenIntent(6, 50, 6)).not.to.reverted
			expect(await partyB1.fillOpenIntent(7, 50, 6)).not.to.reverted // partyB Fills some intent

			let filIsolatedBalancePartyB = await context.viewFacet.getIsolatedBalance(partyB1.getSigner, await context.collateral.getAddress())
			let cancel_OI_IsolatedBalancePartyA = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateral.getAddress())

			openIntents = await context.viewFacet.getActiveOpenIntents(partyA2.getSigner, 0, 100)
			for (let openIntent of openIntents) {
				console.log("\nOpenIntents Before Deadline: ")
				console.log("ID: ", openIntent.id)
				console.log(
					"Status: ",
					openIntent.status == 0
						? "Pending"
						: openIntent.status == 1
						? "LOCKED"
						: openIntent.status == 2
						? "CANCEL_PENDING"
						: openIntent.status == 3
						? "CANCELED"
						: openIntent.status == 4
						? "FILLED"
						: openIntent.status == 5
						? "EXPIRED"
						: openIntent.status,
				)
			}

			newBlockTimeStamp = (await getLatestBlockTime()) + 140 // Time passes
			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTimeStamp])
			await network.provider.send("evm_mine")

			expect(await partyB1.unlockOpenIntent(8)).not.to.reverted // what happens to locked intents
			expect(await partyB1.unlockOpenIntent(9)).not.to.reverted //

			openIntents = await context.viewFacet.getActiveOpenIntents(partyA2.getSigner, 0, 100)
			for (let openIntent of openIntents) {
				console.log("\nOpenIntents After Deadline: ")
				console.log("ID: ", openIntent.id)
				console.log(
					"Status: ",
					openIntent.status == 0
						? "Pending"
						: openIntent.status == 1
						? "LOCKED"
						: openIntent.status == 2
						? "CANCEL_PENDING"
						: openIntent.status == 3
						? "CANCELED"
						: openIntent.status == 4
						? "FILLED"
						: openIntent.status == 5
						? "EXPIRED"
						: openIntent.status,
				)
			}

			let expireIsolatedBalancePartyB = await context.viewFacet.getIsolatedBalance(partyB1.getSigner, await context.collateral.getAddress())
			let expireIsolatedBalancePartyA = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateral.getAddress())
		})
	})
}
