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

import { CloseIntentStruct, LiquidationDetailStruct, SettlementPriceSigStruct, TradeStruct } from "../types/contracts/interfaces/ISymmio"
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
	CloseIntentStatus,
	LiquidationSide,
	OptionType,
} from "./option-enums"
import { address } from "hardhat/internal/core/config/config-validation"
import { ZeroAddress } from "ethers"
import { clearingHouse, view } from "../types/contracts/facets"
import { exceptions } from "winston"
import { Console } from "console"

export function shouldBehaveLikeClearingHouseFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB
	let formatter: Intl.NumberFormat

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyB1.setBalances(context.collateral, e(100000), e(10))
		// await partyB2.setBalances(context.collateral, e(100000), e(10))
		await partyA1.setBalances(context.collateral, e(100000), e(100000))
		await partyA2.setBalances(context.collateral, e(100000), e(10))
		await partyA2.setBalances(context.collateralNL, e(100000), e(1000))

		const newBlock = (await getLatestBlockTime()) + 170
		await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
		await network.provider.send("evm_mine")

		formatter = new Intl.NumberFormat("en-US", {})
	})

	describe("Isolated BUY liquidation", async function () {
		it("Should be failed when Globally Paused", async () => {
			// Globally Pause the System
			await context.controlFacet.pauseGlobal()
			// Checking all 3 flagging functions when paused
			await expect(
				context.clearingHouse.flagIsolatedPartyBLiquidation(partyB1.getSigner.getAddress(), context.collateral.getAddress()),
			).to.be.revertedWithCustomError(context.clearingHouse, "GlobalPaused")
			await expect(
				context.clearingHouse.flagCrossPartyBLiquidation(
					partyB1.getSigner.getAddress(),
					partyA1.getSigner.getAddress(),
					context.collateral.getAddress(),
				),
			).to.be.revertedWithCustomError(context.clearingHouse, "GlobalPaused")
			await expect(
				context.clearingHouse.flagPartyALiquidation(partyA1.getSigner.getAddress(), partyB1.getSigner.getAddress(), context.collateral.getAddress()),
			).to.be.revertedWithCustomError(context.clearingHouse, "GlobalPaused")
		})

		it("Should failed when Liquidating Paused", async () => {
			// Pause the liquidating system
			await context.controlFacet.pauseLiquidating()
			// Checking all 3 flagging functions when paused
			await expect(
				context.clearingHouse.flagIsolatedPartyBLiquidation(partyB1.getSigner.getAddress(), context.collateral.getAddress()),
			).to.be.revertedWithCustomError(context.clearingHouse, "LiquidatingPaused")
			await expect(
				context.clearingHouse.flagCrossPartyBLiquidation(
					partyB1.getSigner.getAddress(),
					partyA1.getSigner.getAddress(),
					context.collateral.getAddress(),
				),
			).to.be.revertedWithCustomError(context.clearingHouse, "LiquidatingPaused")
			await expect(
				context.clearingHouse.flagPartyALiquidation(partyA1.getSigner.getAddress(), partyB1.getSigner.getAddress(), context.collateral.getAddress()),
			).to.be.revertedWithCustomError(context.clearingHouse, "LiquidatingPaused")
		})

		it("Should failed when the sender does not have CLEARING_HOUSE role", async () => {
			// Checking all 3 flagging functions when paused
			await expect(
				context.clearingHouse
					.connect(context.signers.others[0])
					.flagIsolatedPartyBLiquidation(partyB1.getSigner.getAddress(), context.collateral.getAddress()),
			).to.be.revertedWithCustomError(context.clearingHouse, "MissingRole")
			await expect(
				context.clearingHouse
					.connect(context.signers.others[0])
					.flagCrossPartyBLiquidation(partyB1.getSigner.getAddress(), partyA1.getSigner.getAddress(), context.collateral.getAddress()),
			).to.be.revertedWithCustomError(context.clearingHouse, "MissingRole")
			await expect(
				context.clearingHouse
					.connect(context.signers.others[0])
					.flagPartyALiquidation(partyA1.getSigner.getAddress(), partyB1.getSigner.getAddress(), context.collateral.getAddress()),
			).to.be.revertedWithCustomError(context.clearingHouse, "MissingRole")

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
			await expect(
				context.clearingHouse.connect(context.signers.clearingHouse).flagIsolatedPartyBLiquidation(partyB1.address, context.collateral.getAddress()),
			).to.be.revertedWithCustomError(context.clearingHouse, "ZeroLossCoverage")
		})

		//TODO NO Clear Intentions
		it("Should failed when flaggging party B which has not been solvent", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(100))
				.price(e(10))
				.strikePrice(e(100))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(partyB2.address, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			await context.clearingHouse
				.connect(context.signers.clearingHouse)
				.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress())

			// Checking flag function when Party B has not been solvent
			await expect(
				context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).to.be.revertedWithCustomError(context.clearingHouse, "NotSolvent")
		})

		it("Should flagged when flaggging party B with ISOLATED BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(100))
				.price(e(10))
				.strikePrice(e(100))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

			expect((await context.viewFacet.getLiquidationDetail(liquidationId)).status).to.be.equal(LiquidationStatus.FLAGGED)
		})

		it("Should be able to unflag a flagged party B in ISOLATED BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			let liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())
			console.log("Liquidation Flag:", liquidationId)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.unflagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())
			console.log("Liquidation Flag:", liquidationId)

			expect(await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())).to.be.equal(0)
		})

		it("Should be failed when liquidating a solvent party B in ISOLATED BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			let partyBbalance = await context.viewFacet.getIsolatedBalance(partyB2.address, context.collateral)
			console.log("Party B Isolated Balance Before Deposit:\n", partyBbalance)
			await partyB2.setBalances(context.collateral, e(100000), e(1000))
			partyBbalance = await context.viewFacet.getIsolatedBalance(partyB2.address, context.collateral)
			console.log("Party B Isolated Balance After Deposit:\n", partyBbalance)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			const upnl = e(-10000)
			const collateralPrice = e(10)
			let partyBconfig = await context.viewFacet.getPartyBConfig(partyB2.address)
			const partyBSolvencyBalance = partyBbalance + (upnl * partyBconfig.lossCoverage) / collateralPrice
			console.log("Party B Solvency Balance", partyBSolvencyBalance)

			await expect(
				context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), upnl, collateralPrice),
			).to.be.revertedWithCustomError(context.clearingHouse, "PartyBSolvent")
		})

		it("Should be able to liquidate the Flagged party B in ISOLATED BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			let partyBbalance = await context.viewFacet.getIsolatedBalance(partyB2.address, context.collateral)
			console.log("Party B Isolated Balance Before Deposit:\n", partyBbalance)
			await partyB2.setBalances(context.collateral, e(100000), e(1000))
			partyBbalance = await context.viewFacet.getIsolatedBalance(partyB2.address, context.collateral)
			console.log("Party B Isolated Balance After Deposit:\n", partyBbalance)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			const upnl = e(-1200000)
			const collateralPrice = e(10)
			let partyBconfig = await context.viewFacet.getPartyBConfig(partyB2.address)
			const partyBSolvencyBalance = partyBbalance + (upnl * partyBconfig.lossCoverage) / collateralPrice
			console.log("Party B Solvency Balance", partyBSolvencyBalance)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), upnl, collateralPrice),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

			expect((await context.viewFacet.getLiquidationDetail(liquidationId)).status).to.be.equal(LiquidationStatus.IN_PROGRESS)
		})
	})

	describe("CROSS BUY Liquidaiton", async function () {
		it("Should failed when flaggging party B which has not been solvent in CROSS BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			await context.clearingHouse
				.connect(context.signers.clearingHouse)
				.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress())

			// Checking flag function when Party B has not been solvent
			await expect(
				context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress()),
			).to.be.revertedWithCustomError(context.clearingHouse, "NotSolvent")
		})

		it("Should be able to flag when flagging party B in CROSS BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress()),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress(),
			)

			const detail: LiquidationDetailStruct = await context.viewFacet.getLiquidationDetail(liquidationId)
			expect(detail.status).to.be.equal(LiquidationStatus.FLAGGED)
			expect(detail.side).to.be.equal(LiquidationSide.PARTY_B)
			expect(detail.partyA).to.be.equal(partyA2.address)
			expect(detail.partyB).to.be.equal(partyB2.address)
			expect(detail.flagger).to.be.equal(context.signers.clearingHouse.address)
		})

		it("Should be able to unflag when flagging party B in CROSS BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.unflagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress()),
			).not.reverted

			expect(await context.viewFacet.getInProgressLiquidationId(partyA2.address, partyB2.address, await context.collateral.getAddress())).to.be.equal(
				0,
			)
		})

		it("Should be failed when liquidating solvent party B with CROSS BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			let partyBBalance = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)
			console.log("Party B Cross Balance Before Deposit:\n", partyBBalance)
			await partyB2.setBalances(context.collateral, e(100000), e(1000))
			await context.accountFacet.connect(partyB2.getSigner).allocate(context.collateral.getAddress(), partyA2.address, e(1000))
			partyBBalance = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)
			console.log("Party B Cross Balance After Deposit:\n", partyBBalance)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress()),
			).not.reverted

			const upnl = e(-10000)
			const collateralPrice = e(10)
			let partyBconfig = await context.viewFacet.getPartyBConfig(partyB2.address)
			const partyBSolvencyBalance = partyBBalance.balance + (upnl * partyBconfig.lossCoverage) / collateralPrice
			console.log("Party B Solvency Balance", partyBSolvencyBalance)

			await expect(
				context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyB(partyB2.address, partyA2.address, context.collateral.getAddress(), upnl, collateralPrice),
			).to.be.revertedWithCustomError(context.clearingHouse, "PartyBSolvent")
		})

		it("Should liquidate when liquidating party B with CROSS BUY, Balances", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			const partyABeforeCrossBalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral.getAddress(), partyB2.address)
			let partyBBalance = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)
			console.log("Party A Cross Balance:", partyABeforeCrossBalance)
			console.log("Party B Cross Balance Before Deposit:", partyBBalance.balance.toLocaleString("en-US"))
			await partyB2.setBalances(context.collateral, e(100000), e(1000))
			await context.accountFacet.connect(partyB2.getSigner).allocate(context.collateral.getAddress(), partyA2.address, e(1000))
			partyBBalance = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)
			console.log("Party B Cross Balance After Deposit:", partyBBalance)
			console.log("Party B Balance part After Deposit:", formatter.format(partyBBalance.balance))

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress()),
			).not.reverted

			const upnl = e(-12000)
			const collateralPrice = e(10)
			let partyBconfig = await context.viewFacet.getPartyBConfig(partyB2.address)
			const upnlInCollateral = (upnl * partyBconfig.lossCoverage) / collateralPrice
			const partyBSolvencyBalance = partyBBalance.balance + upnlInCollateral
			console.log("UPNL in Collateral:", formatter.format(upnlInCollateral))
			console.log("Party B Solvency Balance Diff:", formatter.format(partyBSolvencyBalance))
			console.log(partyBSolvencyBalance >= 0 ? "Party B is Solvent" : "Party B is In Liquidation State")

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyB(partyB2.address, partyA2.address, context.collateral.getAddress(), upnl, collateralPrice),
			).not.reverted

			const partyAAfterCrossBalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral.getAddress(), partyB2.address)
			const partyBAfterCrossBalance = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral.getAddress(), partyA2.address)

			console.log("Party A Cross Balance After Liquidation:", partyAAfterCrossBalance)
			console.log("Party A Cross Balance After Liquidation:", partyAAfterCrossBalance.balance.toLocaleString("en-US"))
			console.log("Party A Cross Balance Diff:", formatter.format(partyAAfterCrossBalance.balance - partyABeforeCrossBalance.balance))
			console.log("Party B Cross Balance After Liquidation:", partyBAfterCrossBalance)

			expect(partyAAfterCrossBalance.balance - partyABeforeCrossBalance.balance).to.be.equal(partyBBalance.balance)
			expect(partyBAfterCrossBalance.balance).to.be.equal(0)
			expect(partyBAfterCrossBalance.locked).to.be.equal(0)
			expect(partyBAfterCrossBalance.totalMM).to.be.equal(0)
		})

		it("should behave when liquidating, so that Balances Of party A Experince No change when zero Or Below Balance Of party B avialable", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			const partyABeforeCrossBalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral.getAddress(), partyB2.address)
			let partyBBalance = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)
			await partyB2.setBalances(context.collateral, e(100000), e(1000))
			// await context.accountFacet
			// .connect(partyB2.getSigner).allocate(context.collateral.getAddress(), partyA2.address, e(1000))
			// await context.accountFacet.connect(partyB2.getSigner).deallocate(context.collateral.getAddress(), partyA2.address, e(1000))
			partyBBalance = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress()),
			).not.reverted

			const upnl = e(-12000)
			const collateralPrice = e(10)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyB(partyB2.address, partyA2.address, context.collateral.getAddress(), upnl, collateralPrice),
			).not.reverted

			const partyAAfterCrossBalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral.getAddress(), partyB2.address)
			const partyBAfterCrossBalance = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral.getAddress(), partyA2.address)

			//TODO simulate the balance of PartyB to be Zero or less
			// expect(partyAAfterCrossBalance.balance - partyABeforeCrossBalance.balance).to.be.equal(0)
			expect(partyBAfterCrossBalance.balance).to.be.equal(0)
			expect(partyBAfterCrossBalance.locked).to.be.equal(0)
			expect(partyBAfterCrossBalance.totalMM).to.be.equal(0)
		})

		it("Should liquidate when liquidating party B with CROSS BUY, State Update", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			await partyB2.setBalances(context.collateral, e(100000), e(1000))
			await context.accountFacet.connect(partyB2.getSigner).allocate(context.collateral.getAddress(), partyA2.address, e(1000))

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress()),
			).not.reverted

			let liquidationId = await context.viewFacet.getInProgressLiquidationId(partyA2.address, partyB2.address, await context.collateral.getAddress())
			let detail: LiquidationDetailStruct = await context.viewFacet.getLiquidationDetail(liquidationId)
			expect(detail.status).to.equal(LiquidationStatus.FLAGGED)

			const upnl = e(-1200000)
			const collateralPrice = e(10)
			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyB(partyB2.address, partyA2.address, context.collateral.getAddress(), upnl, collateralPrice),
			).not.reverted

			liquidationId = await context.viewFacet.getInProgressLiquidationId(partyA2.address, partyB2.address, await context.collateral.getAddress())

			detail = await context.viewFacet.getLiquidationDetail(liquidationId)
			expect(detail.status).to.be.equal(LiquidationStatus.IN_PROGRESS)
			expect(detail.collateralPrice).to.equal(collateralPrice)
		})
	})

	describe("CROSS SELL Liquidaiton", async function () {
		it("Should failed when flaggging party A which has not been solvent with CROSS SELL", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.mm(30000)
				.tradeSide(TradeSide.SELL)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			await context.clearingHouse
				.connect(context.signers.clearingHouse)
				.flagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress())

			// Checking flag function when Party B has not been solvent
			await expect(
				context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress()),
			).to.be.revertedWithCustomError(context.clearingHouse, "NotSolvent")
		})

		it("Should flagged when flaggging party A with CROSS SELL", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.mm(30000)
				.tradeSide(TradeSide.SELL)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress()),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress(),
			)
			const detail: LiquidationDetailStruct = await context.viewFacet.getLiquidationDetail(liquidationId)

			expect(detail.status).to.be.equal(LiquidationStatus.FLAGGED)
			expect(detail.side).to.be.equal(LiquidationSide.PARTY_A)
			expect(detail.partyA).to.be.equal(partyA2.address)
			expect(detail.partyB).to.be.equal(partyB2.address)
			expect(detail.flagger).to.be.equal(context.signers.clearingHouse.address)
			expect(detail.flagTimestamp).to.be.approximately(await getLatestBlockTime(), 5)
		})

		it("Should unflagged when flaggging party A with CROSS SELL", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(100))
				.strikePrice(e(100))
				.price(e(10))
				.mm(30000)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(100), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.unflagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress()),
			).not.reverted

			const liquidationID = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress(),
			)
			expect(liquidationID).to.be.equal(0)
		})

		it("Should failed when liquidating solvent party A with CROSS SELL", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(e(300))
				.tradeSide(TradeSide.SELL)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			let partyABalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			console.log("Party A Cross Balance Before Deposit:\n", partyABalance)

			await partyA2.setBalances(context.collateral, e(100000), e(1000))
			await context.accountFacet.connect(partyA2.getSigner).allocate(context.collateral.getAddress(), partyB2.address, e(1000))

			partyABalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			console.log("Party A Cross Balance After Deposit:\n", partyABalance)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress()),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress(),
			)

			const upnl = e(-5000)
			const collateralPrice = e(10)
			const upnlInCollateral = (upnl * e(1)) / collateralPrice
			const partyASolvencyBalanceDiff = partyABalance.balance - partyABalance.totalMM + upnlInCollateral
			console.log("UPNL in Collateral:", formatter.format(upnlInCollateral))
			console.log("Party A Solvency Balance Diff:", formatter.format(partyASolvencyBalanceDiff))
			console.log(partyASolvencyBalanceDiff >= 0 ? "Party A is Solvent" : "Party A is In Liquidation State")

			await expect(
				context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyA(liquidationId, partyA2.address, partyB2.address, context.collateral.getAddress(), upnl, e(10)),
			).to.be.revertedWithCustomError(context.clearingHouse, "PartyASolvent")
		})

		it("Should liquidate when liquidating party A with CROSS SELL, Balances", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(e(30000))
				.tradeSide(TradeSide.SELL)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			const partyBBeforeCrossBalance = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral.getAddress(), partyA2.address)

			let partyABalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			console.log("Party A Cross Balance Before Deposit:\n", partyABalance)

			await partyA2.setBalances(context.collateral, e(100000), e(1000))
			await context.accountFacet.connect(partyA2.getSigner).allocate(context.collateral.getAddress(), partyB2.address, e(1000))

			partyABalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			console.log("Party A Cross Balance After Deposit:\n", partyABalance)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress()),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress(),
			)

			const upnl = e(-12000)
			const collateralPrice = e(10)
			const upnlInCollateral = (upnl * e(1)) / collateralPrice
			const partyASolvencyBalanceDiff = partyABalance.balance - partyABalance.totalMM + upnlInCollateral
			console.log("UPNL in Collateral:", formatter.format(upnlInCollateral))
			console.log("Party A Solvency Balance Diff:", formatter.format(partyASolvencyBalanceDiff))
			console.log(partyASolvencyBalanceDiff >= 0 ? "Party A is Solvent" : "Party A is In Liquidation State")

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyA(liquidationId, partyA2.address, partyB2.address, context.collateral.getAddress(), upnl, collateralPrice),
			).not.reverted

			const partyAAfterCrossBalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral.getAddress(), partyB2.address)
			const partyBAfterCrossBalance = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral.getAddress(), partyA2.address)

			expect(partyBAfterCrossBalance.balance - partyBBeforeCrossBalance.balance).to.be.equal(partyABalance.balance)
			expect(partyAAfterCrossBalance.balance).to.be.equal(0)
			expect(partyAAfterCrossBalance.locked).to.be.equal(0)
			expect(partyAAfterCrossBalance.totalMM).to.be.equal(0)
		})

		it("Should liquidate when liquidating party A with CROSS SELL", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(e(30000))
				.tradeSide(TradeSide.SELL)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			let partyABalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			await partyA2.setBalances(context.collateral, e(100000), e(1000))
			await context.accountFacet.connect(partyA2.getSigner).allocate(context.collateral.getAddress(), partyB2.address, e(1000))
			partyABalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress()),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress(),
			)

			const upnl = e(-12000)
			const collateralPrice = e(10)
			const upnlInCollateral = (upnl * e(1)) / collateralPrice
			const partyASolvencyBalanceDiff = partyABalance.balance - partyABalance.totalMM + upnlInCollateral
			console.log("UPNL in Collateral:", formatter.format(upnlInCollateral))
			console.log("Party A Solvency Balance Diff:", formatter.format(partyASolvencyBalanceDiff))
			console.log(partyASolvencyBalanceDiff >= 0 ? "Party A is Solvent" : "Party A is In Liquidation State")

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyA(liquidationId, partyA2.address, partyB2.address, context.collateral.getAddress(), upnl, collateralPrice),
			).not.reverted

			const detail: LiquidationDetailStruct = await context.viewFacet.getLiquidationDetail(liquidationId)
			expect(detail.status).to.be.equal(LiquidationStatus.IN_PROGRESS)
			expect(detail.collateralPrice).to.be.equal(collateralPrice)
		})
	})

	describe("Close Trades", async function () {
		it("Should failed when closing by mismatching inputs after liquidating party B with ISOLATED BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10)),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

			await expect(
				context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [1], [e(1000), e(2000)]),
			).to.be.revertedWithCustomError(context.clearingHouse, "MismatchedArrayLengths")
		})

		it("Should failed when closing by FLAGGED liquidation status for party B", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			// In Flaged State
			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

			await expect(
				context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [1], [e(30000)]),
			).to.be.revertedWithCustomError(context.clearingHouse, "InvalidState")
		})

		it("Should closed when closing after liquidating party B with ISOLATED BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-12000), e(10)),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [1], [e(30000)])).not.reverted

			expect((await context.viewFacet.getTrade(1)).status).to.be.equal(TradeStatus.LIQUIDATED)
		})

		it("Should failed when closing by mismatching inputs after liquidating party B with CROSS BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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

			const openIntentId1 = 1
			await partyB2.setBalances(context.collateral, e(10000), e(1000))
			await context.accountFacet.connect(partyB2.getSigner).allocate(context.collateral.getAddress(), partyA2.address, e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyB(partyB2.address, partyA2.address, context.collateral.getAddress(), e(-1200000), e(10)),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress(),
			)

			await expect(
				context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [1], [e(1000), e(2000)]),
			).to.be.revertedWithCustomError(context.clearingHouse, "MismatchedArrayLengths")
		})

		it("Should failed when closing by FLAGGED liquidation status for party B with CROSS BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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

			const openIntentId1 = 1
			await partyB2.setBalances(context.collateral, e(10000), e(1000))
			await context.accountFacet.connect(partyB2.getSigner).allocate(context.collateral.getAddress(), partyA2.address, e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress()),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress(),
			)

			await expect(
				context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [1], [e(30000)]),
			).to.be.revertedWithCustomError(context.clearingHouse, "InvalidState")
		})

		it("Should closed when closing after liquidating party B with Isolated BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			// await context.accountFacet.connect(partyB2.getSigner).allocate(context.collateral.getAddress(), partyA2.address, e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			const tradeID = await context.viewFacet.getLastTradeId()
			const trade = await context.viewFacet.getTrade(tradeID)

			await partyA2.sendCloseIntent(tradeID, e(10), e(10), (await getLatestBlockTime()) + 100)
			await partyB2.fillCloseIntent(await context.viewFacet.getLastCloseIntentId(), e(10), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10)),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())
			const detail = await context.viewFacet.getLiquidationDetail(liquidationId)
			expect(detail.status).to.equal(LiquidationStatus.IN_PROGRESS)

			const getTradeOpenAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			const tradePremium = await context.viewFacet.getTradePremium(tradeID)
			const proportinalPremium = (tradePremium * getTradeOpenAmount) / trade.tradeAgreements.quantity
			const partyABalanceBefore = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateral)

			const price = [e(30000)]
			expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [tradeID], price)).not.reverted
			expect((await context.viewFacet.getTrade(tradeID)).status).to.be.equal(TradeStatus.LIQUIDATED)

			const partyABalanceAfter = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateral)
			const PartyABalaceDiff = partyABalanceAfter - partyABalanceBefore

			console.log("Premium Payed to Party A in Isolated Margin:", proportinalPremium)
			expect(PartyABalaceDiff).to.equal(proportinalPremium)
		})

		it("Should closed when closing after liquidating party B with CROSS BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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

			const openIntentId1 = 1
			await partyB2.setBalances(context.collateral, e(10000), e(1000))
			await context.accountFacet.connect(partyB2.getSigner).allocate(context.collateral.getAddress(), partyA2.address, e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			const tradeID = await context.viewFacet.getLastTradeId()
			const trade = await context.viewFacet.getTrade(tradeID)

			await partyA2.sendCloseIntent(tradeID, e(10), e(10), (await getLatestBlockTime()) + 100)
			await partyB2.fillCloseIntent(await context.viewFacet.getLastCloseIntentId(), e(10), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyB(partyB2.address, partyA2.address, context.collateral.getAddress(), e(-1200000), e(10)),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress(),
			)

			const getTradeOpenAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			const tradePremium = await context.viewFacet.getTradePremium(tradeID)
			const proportinalPremium = (tradePremium * getTradeOpenAmount) / trade.tradeAgreements.quantity
			const partyABalanceBefore = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)

			const price = [e(30000)]
			expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [tradeID], price)).not.reverted
			expect((await context.viewFacet.getTrade(tradeID)).status).to.be.equal(TradeStatus.LIQUIDATED)

			const partyABalanceAfter = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			const PartyABalaceDiff = partyABalanceAfter.balance - partyABalanceBefore.balance

			console.log("Premium Payed to Party A in Isolated Margin:", proportinalPremium)
			expect(PartyABalaceDiff).to.equal(proportinalPremium)
		})

		it("Should closed when closing after liquidating party B with CROSS SELL, Trade Status", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.SELL)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await context.accountFacet.connect(partyA2.getSigner).allocate(context.collateral.getAddress(), partyB2.address, e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			const tradeID = await context.viewFacet.getLastTradeId()

			const partyABalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			console.log("Party A Cross Balance:", partyABalance)

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress()),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress(),
			)

			const upnl = e(-15001)
			const collateralPrice = e(10)
			const upnlInCollateral = (upnl * e(1)) / collateralPrice
			const partyASolvencyBalanceDiff = partyABalance.balance - partyABalance.totalMM + upnlInCollateral
			console.log("UPNL in Collateral:", formatter.format(upnlInCollateral))
			console.log("Party A Solvency Balance Diff:", formatter.format(partyASolvencyBalanceDiff))
			console.log(partyASolvencyBalanceDiff >= 0 ? "Party A is Solvent" : "Party A is In Liquidation State")

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyA(liquidationId, partyA2.address, partyB2.address, context.collateral.getAddress(), upnl, collateralPrice),
			).not.reverted

			const price = [e(30000)]
			expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [tradeID], price)).not.reverted

			const trade = await context.viewFacet.getTrade(tradeID)
			expect(trade.status).to.be.equal(TradeStatus.LIQUIDATED)
			expect(trade.settledPrice).to.equal(price[0])
		})

		it("Should closed when closing after liquidating party B with CROSS SELL, Balances", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(2)
				.deadline((await getLatestBlockTime()) + 140)
				.expirationTimestamp((await getLatestBlockTime()) + 150)
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.SELL)
				.marginType(MarginType.CROSS)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await context.accountFacet.connect(partyA2.getSigner).allocate(context.collateral.getAddress(), partyB2.address, e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			const tradeID = await context.viewFacet.getLastTradeId()
			const trade = await context.viewFacet.getTrade(tradeID)

			const partyABalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			console.log("Party A Cross Balance:", partyABalance)

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress()),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(
				partyA2.address,
				partyB2.address,
				await context.collateral.getAddress(),
			)

			const upnl = e(-15001)
			const collateralPrice = e(10)
			const upnlInCollateral = (upnl * e(1)) / collateralPrice
			const partyASolvencyBalanceDiff = partyABalance.balance - partyABalance.totalMM + upnlInCollateral
			console.log("UPNL in Collateral:", formatter.format(upnlInCollateral))
			console.log("Party A Solvency Balance Diff:", formatter.format(partyASolvencyBalanceDiff))
			console.log(partyASolvencyBalanceDiff >= 0 ? "Party A is Solvent" : "Party A is In Liquidation State")

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyA(liquidationId, partyA2.address, partyB2.address, context.collateral.getAddress(), upnl, collateralPrice),
			).not.reverted

			const getTradeOpenAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
			const tradePremium = await context.viewFacet.getTradePremium(tradeID)
			const proportinalPremium = (tradePremium * getTradeOpenAmount) / trade.tradeAgreements.quantity
			const partyBBalanceBefore = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)

			const price = [e(30000)]
			expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [tradeID], price)).not.reverted

			const partyBBalanceAfter = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
			const PartyBBalaceDiff = partyBBalanceAfter.balance - partyBBalanceBefore.balance

			expect(PartyBBalaceDiff).to.equal(proportinalPremium)
		})
	})

	describe("Allocating From Reserve", async function () {
		it("Should failed when allocating from reserve balance has insufficient balance ", async () => {
			await expect(
				context.clearingHouse
					.connect(context.signers.clearingHouse)
					.allocateFromReserveToCross(partyB2.address, partyA2.address, context.collateral.getAddress(), e(1000)),
			).to.be.revertedWithCustomError(context.clearingHouse, "InsufficientBalance")
		})

		it("Should allocate from reserve balance into cross balance", async () => {
			await context.accountFacet.connect(context.signers.partyB2).allocateToReserveBalance(context.collateral.getAddress(), e(10000))
			const partyBBeforeReserveBalance = await context.viewFacet.getReserveBalance(partyB2.address, context.collateral.getAddress())
			const partyBBeforeCrossBalance = (await context.viewFacet.getCrossBalance(partyB2.address, context.collateral.getAddress(), partyA2.address))
				.balance

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.allocateFromReserveToCross(partyB2.address, partyA2.address, context.collateral.getAddress(), e(1000)),
			).not.reverted

			const partyBAfterReserveBalance = await context.viewFacet.getReserveBalance(partyB2.address, context.collateral.getAddress())

			const partyBAfterCrossBalance = (await context.viewFacet.getCrossBalance(partyB2.address, context.collateral.getAddress(), partyA2.address))
				.balance

			expect(partyBBeforeReserveBalance - partyBAfterReserveBalance).to.be.equal(partyBAfterCrossBalance - partyBBeforeCrossBalance)
		})
	})

	describe("Confiscation", async function () {
		it("Should failed when try to confiscate party B by invalid status in ISOLATED BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			// expect(await context.clearingHouse.connect(context.signers.clearingHouse).liquidateIsolatedPartyB(
			// 	partyB2.address,
			// 	context.collateral.getAddress(),
			// 	e(-1200000),
			// 	e(10)
			// )).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

			// await expect((await context.viewFacet.getLiquidationDetail(liquidationId)).status).to.be.equal(LiquidationStatus.IN_PROGRESS)
			//
			await expect(
				context.clearingHouse
					.connect(context.signers.clearingHouse)
					.confiscate(liquidationId, e(10000), partyB2.address, partyA2.address, MarginType.ISOLATED),
			).to.be.revertedWithCustomError(context.clearingHouse, "InvalidState")
		})

		it("Should failed when try to confiscate party B by insufficient balance in ISOLATED BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10)),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

			await expect(
				context.clearingHouse
					.connect(context.signers.clearingHouse)
					.confiscate(liquidationId, e(120000), partyB2.address, partyA2.address, MarginType.ISOLATED),
			).to.be.revertedWithCustomError(context.clearingHouse, "InsufficientIntBalance")
		})

		it("Should confiscate party B when liquidating in ISOLATED BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			const partyBBeforeIsolatedBalance = await context.viewFacet.getIsolatedBalance(partyB2.address, context.collateral.getAddress())

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10)),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

			const liquidationAmount = e(30000)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.confiscate(liquidationId, liquidationAmount, partyB2.address, partyA2.address, MarginType.ISOLATED),
			).not.reverted

			const partyBAfterIsolatedBalance = await context.viewFacet.getIsolatedBalance(partyB2.address, context.collateral.getAddress())

			await expect(partyBBeforeIsolatedBalance - partyBAfterIsolatedBalance).to.be.equal(liquidationAmount)
		})
	})

	describe("Confiscate Withdrwa", async function () {
		it("Should failed when confiscating party B withdrawal by invalid status in ISOLATED BUY", async () => {
			await partyB1.setBalances(context.collateral, e(100000), e(100000))

			await context.accountFacet
				.connect(context.signers.partyB1)
				.initiateWithdraw(context.collateral.getAddress(), e(1000), context.signers.others[0])
			const withdrawalId = 1
			await context.accountFacet.connect(partyB1.getSigner).cancelWithdraw(withdrawalId)

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).confiscateWithdrawal(withdrawalId)).to.be.revertedWithCustomError(
				context.clearingHouse,
				"InvalidState",
			)
		})

		it("Should confiscate withdrawal", async () => {
			await partyB1.setBalances(context.collateral, e(100000), e(100000))
			await context.accountFacet
				.connect(context.signers.partyB1)
				.initiateWithdraw(context.collateral.getAddress(), e(1000), context.signers.others[0])
			const partyBBeforeBalance = await context.viewFacet.getIsolatedBalance(partyB1.address, context.collateral.getAddress())
			console.log("partyBBeforeBalance", partyBBeforeBalance)
			const withdrawalId = 1
			expect(await context.clearingHouse.connect(context.signers.clearingHouse).confiscateWithdrawal(withdrawalId)).not.reverted
			const partyBAfterBalance = await context.viewFacet.getIsolatedBalance(partyB1.address, context.collateral.getAddress())
			console.log("partyBAfterBalance", partyBAfterBalance)
			expect(partyBAfterBalance - partyBBeforeBalance).to.be.equal(e(1000))
			const withdraw = await context.viewFacet.getWithdrawal(withdrawalId)
			expect(withdraw.status).to.be.equal(WithdrawStatus.CANCELED)
		})
	})

	describe("Confiscate Collateral", async function () {
		it("Should fail to distribute collateral after confiscate party B when liquidating in ISOLATED BUY because of mismatching inputs", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10)),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

			const liquidationAmount = e(30000)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.confiscate(liquidationId, liquidationAmount, partyB2.address, partyA2.address, MarginType.ISOLATED),
			).not.reverted

			await expect(
				context.clearingHouse
					.connect(context.signers.clearingHouse)
					.distributeCollateral(
						liquidationId,
						partyB2.address,
						context.collateral.getAddress(),
						MarginType.ISOLATED,
						[partyA2.address],
						[e(10000), e(20000)],
					),
			).to.be.revertedWithCustomError(context.clearingHouse, "MismatchedArrayLengths")
		})

		it("Should fail to distribute collateral after confiscate party B when liquidating in ISOLATED BUY because of invalid state", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

			await expect(
				context.clearingHouse
					.connect(context.signers.clearingHouse)
					.distributeCollateral(liquidationId, partyB2.address, context.collateral.getAddress(), MarginType.ISOLATED, [partyA2.address], [e(30000)]),
			).to.be.revertedWithCustomError(context.clearingHouse, "InvalidState")
		})

		it("Should fail to distribute collateral after confiscate party B when liquidating in ISOLATED BUY because of exceeding amount from confiscated amount", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10)),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

			const liquidationAmount = e(30000)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.confiscate(liquidationId, liquidationAmount, partyB2.address, partyA2.address, MarginType.ISOLATED),
			).not.reverted

			await expect(
				context.clearingHouse
					.connect(context.signers.clearingHouse)
					.distributeCollateral(liquidationId, partyB2.address, context.collateral.getAddress(), MarginType.ISOLATED, [partyA2.address], [e(40000)]),
			).to.be.revertedWithCustomError(context.clearingHouse, "DistributedAmountExceedsConfiscatedAmount")
		})

		it("Should distribute collateral after confiscate party B when liquidating in ISOLATED BUY", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral.getAddress())
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10)),
			).not.reverted

			const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

			const liquidationAmount = e(30000)

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.confiscate(liquidationId, liquidationAmount, partyB2.address, partyA2.address, MarginType.ISOLATED),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.distributeCollateral(
						liquidationId,
						partyB2.address,
						context.collateral.getAddress(),
						MarginType.ISOLATED,
						[partyA2.address],
						[liquidationAmount],
					),
			).not.reverted

			const partyAScheduledBalance = (
				await context.viewFacet.getScheduledReleaseEntry(partyA2.address, context.collateral.getAddress(), partyB2.address)
			).scheduled

			expect(partyAScheduledBalance).be.equal(liquidationAmount)
		})
	})

	describe("Cancel Open Intents", async function () {
		it("Should fail to cancel open intents when open intent is filled", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral.getAddress())
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId1])).to.be.revertedWithCustomError(
				context.clearingHouse,
				"InvalidState",
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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId1])).to.be.revertedWithCustomError(
				context.clearingHouse,
				"PartiesNotInLiquidation",
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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
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

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10)),
			).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId2])).not.reverted

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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))
			const tradeId1 = 1
			await partyA2.sendCloseIntent(tradeId1, e(40), e(12), (await getLatestBlockTime()) + 140)
			const closeIntentId1 = 1
			await partyB2.fillCloseIntent(closeIntentId1, e(40), e(12))

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelCloseIntents([closeIntentId1])).to.be.revertedWithCustomError(
				context.clearingHouse,
				"InvalidState",
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
				.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
				.quantity(e(50))
				.strikePrice(e(10000))
				.price(e(10))
				.mm(0)
				.tradeSide(TradeSide.BUY)
				.marginType(MarginType.ISOLATED)
				.build()

			const openIntentId1 = 1
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))
			const tradeId1 = 1
			await partyA2.sendCloseIntent(tradeId1, e(40), e(12), (await getLatestBlockTime()) + 140)
			const closeIntentId1 = 1

			await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelCloseIntents([closeIntentId1])).to.be.revertedWithCustomError(
				context.clearingHouse,
				"PartiesNotInLiquidation",
			)
		})
	})

	describe("Cancel Open Intents", async function () {
		it("Should cancel close intents", async () => {
			const request1 = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral.getAddress())
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
			await partyA2.setBalances(context.collateral, e(10000), e(1000))
			await partyA2.sendOpenIntent(request1)
			await partyB2.lockOpenIntent(openIntentId1)
			await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))
			const tradeId1 = 1
			await partyA2.sendCloseIntent(tradeId1, e(40), e(12), (await getLatestBlockTime()) + 2000)
			const closeIntentId1 = 1

			// TODO: if the contract changed to one-time setting config this transaction should be removed
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.getSigner.getAddress(), context.collateral.getAddress()),
			).not.reverted

			expect(
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10)),
			).not.reverted

			expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelCloseIntents([closeIntentId1])).not.reverted

			expect((await context.viewFacet.getCloseIntent(closeIntentId1)).status).to.be.equal(CloseIntentStatus.CANCELED)
		})
	})
}
