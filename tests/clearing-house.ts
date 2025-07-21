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
import { MarginType, TradeSide , LiquidationStatus } from "./option-enums"
import { address } from "hardhat/internal/core/config/config-validation"
import { ZeroAddress } from "ethers"
import { clearingHouse } from "../types/contracts/facets"

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
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

			const liquidationId = await  context.viewFacet.getInProgressLiquidationId(
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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
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

			expect(await  context.viewFacet.getInProgressLiquidationId(
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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
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
		it("Should liquidated when liquidating party B with ISOLATED BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
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

			const liquidationId = await  context.viewFacet.getInProgressLiquidationId(
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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
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

			const liquidationId = await  context.viewFacet.getInProgressLiquidationId(
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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
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

			expect(await  context.viewFacet.getInProgressLiquidationId(
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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
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

		it("Should liquidated when liquidating party B with CROSS BUY", async () => {

			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
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

			const liquidationId = await  context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress()
			)

			await expect((await context.viewFacet.getLiquidationDetail(liquidationId)).status).to.be.equal(LiquidationStatus.IN_PROGRESS)
		})
	})
}
