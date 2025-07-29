import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import "@nomicfoundation/hardhat-ethers";
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
// import { encodeBytes32String, ZeroAddress } from "ethers/lib.esm"
import {
	MarginType,
	TradeSide,
	LiquidationStatus,
	TradeStatus,
	WithdrawStatus,
	IntentStatus,
	CloseIntentStatus
} from "./option-enums"
import { address } from "hardhat/internal/core/config/config-validation"
import { ZeroAddress } from "ethers"
import {clearingHouse, view} from "../types/contracts/facets"
import { exceptions } from "winston"

export function shouldBehaveLikeClearingHouseFacet(): void {
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

		const newBlock = (await getLatestBlockTime()) + 170
		await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
		await network.provider.send("evm_mine")
	})

	describe.only("liquidation", async function () {
		it("Should be failed when Globally Paused", async () => {
			// Globally Pause the System
			await context.controlFacet.pauseGlobal()
			// Checking all 3 flagging functions when paused
			await expect(context.clearingHouse.flagIsolatedPartyBLiquidation(
				partyB1.getSigner.getAddress(),
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"GlobalPaused",
			)
			await expect(context.clearingHouse.flagCrossPartyBLiquidation(
				partyB1.getSigner.getAddress(),
				partyA1.getSigner.getAddress(),
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"GlobalPaused",
			)
			await expect(context.clearingHouse.flagPartyALiquidation(
				partyA1.getSigner.getAddress(),
				partyB1.getSigner.getAddress(),
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"GlobalPaused",
			)
		})

		it("Should failed when Liquidating Paused", async () => {
			// Pause the liquidating system
			await context.controlFacet.pauseLiquidating()
			// Checking all 3 flagging functions when paused
			await expect(context.clearingHouse.flagIsolatedPartyBLiquidation(
				partyB1.getSigner.getAddress(),
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"LiquidatingPaused",
			)
			await expect(context.clearingHouse.flagCrossPartyBLiquidation(
				partyB1.getSigner.getAddress(),
				partyA1.getSigner.getAddress(),
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"LiquidatingPaused",
			)
			await expect(context.clearingHouse.flagPartyALiquidation(
				partyA1.getSigner.getAddress(),
				partyB1.getSigner.getAddress(),
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"LiquidatingPaused",
			)
		})

		it("Should failed when the sender does not have CLEARING_HOUSE role", async () => {

			// Checking all 3 flagging functions when paused
			await expect(context.clearingHouse.connect(context.signers.admin).flagIsolatedPartyBLiquidation(
				partyB1.getSigner.getAddress(),
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"MissingRole",
			)
			await expect(context.clearingHouse.connect(context.signers.admin).flagCrossPartyBLiquidation(
				partyB1.getSigner.getAddress(),
				partyA1.getSigner.getAddress(),
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"MissingRole",
			)
			await expect(context.clearingHouse.connect(context.signers.admin).flagPartyALiquidation(
				partyA1.getSigner.getAddress(),
				partyB1.getSigner.getAddress(),
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"MissingRole",
			)

			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})
		})


		it("Should failed when flaggging party B with zero loss coverage", async () => {

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})

			// Checking flag functions when Party B has zero loss coverage
			await expect(context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB1.getSigner.getAddress(),
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"ZeroLossCoverage",
			)
		})

		it("Should failed when flaggging party B which has not been solvent", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)

			// Checking flag function when Party B has not been solvent
			await expect(context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"NotSolvent"
			)

		})

		it("Should flagged when flaggging party B with ISOLATED BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)

			expect((await context.viewFacet.getLiquidationDetail(liquidationId)).status).to.be.equal(LiquidationStatus.FLAGGED)
		})

		it("Should unflagged when flaggging party B with ISOLATED BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).unflagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)).to.be.equal(0)

		})

		it("Should failed when liquidating solvent party B with ISOLATED BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
				partyB2.address,
				context.collateral.getAddress(),
				e(-10000),
				e(10)
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"PartyBSolvent"
			)
		})
		it("Should liquidate when liquidating party B with ISOLATED BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
				partyB2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)

			await expect((await context.viewFacet.getLiquidationDetail(liquidationId)).status).to.be.equal(LiquidationStatus.IN_PROGRESS)
		})

		it("Should failed when flaggging party B which has not been solvent with CROSS BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			await context.clearingHouse.connect(context.signers.clearingHouse).flagCrossPartyBLiquidation(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress()
			)

			// Checking flag function when Party B has not been solvent
			await expect(context.clearingHouse.connect(context.signers.clearingHouse).flagCrossPartyBLiquidation(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"NotSolvent"
			)

		})

		it("Should flagged when flaggging party B with CROSS BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagCrossPartyBLiquidation(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress()
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress()
			)

			expect((await context.viewFacet.getLiquidationDetail(liquidationId)).status).to.be.equal(LiquidationStatus.FLAGGED)
		})

		it("Should unflagged when flaggging party B with CROSS BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagCrossPartyBLiquidation(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).unflagCrossPartyBLiquidation(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress()
			)).to.be.equal(0)

		})

		it("Should failed when liquidating solvent party B with CROSS BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.CROSS)
				.build()

			await context.accountFacet.connect(partyB2.getSigner).allocate(
				context.collateral.getAddress(),
				partyA2.address,
				e(100000)
			)
			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagCrossPartyBLiquidation(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress()
			)).not.reverted

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).liquidateCrossPartyB(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress(),
				e(-10000),
				e(10)
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"PartyBSolvent"
			)
		})

		it("Should liquidate when liquidating party B with CROSS BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.CROSS)
				.build()

			await context.accountFacet.connect(partyB2.getSigner).allocate(
				context.collateral.getAddress(),
				partyA2.address,
				e(100000)
			)
			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			const partyABeforeCrossBalance = (await context.viewFacet.getCrossBalance(
				partyA2.address,
				context.collateral.getAddress(),
				partyB2.address
			)).balance

			const partyBBeforeCrossBalance = (await context.viewFacet.getCrossBalance(
				partyB2.address,
				context.collateral.getAddress(),
				partyA2.address
			)).balance

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagCrossPartyBLiquidation(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateCrossPartyB(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress()
			)

			const partyAAfterCrossBalance = (await context.viewFacet.getCrossBalance(
				partyA2.address,
				context.collateral.getAddress(),
				partyB2.address
			)).balance

			const partyBAfterCrossBalance = (await context.viewFacet.getCrossBalance(
				partyB2.address,
				context.collateral.getAddress(),
				partyA2.address
			)).balance


			await expect((await context.viewFacet.getLiquidationDetail(liquidationId)).status).to.be.equal(LiquidationStatus.IN_PROGRESS)


			await expect(partyAAfterCrossBalance - partyABeforeCrossBalance).to.be.equal(
				partyBBeforeCrossBalance - partyBAfterCrossBalance
			)

			await expect(partyBAfterCrossBalance).to.be.equal(0)
		})

		it("Should failed when flaggging party A which has not been solvent with CROSS SELL", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.mm(30000)
				.tradeSide(TradeSide.SELL)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			await context.clearingHouse.connect(context.signers.clearingHouse).flagPartyALiquidation(
				partyA2.address,
				partyB2.address,
				context.collateral.getAddress()
			)

			// Checking flag function when Party B has not been solvent
			await expect(context.clearingHouse.connect(context.signers.clearingHouse).flagPartyALiquidation(
				partyA2.address,
				partyB2.address,
				context.collateral.getAddress()
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"NotSolvent"
			)

		})

		it("Should flagged when flaggging party A with CROSS SELL", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.mm(30000)
				.tradeSide(TradeSide.SELL)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagPartyALiquidation(
				partyA2.address,
				partyB2.address,
				context.collateral.getAddress()
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress()
			)

			expect((await context.viewFacet.getLiquidationDetail(liquidationId)).status).to.be.equal(LiquidationStatus.FLAGGED)
		})

		it("Should unflagged when flaggging party A with CROSS SELL", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.mm(30000)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagPartyALiquidation(
				partyA2.address,
				partyB2.address,
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).unflagPartyALiquidation(
				partyA2.address,
				partyB2.address,
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress()
			)).to.be.equal(0)

		})

		it("Should failed when liquidating solvent party A with CROSS SELL", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(e(30000))
				.tradeSide(TradeSide.SELL)
				.marginType(MarginType.CROSS)
				.build()

			await context.accountFacet.connect(partyA2.getSigner).allocate(
				context.collateral.getAddress(),
				partyB2.address,
				e(40000)
			)
			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagPartyALiquidation(
				partyA2.address,
				partyB2.address,
				context.collateral.getAddress()
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress()
			)
			// console.log("cross balance",await context.viewFacet.getCrossBalance(partyA2.address,context.collateral.getAddress(),partyB2.address))

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).liquidateCrossPartyA(
				liquidationId,
				partyA2.address,
				partyB2.address,
				context.collateral.getAddress(),
				e(-50000),
				e(10)
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"PartyASolvent"
			)
		})

		it("Should liquidate when liquidating party A with CROSS SELL", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(e(30000))
				.tradeSide(TradeSide.SELL)
				.marginType(MarginType.CROSS)
				.build()

			await context.accountFacet.connect(partyA2.getSigner).allocate(
				context.collateral.getAddress(),
				partyB2.address,
				e(40000)
			)

			await context.accountFacet.connect(partyB2.getSigner).allocate(
				context.collateral.getAddress(),
				partyA2.address,
				e(50000)
			)

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			const partyABeforeCrossBalance = (await context.viewFacet.getCrossBalance(
				partyA2.address,
				context.collateral.getAddress(),
				partyB2.address
			)).balance

			const partyBBeforeCrossBalance = (await context.viewFacet.getCrossBalance(
				partyB2.address,
				context.collateral.getAddress(),
				partyA2.address
			)).balance

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagPartyALiquidation(
				partyA2.address,
				partyB2.address,
				context.collateral.getAddress()
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress()
			)

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateCrossPartyA(
				liquidationId,
				partyA2.address,
				partyB2.address,
				context.collateral.getAddress(),
				e(-120000),
				e(10)
			)).not.reverted

			await expect((await context.viewFacet.getLiquidationDetail(liquidationId)).status).to.be.equal(LiquidationStatus.IN_PROGRESS)

			const partyAAfterCrossBalance = (await context.viewFacet.getCrossBalance(
				partyA2.address,
				context.collateral.getAddress(),
				partyB2.address
			)).balance

			const partyBAfterCrossBalance = (await context.viewFacet.getCrossBalance(
				partyB2.address,
				context.collateral.getAddress(),
				partyA2.address
			)).balance


			await expect(partyABeforeCrossBalance - partyAAfterCrossBalance).to.be.equal(
				partyBAfterCrossBalance - partyBBeforeCrossBalance
			)

			await expect(partyAAfterCrossBalance).to.be.equal(0)


		})

		it("Should failed when closing by mismatching inputs after liquidating party B with ISOLATED BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
				partyB2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(
				liquidationId,
				[1],
				[e(1000), e(2000)]
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"MismatchedArrayLengths"
			)
		})

		it("Should failed when closing by FLAGGED liquidation status for party B with ISOLATED BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted


			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(
				liquidationId,
				[1],
				[e(30000)]
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"InvalidState"
			)
		})

		it("Should closed when closing after liquidating party B with ISOLATED BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
				partyB2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(
				liquidationId,
				[1],
				[e(30000)]
			)).not.reverted

			expect((await context.viewFacet.getTrade(1)).status).to.be.equal(TradeStatus.LIQUIDATED)

		})
		it("Should failed when closing by mismatching inputs after liquidating party B with CROSS BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.CROSS)
				.build()

			await context.accountFacet.connect(partyB2.getSigner).allocate(
				context.collateral.getAddress(),
				partyA2.address,
				e(100000)
			)
			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagCrossPartyBLiquidation(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateCrossPartyB(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress()
			)

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(
				liquidationId,
				[1],
				[e(1000), e(2000)]
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"MismatchedArrayLengths"
			)
		})

		it("Should failed when closing by FLAGGED liquidation status for party B with CROSS BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.CROSS)
				.build()

			await context.accountFacet.connect(partyB2.getSigner).allocate(
				context.collateral.getAddress(),
				partyA2.address,
				e(100000)
			)
			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagCrossPartyBLiquidation(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress()
			)).not.reverted


			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress()
			)

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(
				liquidationId,
				[1],
				[e(30000)]
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"InvalidState"
			)
		})
		it("Should closed when closing after liquidating party B with CROSS BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.CROSS)
				.build()

			await context.accountFacet.connect(partyB2.getSigner).allocate(
				context.collateral.getAddress(),
				partyA2.address,
				e(100000)
			)
			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagCrossPartyBLiquidation(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateCrossPartyB(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress()
			)

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(
				liquidationId,
				[1],
				[e(30000)]
			)).not.reverted

			expect((await context.viewFacet.getTrade(1)).status).to.be.equal(TradeStatus.LIQUIDATED)
		})

		it("Should failed when allocating from reserve balance has insufficient balance ", async () => {
			await expect(context.clearingHouse.connect(context.signers.clearingHouse).allocateFromReserveToCross(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress(),
				e(1000)
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"InsufficientBalance"
			)
		})
		it("Should allocate from reserve balance into cross balance", async () => {
			await context.accountFacet.connect(context.signers.partyB2).allocateToReserveBalance(
				context.collateral.getAddress(),
				e(10000)
			)
			const partyBBeforeReserveBalance = await context.viewFacet.getReserveBalance(
				partyB2.address,
				context.collateral.getAddress()
			)
			const partyBBeforeCrossBalance = (await context.viewFacet.getCrossBalance(
				partyB2.address,
				context.collateral.getAddress(),
				partyA2.address
			)).balance

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).allocateFromReserveToCross(
				partyB2.address,
				partyA2.address,
				context.collateral.getAddress(),
				e(1000)
			)).not.reverted

			const partyBAfterReserveBalance = await context.viewFacet.getReserveBalance(
				partyB2.address,
				context.collateral.getAddress()
			)

			const partyBAfterCrossBalance = (await context.viewFacet.getCrossBalance(
				partyB2.address,
				context.collateral.getAddress(),
				partyA2.address
			)).balance

			expect(partyBBeforeReserveBalance - partyBAfterReserveBalance).to.be.equal(
				partyBAfterCrossBalance - partyBBeforeCrossBalance
			)

		})

		it("Should failed when try to confiscate party B by invalid status in ISOLATED BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			// expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
			// 	partyB2.address,
			// 	context.collateral.getAddress(),
			// 	e(-1200000),
			// 	e(10)
			// )).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)

			// await expect((await context.viewFacet.getLiquidationDetail(liquidationId)).status).to.be.equal(LiquidationStatus.IN_PROGRESS)
			//
			await expect(context.clearingHouse.connect(context.signers.clearingHouse).confiscate(
				liquidationId,
				e(10000),
				partyB2.address,
				partyA2.address,
				MarginType.ISOLATED
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"InvalidState"
			)
		})

		it("Should failed when try to confiscate party B by insufficient balance in ISOLATED BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
				partyB2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).confiscate(
				liquidationId,
				e(120000),
				partyB2.address,
				partyA2.address,
				MarginType.ISOLATED
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"InsufficientIntBalance"
			)

		})
		it("Should confiscate party B when liquidating in ISOLATED BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			const partyBBeforeIsolatedBalance = await context.viewFacet.getIsolatedBalance(
				partyB2.address,
				context.collateral.getAddress()
			)

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
				partyB2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)


			const liquidationAmount = e(30000)

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).confiscate(
				liquidationId,
				liquidationAmount,
				partyB2.address,
				partyA2.address,
				MarginType.ISOLATED
			)).not.reverted

			const partyBAfterIsolatedBalance = await context.viewFacet.getIsolatedBalance(
				partyB2.address,
				context.collateral.getAddress()
			)

			await expect(partyBBeforeIsolatedBalance - partyBAfterIsolatedBalance).to.be.equal(liquidationAmount)
		})

		it("Should failed when confiscating party B withdrawal by invalid status in ISOLATED BUY", async () => {

			await context.accountFacet.connect(context.signers.partyB1).initiateWithdraw(
				context.collateral.getAddress(),
				e(1000),
				context.signers.others[0]
			)
			const withdrawalId = 1
			await context.accountFacet.connect(partyB1.getSigner).cancelWithdraw(withdrawalId)

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).confiscateWithdrawal(
				withdrawalId
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"InvalidState"
			)

		})

		it("Should confiscate withdrawal", async () => {

			await context.accountFacet.connect(context.signers.partyB1).initiateWithdraw(
				context.collateral.getAddress(),
				e(1000),
				context.signers.others[0]
			)
			const partyBBeforeBalance = await context.viewFacet.getIsolatedBalance(
				partyB1.address,
				context.collateral.getAddress()
			)
			console.log("partyBBeforeBalance", partyBBeforeBalance)
			const withdrawalId = 1
			expect(await context.clearingHouse.connect(context.signers.clearingHouse).confiscateWithdrawal(withdrawalId)).not.reverted
			const partyBAfterBalance = await context.viewFacet.getIsolatedBalance(
				partyB1.address,
				context.collateral.getAddress()
			)
			console.log("partyBAfterBalance", partyBAfterBalance)
			expect(partyBAfterBalance - partyBBeforeBalance).to.be.equal(e(1000))
			const withdraw = await context.viewFacet.getWithdrawal(withdrawalId)
			expect(withdraw.status).to.be.equal(WithdrawStatus.CANCELED)
		})

		it("Should fail to distribute collateral after confiscate party B when liquidating in ISOLATED BUY because of mismatching inputs", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
				partyB2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)

			const liquidationAmount = e(30000)

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).confiscate(
				liquidationId,
				liquidationAmount,
				partyB2.address,
				partyA2.address,
				MarginType.ISOLATED
			)).not.reverted

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).distributeCollateral(
				liquidationId,
				partyB2.address,
				context.collateral.getAddress(),
				MarginType.ISOLATED,
				[partyA2.address],
				[e(10000), e(20000)]
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"MismatchedArrayLengths"
			)
		})

		it("Should fail to distribute collateral after confiscate party B when liquidating in ISOLATED BUY because of invalid state", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted


			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).distributeCollateral(
				liquidationId,
				partyB2.address,
				context.collateral.getAddress(),
				MarginType.ISOLATED,
				[partyA2.address],
				[e(30000)]
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"InvalidState"
			)
		})

		it("Should fail to distribute collateral after confiscate party B when liquidating in ISOLATED BUY because of exceeding amount from confiscated amount", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
				partyB2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)

			const liquidationAmount = e(30000)

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).confiscate(
				liquidationId,
				liquidationAmount,
				partyB2.address,
				partyA2.address,
				MarginType.ISOLATED
			)).not.reverted

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).distributeCollateral(
				liquidationId,
				partyB2.address,
				context.collateral.getAddress(),
				MarginType.ISOLATED,
				[partyA2.address],
				[e(40000)]
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"DistributedAmountExceedsConfiscatedAmount"
			)
		})

		it("Should distribute collateral after confiscate party B when liquidating in ISOLATED BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral.getAddress())
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
				partyB2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				ZeroAddress,
				partyB2.address,
				await context.collateral.getAddress()
			)

			const liquidationAmount = e(30000)

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).confiscate(
				liquidationId,
				liquidationAmount,
				partyB2.address,
				partyA2.address,
				MarginType.ISOLATED
			)).not.reverted


			expect(await context.clearingHouse.connect(context.signers.clearingHouse).distributeCollateral(
				liquidationId,
				partyB2.address,
				context.collateral.getAddress(),
				MarginType.ISOLATED,
				[partyA2.address],
				[liquidationAmount]
			)).not.reverted

			const partyAScheduledBalance = (await context.viewFacet.getScheduledReleaseEntry(
				partyA2.address,
				context.collateral.getAddress(),
				partyB2.address
			)).scheduled

			expect(partyAScheduledBalance).be.equal(liquidationAmount)

		})

		it("Should fail to cancel open intents when open intent is filled", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral.getAddress())
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents(
				[openIntentId1]
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"InvalidState"
			)

		})

		it("Should fail to cancel open intents when party is not in liquidation", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral.getAddress())
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents(
				[openIntentId1]
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"PartiesNotInLiquidation"
			)

		})

		it("Should cancel open intents", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral.getAddress())
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))


			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})


			const request2 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral.getAddress())
				.symbolId(1)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId2 = 2
			await partyA2.sendOpenIntent(request2)
			await partyB2.lockOpenIntent(openIntentId2)

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
				partyB2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents(
				[openIntentId2]
			)).not.reverted

			expect((await context.viewFacet.getOpenIntent(openIntentId2)).status).to.be.equal(IntentStatus.CANCELED)

		})

		it("Should fail to cancel close intents when close intent is filled", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral.getAddress())
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))
			const tradeId1 = 1
			await partyA2.sendCloseIntent(tradeId1,e(40) , e(12) , (await getLatestBlockTime()) + 140)
			const closeIntentId1 = 1
			await partyB2.fillCloseIntent(closeIntentId1,e(40),e(12))

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelCloseIntents(
				[closeIntentId1]
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"InvalidState"
			)

		})

		it("Should fail to cancel open intents when party is not in liquidation", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral.getAddress())
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))
			const tradeId1 = 1
			await partyA2.sendCloseIntent(tradeId1,e(40) , e(12) , (await getLatestBlockTime()) + 140)
			const closeIntentId1 = 1

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelCloseIntents(
				[closeIntentId1]
			)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"PartiesNotInLiquidation"
			)

		})

		it("Should cancel close intents", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral.getAddress())
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({cap: e(0.002), rate: e(0.0002)})
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))
			const tradeId1 = 1
			await partyA2.sendCloseIntent(tradeId1,e(40) , e(12) , (await getLatestBlockTime()) + 2000)
			const closeIntentId1 = 1

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})


			expect(await context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(
				partyB2.getSigner.getAddress(),
				context.collateral.getAddress()
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
				partyB2.address,
				context.collateral.getAddress(),
				e(-1200000),
				e(10)
			)).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelCloseIntents(
				[closeIntentId1]
			)).not.reverted

			expect((await context.viewFacet.getCloseIntent(closeIntentId1)).status).to.be.equal(CloseIntentStatus.CANCELED)
		})
	})
}
