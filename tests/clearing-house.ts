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
import { getLatestBlockTime, moveTime } from "../utils/time"
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
import { ContractEventPayload, ZeroAddress, parseUnits } from "ethers"
import { clearingHouse, view } from "../types/contracts/facets"
import { configure, exceptions } from "winston"
import { Console } from "console"
import { Context } from "mocha"
import { ScheduledReleaseEntryStruct } from "../types/contracts/facets/View/ViewFacet"
import { bigint } from "hardhat/internal/core/params/argumentTypes"
import { LibAccessibility } from "../types"
import { lstat } from "fs"

export function shouldBehaveLikeClearingHouseFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB
	let formatter: Intl.NumberFormat

	describe("Clearing House", async function () {
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

		async function makePartyInLiquidationIsolated() {
			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: e(1),
				oracleId: 1,
			})
			await context.clearingHouse
				.connect(context.signers.clearingHouse)
				.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress())

			await context.clearingHouse
				.connect(context.signers.clearingHouse)
				.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10))
		}

		describe("Isolated BUY liquidation", async function () {
			it("Should be failed when Globally Paused", async () => {
				// Globally Pause the System
				await context.controlFacet.pauseGlobal()
				// Checking all 3 flagging functions when paused
				await expect(
					context.clearingHouse.flagIsolatedPartyBLiquidation(partyB1.address, context.collateral.getAddress()),
				).to.be.revertedWithCustomError(context.clearingHouse, "GlobalPaused")
				await expect(
					context.clearingHouse.flagCrossPartyBLiquidation(partyB1.address, partyA1.address, context.collateral.getAddress()),
				).to.be.revertedWithCustomError(context.clearingHouse, "GlobalPaused")
				await expect(
					context.clearingHouse.flagPartyALiquidation(partyA1.address, partyB1.address, context.collateral.getAddress()),
				).to.be.revertedWithCustomError(context.clearingHouse, "GlobalPaused")
			})

			it("Should failed when Liquidating Paused", async () => {
				// Pause the liquidating system
				await context.controlFacet.pauseLiquidating()
				// Checking all 3 flagging functions when paused
				await expect(
					context.clearingHouse.flagIsolatedPartyBLiquidation(partyB1.address, context.collateral.getAddress()),
				).to.be.revertedWithCustomError(context.clearingHouse, "LiquidatingPaused")
				await expect(
					context.clearingHouse.flagCrossPartyBLiquidation(partyB1.address, partyA1.address, context.collateral.getAddress()),
				).to.be.revertedWithCustomError(context.clearingHouse, "LiquidatingPaused")
				await expect(
					context.clearingHouse.flagPartyALiquidation(partyA1.address, partyB1.address, context.collateral.getAddress()),
				).to.be.revertedWithCustomError(context.clearingHouse, "LiquidatingPaused")
			})

			it("Should failed when the sender does not have CLEARING_HOUSE role", async () => {
				// Checking all 3 flagging functions when paused
				await expect(
					context.clearingHouse.connect(context.signers.others[0]).flagIsolatedPartyBLiquidation(partyB1.address, context.collateral.getAddress()),
				).to.be.revertedWithCustomError(context.clearingHouse, "MissingRole")
				await expect(
					context.clearingHouse
						.connect(context.signers.others[0])
						.flagCrossPartyBLiquidation(partyB1.address, partyA1.address, context.collateral.getAddress()),
				).to.be.revertedWithCustomError(context.clearingHouse, "MissingRole")
				await expect(
					context.clearingHouse
						.connect(context.signers.others[0])
						.flagPartyALiquidation(partyA1.address, partyB1.address, context.collateral.getAddress()),
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
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.flagIsolatedPartyBLiquidation(partyB1.address, context.collateral.getAddress()),
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
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
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
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
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
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
				).not.reverted

				let liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())
				console.log("Liquidation Flag:", liquidationId)

				expect(
					await context.clearingHouse
						.connect(context.signers.clearingHouse)
						.unflagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
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
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
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
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
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

				expect(
					await context.viewFacet.getInProgressLiquidationId(partyA2.address, partyB2.address, await context.collateral.getAddress()),
				).to.be.equal(0)
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

				console.log("Party A Cross Balance Before Liquidation:", partyABeforeCrossBalance)
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
					.symbolId(2) // Call Option
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
				// No Allocation
				// await context.accountFacet.connect(partyB2.getSigner).allocate(context.collateral.getAddress(), partyA2.address, e(1000))
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

				console.log("Party A Cross Balance Before Liquidation:", partyABeforeCrossBalance)
				console.log("Party A Cross Balance After Liquidation:", partyAAfterCrossBalance)
				console.log("Party A Cross Balance After Liquidation:", partyAAfterCrossBalance.balance.toLocaleString("en-US"))
				console.log("Party A Cross Balance Diff:", formatter.format(partyAAfterCrossBalance.balance - partyABeforeCrossBalance.balance))
				console.log("Party B Cross Balance Before Liquidation:", partyBBalance)
				console.log("Party B Cross Balance After Liquidation:", partyBAfterCrossBalance)

				//TODO simulate the balance of PartyB to be Zero or less
				expect(partyAAfterCrossBalance.balance - partyABeforeCrossBalance.balance).to.be.equal(0)
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
					lossCoverage: e(0.5),
					oracleId: 1,
				})

				await partyB2.setBalances(context.collateral, e(100000), e(1000))
				await context.accountFacet.connect(partyB2.getSigner).allocate(context.collateral.getAddress(), partyA2.address, e(1000))

				expect(
					await context.clearingHouse
						.connect(context.signers.clearingHouse)
						.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress()),
				).not.reverted

				let liquidationId = await context.viewFacet.getInProgressLiquidationId(
					partyA2.address,
					partyB2.address,
					await context.collateral.getAddress(),
				)
				let detail: LiquidationDetailStruct = await context.viewFacet.getLiquidationDetail(liquidationId)
				expect(detail.status).to.equal(LiquidationStatus.FLAGGED)

				const upnl = e(-20010)
				const collateralPrice = e(10) //
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
				let partyABalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
				console.log("Party A Cross Balance Before Deposit:\n", partyABalance)
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId1)
				await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

				const partyBBeforeCrossBalance = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral.getAddress(), partyA2.address)

				partyABalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
				console.log("Party A Cross Balance Before New Deposit:\n", partyABalance) // only the Premium from Party B

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

				console.log("Party B Cross Balance Before Party A Liquidation:\n", partyBBeforeCrossBalance)
				console.log("Party B Cross Balance After Party A Liquidation:\n", partyBAfterCrossBalance)
				expect(partyBAfterCrossBalance.balance - partyBBeforeCrossBalance.balance).to.be.equal(partyABalance.balance)
				expect(partyAAfterCrossBalance.balance).to.be.equal(0)
				expect(partyAAfterCrossBalance.locked).to.be.equal(0)
				expect(partyAAfterCrossBalance.totalMM).to.be.equal(partyABalance.totalMM)
			})

			it("Should liquidate when liquidating party A with CROSS SELL, State Updates", async () => {
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
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
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
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
				).not.reverted

				// In Flaged State
				const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

				await expect(
					context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [1], [e(30000)]),
				).to.be.revertedWithCustomError(context.clearingHouse, "InvalidState")
			})

			it("Should closed when closing after liquidating party B with ISOLATED BUY, with Trade State Updated", async () => {
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
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
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

			it("Should be on closing after liquidating party B with Isolated BUY, with Balances Updated", async () => {
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
				await partyB2.setBalances(context.collateral, e(10000), e(1000))
				// await context.accountFacet.connect(partyB2.getSigner).allocate(context.collateral.getAddress(), partyA2.address, e(10000))
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
				const proportionalPremium = (tradePremium * getTradeOpenAmount) / trade.tradeAgreements.quantity
				const partyBBalanceBefore = await context.viewFacet.getIsolatedBalance(partyB2.address, context.collateral)

				const price = [e(30000)]
				expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [tradeID], price)).not.reverted
				expect((await context.viewFacet.getTrade(tradeID)).status).to.be.equal(TradeStatus.LIQUIDATED)

				// const nextTime = (await getLatestBlockTime()) + 50
				// await moveTime(nextTime)
				// await context.accountFacet.syncBalances(context.collateral, partyA2.address, [partyB2.address])

				const partyBBalanceAfter = await context.viewFacet.getIsolatedBalance(partyB2.address, context.collateral)
				const PartyBBalaceDiff = partyBBalanceAfter - partyBBalanceBefore
				console.log("Party B Balance Before:", partyBBalanceBefore)
				console.log("Party B Balance After:", partyBBalanceAfter)
				console.log("Party B Balance Diff:", PartyBBalaceDiff)

				console.log("Premium Payed to Party B in Isolated Margin:", proportionalPremium)
				expect(PartyBBalaceDiff).to.equal(proportionalPremium)
			})

			it("Should closed when closing after liquidating party B with CROSS BUY", async () => {
				const openIntentCount = 2n
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
				await partyB2.setBalances(context.collateral, e(10000), e(3000))
				await context.accountFacet.connect(partyB2.getSigner).allocate(context.collateral.getAddress(), partyA2.address, e(3000))
				const partyBBalanceInit = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)
				console.log("Party B Balance Init:", partyBBalanceInit)

				for (let i = 0; i < openIntentCount; i++) await partyA2.sendOpenIntent(request1)

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
						.liquidateCrossPartyB(partyB2.address, partyA2.address, context.collateral.getAddress(), e(-120000), e(10)),
				).not.reverted

				const liquidationId = await context.viewFacet.getInProgressLiquidationId(
					partyA2.address,
					partyB2.address,
					await context.collateral.getAddress(),
				)

				const getTradeOpenAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
				const tradePremium = await context.viewFacet.getTradePremium(tradeID)
				const proportionalPremium = (tradePremium * getTradeOpenAmount) / trade.tradeAgreements.quantity
				const partyBBalanceBefore = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)

				const price = [e(30000)]
				expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [tradeID], price)).not.reverted
				expect((await context.viewFacet.getTrade(tradeID)).status).to.be.equal(TradeStatus.LIQUIDATED)

				const partyBBalanceAfter = await context.viewFacet.getCrossBalance(partyB2.address, context.collateral, partyA2.address)
				const PartyBBalaceDiff = partyBBalanceAfter.balance - partyBBalanceBefore.balance
				console.log("Party B Balance Before:", partyBBalanceBefore)
				console.log("Party B Balance After:", partyBBalanceAfter)
				console.log("Party B Balance Diff:", PartyBBalaceDiff)

				console.log("Premium Payed to Party A in Isolated Margin:", proportionalPremium)
				expect(PartyBBalaceDiff).to.equal(proportionalPremium)
			})

			it("Should closed when closing after liquidating party B with CROSS SELL, with Updated Close Intents Status", async () => {
				const mm = e(1000)
				const balance = e(1000)
				const closeIntentLen = 3

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
					.mm(mm)
					.tradeSide(TradeSide.SELL)
					.marginType(MarginType.CROSS)
					.build()

				const openIntentId1 = 1
				await partyA2.setBalances(context.collateral, e(10000), balance + mm)
				await context.accountFacet.connect(partyA2.getSigner).allocate(context.collateral.getAddress(), partyB2.address, balance)
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId1)
				await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

				const tradeID = await context.viewFacet.getLastTradeId()

				//Close Intents
				for (let i = 0; i < closeIntentLen; i++) await partyA2.sendCloseIntent(tradeID, e(10), e(10), (await getLatestBlockTime()) + 100)

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

				await moveTime(100)

				const price = [e(30000)]
				expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [tradeID], price)).not.reverted

				const currentBlockTime = await getLatestBlockTime()
				const closeIntentsIDs = await context.viewFacet.getCloseIntentIds(tradeID)
				expect(closeIntentsIDs.length).equal(closeIntentLen)
				for (let i = 0; i < closeIntentsIDs.length; i++) {
					let closeIntent = await context.viewFacet.getCloseIntent(closeIntentsIDs[i])
					expect(closeIntent.status).to.be.equal(CloseIntentStatus.CANCELED)
					expect(closeIntent.statusModifyTimestamp).to.be.approximately(currentBlockTime, 5)
				}
			})

			it("Should closed when closing after liquidating party B with CROSS SELL, Trade Status", async () => {
				const mm = e(1000)
				const balance = e(1000)
				const closeIntentLen = 3

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
					.mm(mm)
					.tradeSide(TradeSide.SELL)
					.marginType(MarginType.CROSS)
					.build()

				const openIntentId1 = 1
				await partyA2.setBalances(context.collateral, e(10000), balance + mm)
				await context.accountFacet.connect(partyA2.getSigner).allocate(context.collateral.getAddress(), partyB2.address, balance)
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId1)
				await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

				const tradeID = await context.viewFacet.getLastTradeId()

				//Close Intents
				for (let i = 0; i < closeIntentLen; i++) await partyA2.sendCloseIntent(tradeID, e(10), e(10), (await getLatestBlockTime()) + 100)

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

				const tradeBefore = await context.viewFacet.getTrade(tradeID)

				const price = [e(30000)]
				expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [tradeID], price)).not.reverted

				const trade: TradeStruct = await context.viewFacet.getTrade(tradeID)
				expect(tradeBefore.activeCloseIntentIds.length).equal(closeIntentLen)
				expect(trade.status).to.be.equal(TradeStatus.LIQUIDATED)
				expect(trade.settledPrice).to.equal(price[0])
				expect(trade.closePendingAmount).equal(0)
				expect(trade.activeCloseIntentIds.length).equal(0)
			})

			it("Should be when closing after liquidating party B with CROSS SELL, Balances", async () => {
				const mm = e(1000)
				const balance = e(1000)
				const openIntentCount = 2n

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
					.mm(mm)
					.tradeSide(TradeSide.SELL)
					.marginType(MarginType.CROSS)
					.build()

				const openIntentId1 = 1
				await partyA2.setBalances(context.collateral, e(10000), mm + balance)

				// NOTE
				// no Need to allocate as Premium is fetched when Filled in Party A selling Option
				// await context.accountFacet.connect(partyA2.getSigner).allocate(context.collateral.getAddress(), partyB2.address, balance)

				for (let i = 0; i < openIntentCount; i++) await partyA2.sendOpenIntent(request1)

				await partyB2.lockOpenIntent(openIntentId1)
				await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

				const tradeID = await context.viewFacet.getLastTradeId()
				const trade = await context.viewFacet.getTrade(tradeID)

				const partyABalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
				console.log("Party A Cross Balance After Fill:", partyABalance)

				await partyA2.sendCloseIntent(tradeID, e(10), e(10), (await getLatestBlockTime()) + 100)
				await partyB2.fillCloseIntent(await context.viewFacet.getLastCloseIntentId(), e(10), e(10))

				const partyABalance2 = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
				console.log("Party A Cross Balance After Fill Close:", partyABalance2)

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

				const tradeOpenAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
				const tradeMM = await context.viewFacet.getTradeMM(tradeID, tradeOpenAmount)
				// const proportionalPremium = (tradePremium * tradeOpenAmount) / trade.tradeAgreements.quantity
				const partyABalanceBefore = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)

				console.log("Party A MM:", tradeMM)
				const price = [e(30000)]
				expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [tradeID], price)).not.reverted

				const partyABalanceAfter = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
				const PartyBBalaceDiff = partyABalanceBefore.totalMM - partyABalanceAfter.totalMM

				console.log("Party A Balance After Liquidation:", partyABalanceBefore)
				console.log("Party A Balance After CLoseing TRADES:", partyABalanceAfter)
				expect(PartyBBalaceDiff).to.equal(tradeMM)
			})

			it("Should be when closing after liquidating party B with CROSS SELL, Balances", async () => {
				const mm = e(1000)
				const balance = e(1000)
				const openIntentCount = 2n

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
					.mm(mm)
					.tradeSide(TradeSide.SELL)
					.marginType(MarginType.CROSS)
					.build()

				const openIntentId1 = 1
				await partyA2.setBalances(context.collateral, e(10000), mm + balance)

				// NOTE
				// no Need to allocate as Premium is fetched when Filled in Party A selling Option
				// await context.accountFacet.connect(partyA2.getSigner).allocate(context.collateral.getAddress(), partyB2.address, balance)

				for (let i = 0; i < openIntentCount; i++) await partyA2.sendOpenIntent(request1)

				await partyB2.lockOpenIntent(openIntentId1)
				await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

				const tradeID = await context.viewFacet.getLastTradeId()
				const trade = await context.viewFacet.getTrade(tradeID)

				const partyABalance = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
				console.log("Party A Cross Balance After Fill:", partyABalance)

				await partyA2.sendCloseIntent(tradeID, e(10), e(10), (await getLatestBlockTime()) + 100)
				await partyB2.fillCloseIntent(await context.viewFacet.getLastCloseIntentId(), e(10), e(10))

				const partyABalance2 = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
				console.log("Party A Cross Balance After Fill Close:", partyABalance2)

				// NOTE
				// No way to Deallocate
				// await context.accountFacet.connect(partyA2.getSigner).deallocate(context.collateral,partyB2.address,party)
				// TODO how to deallocate

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

				const tradeOpenAmount = await context.viewFacet.getTradeOpenAmount(tradeID)
				const tradeMM = await context.viewFacet.getTradeMM(tradeID, tradeOpenAmount)
				// const proportionalPremium = (tradePremium * tradeOpenAmount) / trade.tradeAgreements.quantity
				const partyABalanceBefore = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)

				console.log("Party A MM:", tradeMM)
				const price = [e(30000)]
				expect(await context.clearingHouse.connect(context.signers.clearingHouse).closeTrades(liquidationId, [tradeID], price)).not.reverted

				const partyABalanceAfter = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral, partyB2.address)
				const PartyBBalaceDiff = partyABalanceBefore.totalMM - partyABalanceAfter.totalMM

				console.log("Party A Balance After Liquidation:", partyABalanceBefore)
				console.log("Party A Balance After CLoseing TRADES:", partyABalanceAfter)
				expect(PartyBBalaceDiff).to.equal(tradeMM)
			})
		})

		describe("Allocating From Reserve", async function () {
			it("Should failed when allocating from reserve balance has insufficient balance ", async () => {
				await expect(
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.allocateFromReserveToCross(partyA2.address, partyB2.address, context.collateral.getAddress(), e(10000)),
				).to.be.revertedWithCustomError(context.clearingHouse, "InsufficientBalance")
			})

			it("Should allocate from reserve balance into cross balance, Decrease from Reserve", async () => {
				const amountToDeposit = e(1000)
				await partyB2.setBalances(context.collateral, amountToDeposit, amountToDeposit)
				await context.accountFacet.connect(context.signers.partyB2).allocateToReserveBalance(context.collateral.getAddress(), amountToDeposit)
				const partyBBeforeReserveBalance = await context.viewFacet.getReserveBalance(partyB2.address, context.collateral.getAddress())
				const partyBBeforeCrossBalance = (await context.viewFacet.getCrossBalance(partyB2.address, context.collateral.getAddress(), partyA2.address))
					.balance

				const amountToAllocate = e(1000)
				expect(
					await context.clearingHouse
						.connect(context.signers.clearingHouse)
						.allocateFromReserveToCross(partyB2.address, partyA2.address, context.collateral.getAddress(), amountToDeposit),
				).not.reverted

				const partyBAfterReserveBalance = await context.viewFacet.getReserveBalance(partyB2.address, context.collateral.getAddress())

				const partyBAfterCrossBalance = (await context.viewFacet.getCrossBalance(partyB2.address, context.collateral.getAddress(), partyA2.address))
					.balance

				expect(partyBBeforeReserveBalance - partyBAfterReserveBalance).to.equal(amountToDeposit)
			})

			it("Should allocate from reserve balance into cross balance, Increase Cross Balnace", async () => {
				const amountToDeposit = e(1000)
				await partyB2.setBalances(context.collateral, amountToDeposit, amountToDeposit)
				await context.accountFacet.connect(context.signers.partyB2).allocateToReserveBalance(context.collateral.getAddress(), amountToDeposit)
				const partyBBeforeReserveBalance = await context.viewFacet.getReserveBalance(partyB2.address, context.collateral.getAddress())
				const partyBBeforeCrossBalance = (await context.viewFacet.getCrossBalance(partyB2.address, context.collateral.getAddress(), partyA2.address))
					.balance

				const amountToAllocate = e(1000)
				expect(
					await context.clearingHouse
						.connect(context.signers.clearingHouse)
						.allocateFromReserveToCross(partyB2.address, partyA2.address, context.collateral.getAddress(), amountToDeposit),
				).not.reverted

				const partyBAfterReserveBalance = await context.viewFacet.getReserveBalance(partyB2.address, context.collateral.getAddress())

				const partyBAfterCrossBalance = (await context.viewFacet.getCrossBalance(partyB2.address, context.collateral.getAddress(), partyA2.address))
					.balance

				expect(partyBAfterCrossBalance - partyBBeforeCrossBalance).to.equal(amountToAllocate)
			})
		})

		describe("Distribute Collateral", async function () {
			it("Should revert distributeCollateral when LiquidatingPaused, then succeed after unpause", async () => {
				// minimal setup to IN_PROGRESS (flag + liquidate)
				const req = openIntentRequestBuilder()
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

				await partyA2.setBalances(context.collateral, e(10000), e(1000))
				await partyB2.setBalances(context.collateral, e(10000), e(1000))
				await partyA2.sendOpenIntent(req)
				await partyB2.lockOpenIntent(1)
				await partyB2.fillOpenIntent(1, e(50), e(10))

				await context.controlFacet.setPartyBConfig(context.signers.partyB2, { isActive: true, lossCoverage: e(1), oracleId: 1 })

				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress())
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10))

				const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.confiscate(liquidationId, partyB2.address, [partyA2.address], [e(10)], MarginType.ISOLATED)

				await context.controlFacet.pauseLiquidating()
				await expect(
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.distributeCollateral(liquidationId, partyB2.address, context.collateral, MarginType.ISOLATED, [partyA2.address], [e(10)]),
				).to.be.revertedWithCustomError(context.clearingHouse, "LiquidatingPaused")

				await context.controlFacet.unpauseLiquidating()
				await expect(
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.distributeCollateral(liquidationId, partyB2.address, context.collateral, MarginType.ISOLATED, [partyA2.address], [e(10)]),
				).not.reverted
			})

			it("Should enforce onlyRole(CLEARING_HOUSE_ROLE) on distributeCollateral", async () => {
				// minimal setup to IN_PROGRESS (flag + liquidate)
				const req = openIntentRequestBuilder()
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

				await partyA2.setBalances(context.collateral, e(10000), e(1000))
				await partyB2.setBalances(context.collateral, e(10000), e(1000))
				await partyA2.sendOpenIntent(req)
				await partyB2.lockOpenIntent(1)
				await partyB2.fillOpenIntent(1, e(50), e(10))

				await context.controlFacet.setPartyBConfig(context.signers.partyB2, { isActive: true, lossCoverage: e(1), oracleId: 1 })

				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress())
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10))

				const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

				// make minimal confiscation so distribution won’t hit the over-distribution check
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.confiscate(liquidationId, partyB2.address, [partyA2.address], [e(10)], MarginType.ISOLATED)

				const unauthorized = context.signers.affiliate1
				await expect(
					context.clearingHouse
						.connect(unauthorized)
						.distributeCollateral(liquidationId, partyB2.address, context.collateral, MarginType.ISOLATED, [partyA2.address], [e(10)]),
				).to.be.reverted // tighten with AccessControl error if exposed on this facet
			})

			it("Should failed when Partys list Length different from Amounts list length ", async () => {
				const liquidationId = await context.viewFacet.getInProgressLiquidationId(
					partyA2.address,
					partyB2.address,
					await context.collateral.getAddress(),
				)

				await expect(
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.distributeCollateral(
							liquidationId,
							partyB2.address,
							context.collateral,
							MarginType.ISOLATED,
							[partyA1.address, partyA2.address],
							[e(10), e(10), e(10)],
						),
				).to.be.revertedWithCustomError(context.clearingHouse, "MismatchedArrayLengths")
			})

			it("Should Fail to Distribute when Party B is Not in Liquidation State", async () => {
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
				await partyB2.setBalances(context.collateral, e(10000), e(1000))

				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId1)
				await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

				const tradeID = await context.viewFacet.getLastTradeId()
				const trade = await context.viewFacet.getTrade(tradeID)

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

				const liquidationId = await context.viewFacet.getInProgressLiquidationId(
					partyA2.address,
					partyB2.address,
					await context.collateral.getAddress(),
				)

				await expect(
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.distributeCollateral(
							liquidationId,
							partyB2.address,
							context.collateral,
							MarginType.ISOLATED,
							[partyA1.address, partyA2.address],
							[e(10), e(10)],
						),
				).to.be.revertedWithCustomError(context.clearingHouse, "InvalidState")
			})

			it("Should Distribute when Party B is in Liquidation State", async () => {
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
				const partyBBalance = e(1000)
				await partyA2.setBalances(context.collateral, e(10000), e(1000))
				await partyB2.setBalances(context.collateral, e(10000), partyBBalance)

				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId1)
				await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

				const tradeID = await context.viewFacet.getLastTradeId()
				const trade = await context.viewFacet.getTrade(tradeID)

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

				const distributionParties = [partyA1.address, partyA2.address]
				const distributionAmounts: bigint[] = [e(10), e(10)]

				// First Confiscate
				const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())
				const detailBefore = await context.viewFacet.getLiquidationDetail(liquidationId)
				console.log("Detail Structure Confiscated Amount Before:", detailBefore.confiscatedAmount)
				expect(detailBefore.status).to.equal(LiquidationStatus.IN_PROGRESS)

				let confiscateAmount: bigint[] = []
				for (let i = 0; i < distributionAmounts.length; i++) confiscateAmount[i] = distributionAmounts[i]
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.confiscate(liquidationId, partyB2.address, [partyA1.address, partyA2.address], confiscateAmount, MarginType.ISOLATED)

				const detailAfter = await context.viewFacet.getLiquidationDetail(liquidationId)
				console.log("Detail Structure Confiscated Amount After:", detailAfter.confiscatedAmount)

				let schedEntriesBefore: ScheduledReleaseEntryStruct[] = []
				let schedEntriesAfter: ScheduledReleaseEntryStruct[] = []
				for (let i = 0; i < distributionParties.length; i++) {
					schedEntriesBefore[i] = await context.viewFacet.getScheduledReleaseEntry(
						distributionParties[i],
						context.collateral.getAddress(),
						partyB2.address,
					)
					console.log("Scheduled Entry", i, ":", schedEntriesBefore[i])
				}

				await expect(
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.distributeCollateral(
							liquidationId,
							partyB2.address,
							context.collateral.getAddress(),
							MarginType.ISOLATED,
							distributionParties,
							distributionAmounts,
						),
				).not.to.be.reverted

				////////////// Note ////////////////////////////////////////////////
				//No effect as therer PartyB is not SOLVENT
				await moveTime(50)
				for (let i = 0; i < distributionParties.length; i++)
					await context.accountFacet.syncBalances(context.collateral.getAddress(), distributionParties[i], [partyB2.address])
				///////////////////////////////////////////////////////

				for (let i = 0; i < distributionParties.length; i++) {
					schedEntriesAfter[i] = await context.viewFacet.getScheduledReleaseEntry(
						distributionParties[i],
						context.collateral.getAddress(),
						partyB2.address,
					)
					console.log("Scheduled Entry", i, ":", schedEntriesAfter[i])
				}

				for (let i = 0; i < distributionParties.length; i++) {
					expect(BigInt(schedEntriesAfter[i].scheduled) - BigInt(schedEntriesBefore[i].scheduled)).to.equal(distributionAmounts[i])
				}
			})

			it("Should revert when distributedAmount exceeds confiscatedAmount", async () => {
				// minimal setup to IN_PROGRESS (flag + liquidate)
				const req = openIntentRequestBuilder()
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

				await partyA2.setBalances(context.collateral, e(10000), e(1000))
				await partyB2.setBalances(context.collateral, e(10000), e(1000))
				await partyA2.sendOpenIntent(req)
				await partyB2.lockOpenIntent(1)
				await partyB2.fillOpenIntent(1, e(50), e(10))

				await context.controlFacet.setPartyBConfig(context.signers.partyB2, { isActive: true, lossCoverage: e(1), oracleId: 1 })

				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress())
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10))

				const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

				// try to distribute without prior confiscation -> exceeds
				await expect(
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.distributeCollateral(
							liquidationId,
							partyB2.address,
							context.collateral,
							MarginType.ISOLATED,
							[partyA1.address, partyA2.address],
							[e(10), e(10)],
						),
				).to.be.revertedWithCustomError(context.clearingHouse, "DistributedAmountExceedsConfiscatedAmount")
			})
		})

		describe("Confiscation", async function () {
			it("Should revert confiscate when GlobalPaused, then succeed after unpause", async () => {
				// ----- set up a valid liquidation (your standard flow) -----
				const request = openIntentRequestBuilder()
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

				const openIntentId = 1
				await partyA2.setBalances(context.collateral, e(10000), e(1000))
				await partyB2.setBalances(context.collateral, e(10000), e(10000))
				await partyA2.sendOpenIntent(request)
				await partyB2.lockOpenIntent(openIntentId)
				await partyB2.fillOpenIntent(openIntentId, e(50), e(10))

				await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
					isActive: true,
					lossCoverage: e(1),
					oracleId: 1,
				})

				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress())

				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10))

				const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

				const cps = [partyA1.address, partyA2.address]
				const amts = [e(400), e(600)]

				// ----- pause globally and expect GlobalPaused on confiscate -----
				await context.controlFacet.pauseGlobal() // default signer assumed to hold PAUSER_ROLE in your rig

				await expect(
					context.clearingHouse.connect(context.signers.clearingHouse).confiscate(liquidationId, partyB2.address, cps, amts, MarginType.ISOLATED),
				).to.be.revertedWithCustomError(context.clearingHouse, "GlobalPaused")

				// unpause and confirm succeeds
				await context.controlFacet.unpauseGlobal() // default signer assumed to have UNPAUSER_ROLE
				await expect(
					context.clearingHouse.connect(context.signers.clearingHouse).confiscate(liquidationId, partyB2.address, cps, amts, MarginType.ISOLATED),
				).not.reverted
			})

			it("Should revert confiscate when LiquidatingPaused, then succeed after unpause", async () => {
				// quick setup (same pattern, less comments)
				const request = openIntentRequestBuilder()
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

				const openIntentId = 1
				await partyA2.setBalances(context.collateral, e(10000), e(1000))
				await partyB2.setBalances(context.collateral, e(10000), e(10000))
				await partyA2.sendOpenIntent(request)
				await partyB2.lockOpenIntent(openIntentId)
				await partyB2.fillOpenIntent(openIntentId, e(50), e(10))

				await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
					isActive: true,
					lossCoverage: e(1),
					oracleId: 1,
				})

				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress())

				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10))

				const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

				const cps = [partyA1.address, partyA2.address]
				const amts = [e(500), e(700)]

				// liquidating pause should block confiscate via whenNotLiquidationPaused
				await context.controlFacet.pauseLiquidating()

				await expect(
					context.clearingHouse.connect(context.signers.clearingHouse).confiscate(liquidationId, partyB2.address, cps, amts, MarginType.ISOLATED),
				).to.be.revertedWithCustomError(context.clearingHouse, "LiquidatingPaused")

				// unpause and then it should work
				await context.controlFacet.unpauseLiquidating()
				await expect(
					context.clearingHouse.connect(context.signers.clearingHouse).confiscate(liquidationId, partyB2.address, cps, amts, MarginType.ISOLATED),
				).not.reverted
			})

			it("Should enforce onlyRole(CLEARING_HOUSE_ROLE) on confiscate (unauthorized reverts, authorized succeeds)", async () => {
				// Build a valid ISOLATED BUY flow so any revert we see is from AccessControl, not business logic.
				const request = openIntentRequestBuilder()
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

				const openIntentId = 1n
				const partyBBalance = e(10000)

				await partyA2.setBalances(context.collateral, e(10000), e(1000))
				await partyB2.setBalances(context.collateral, partyBBalance, partyBBalance)

				await partyA2.sendOpenIntent(request)
				await partyB2.lockOpenIntent(Number(openIntentId))
				await partyB2.fillOpenIntent(Number(openIntentId), e(50), e(10))

				await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
					isActive: true,
					lossCoverage: e(1),
					oracleId: 1,
				})

				// Move to liquidation state
				await expect(
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
				).not.reverted

				await expect(
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10)),
				).not.reverted

				const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

				const counterParties = [partyA1.address, partyA2.address]
				const amounts = [e(500), e(700)] // well within seeded balances

				// ---- unauthorized caller should revert with AccessControl ----
				const unauthorized = context.signers.affiliate1 // pick any signer without the role
				const role = ethers.id("CLEARING_HOUSE_ROLE") // keccak256("CLEARING_HOUSE_ROLE") (ethers v6)

				console.log("Cleating House Role:", role)
				await expect(
					context.clearingHouse.connect(unauthorized).confiscate(liquidationId, partyB2.address, counterParties, amounts, MarginType.ISOLATED),
				)
					.to.be.revertedWithCustomError(context.clearingHouse, "MissingRole")
					.withArgs(await unauthorized.getAddress(), role)

				// ---- authorized caller (has CLEARING_HOUSE_ROLE) succeeds ----
				await expect(
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.confiscate(liquidationId, partyB2.address, counterParties, amounts, MarginType.ISOLATED),
				).not.reverted
			})

			it("Should fail on mismatched counterparties/amounts length in ISOLATED BUY", async () => {
				const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

				// MISMATCH: 2 counterparties, 1 amount
				await expect(
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.confiscate(liquidationId, partyB2.address, [partyA1.address, partyA2.address], [e(1000)], MarginType.ISOLATED),
				).to.be.revertedWithCustomError(context.clearingHouse, "MismatchedArrayLengths")
			})

			it("Should fail when party is not part of the liquidation (PartyNotInLiquidation)", async () => {
				const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

				// Here we deliberately pass a `party` that is NOT partyA2 nor partyB2 in this liquidation.
				await expect(
					context.clearingHouse.connect(context.signers.clearingHouse).confiscate(
						liquidationId,
						partyA1.address, // wrong party for this liquidation
						[partyA2.address],
						[e(100)],
						MarginType.ISOLATED,
					),
				).to.be.revertedWithCustomError(context.clearingHouse, "PartyNotInLiquidation")
			})

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
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
				).not.reverted

				const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

				await expect(
					context.clearingHouse
						.connect(context.signers.clearingHouse)
						.confiscate(liquidationId, partyB2.address, [partyA2.address], [e(10000)], MarginType.ISOLATED),
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
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
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
						.confiscate(liquidationId, partyB2.address, [partyA2.address], [e(120000)], MarginType.ISOLATED),
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

				const partyBInitialBalance = e(10000)
				const openIntentId1 = 1
				await partyA2.setBalances(context.collateral, e(10000), e(1000))
				await partyB2.setBalances(context.collateral, partyBInitialBalance, partyBInitialBalance)
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
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
				).not.reverted

				expect(
					await context.clearingHouse
						.connect(context.signers.clearingHouse)
						.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10)),
				).not.reverted

				const liquidationId = await context.viewFacet.getInProgressLiquidationId(ZeroAddress, partyB2.address, await context.collateral.getAddress())

				const liquidationAmounts = [e(1000), e(1000)]
				const counterParties = [partyA1.address, partyA2.address]
				expect(
					await context.clearingHouse
						.connect(context.signers.clearingHouse)
						.confiscate(liquidationId, partyB2.address, counterParties, liquidationAmounts, MarginType.ISOLATED),
				).not.reverted

				let totalAmount = 0n
				let partyBAfterIsolatedBalance = await context.viewFacet.getIsolatedBalance(partyB2.address, context.collateral.getAddress())
				for (let i = 0; i < liquidationAmounts.length; i++) totalAmount += liquidationAmounts[i]
				expect(partyBBeforeIsolatedBalance - partyBAfterIsolatedBalance).to.be.equal(totalAmount)
			})
		})

		describe("Confiscate Withdrawal", async function () {
			it("Should revert when unauthorized caller (missing CLEARING_HOUSE_ROLE)", async () => {
				const withdrawalId = await context.viewFacet.getLastWithdrawalId()

				const role = ethers.id("CLEARING_HOUSE_ROLE")
				const unauthorized = context.signers.affiliate1 // any account without the role
				await expect(context.clearingHouse.connect(unauthorized).confiscateWithdrawal(withdrawalId))
					.to.be.revertedWithCustomError(context.clearingHouse, "MissingRole")
					.withArgs(await unauthorized.getAddress(), role)
			})

			it("Should revert when GlobalPaused, then succeed after unpause", async () => {
				await partyB1.setBalances(context.collateral, e(100000), e(100000))
				await context.accountFacet
					.connect(context.signers.partyB1)
					.initiateWithdraw(context.collateral.getAddress(), e(1000), context.signers.others[0])

				const withdrawalId = await context.viewFacet.getLastWithdrawalId()

				// Pause globally => whenNotLiquidationPaused should first hit GlobalPaused
				await context.controlFacet.pauseGlobal()

				await expect(context.clearingHouse.connect(context.signers.clearingHouse).confiscateWithdrawal(withdrawalId)).to.be.revertedWithCustomError(
					context.clearingHouse,
					"GlobalPaused",
				)

				// Unpause and it should work
				await context.controlFacet.unpauseGlobal()
				await expect(context.clearingHouse.connect(context.signers.clearingHouse).confiscateWithdrawal(withdrawalId)).not.reverted
			})

			it("Should revert when LiquidatingPaused, then succeed after unpause", async () => {
				await partyB1.setBalances(context.collateral, e(100000), e(100000))
				await context.accountFacet
					.connect(context.signers.partyB1)
					.initiateWithdraw(context.collateral.getAddress(), e(1000), context.signers.others[0])

				const withdrawalId = await context.viewFacet.getLastWithdrawalId()

				// Pause liquidating => guarded by whenNotLiquidationPaused
				await context.controlFacet.pauseLiquidating()

				await expect(context.clearingHouse.connect(context.signers.clearingHouse).confiscateWithdrawal(withdrawalId)).to.be.revertedWithCustomError(
					context.clearingHouse,
					"LiquidatingPaused",
				)

				// Unpause and it should work
				await context.controlFacet.unpauseLiquidating()
				await expect(context.clearingHouse.connect(context.signers.clearingHouse).confiscateWithdrawal(withdrawalId)).not.reverted
			})

			it("Should revert on withdrawId == 0", async () => {
				await expect(context.clearingHouse.connect(context.signers.clearingHouse).confiscateWithdrawal(0)).to.be.revertedWithCustomError(
					context.clearingHouse,
					"InvalidID",
				)
			})

			it("Should revert on withdrawId > lastWithdrawId", async () => {
				const last = await context.viewFacet.getLastWithdrawalId() // uses AccountStorage.lastWithdrawId
				const nonExistent = Number(last) + 1

				await expect(context.clearingHouse.connect(context.signers.clearingHouse).confiscateWithdrawal(nonExistent)).to.be.revertedWithCustomError(
					context.clearingHouse,
					"InvalidID",
				)
			})

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

				// TODO: if the contract changed to one-time setting config this transaction should be removed
				await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
					isActive: true,
					lossCoverage: e(1),
					oracleId: 1,
				})

				expect(
					await context.clearingHouse
						.connect(context.signers.clearingHouse)
						.flagIsolatedPartyBLiquidation(partyB1.address, context.collateral.getAddress()),
				).not.reverted

				expect(
					await context.clearingHouse
						.connect(context.signers.clearingHouse)
						.liquidateIsolatedPartyB(partyB1.address, context.collateral.getAddress(), e(-1200000), e(10)),
				).not.reverted

				const withdrawalId = await context.viewFacet.getLastWithdrawalId()
				await expect(context.clearingHouse.connect(context.signers.clearingHouse).confiscateWithdrawal(withdrawalId)).not.reverted

				const partyBAfterBalance = await context.viewFacet.getIsolatedBalance(partyB1.address, context.collateral.getAddress())
				console.log("partyBAfterBalance", partyBAfterBalance)

				expect(partyBAfterBalance - partyBBeforeBalance).to.be.equal(e(1000))
				const withdraw = await context.viewFacet.getWithdrawal(withdrawalId)
				expect(withdraw.status).to.be.equal(WithdrawStatus.CANCELED)
			})
		})

		describe("Cancel Open Intents", async function () {
			it("Should enforce onlyRole(CLEARING_HOUSE_ROLE)", async () => {
				const req = openIntentRequestBuilder()
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

				const CLEARING_HOUSE_ROLE = ethers.id("CLEARING_HOUSE_ROLE")
				await partyA2.setBalances(context.collateral, e(10000), e(1000))
				await partyA2.sendOpenIntent(req) // id=1
				const id = 1
				await partyB2.lockOpenIntent(id)

				await makePartyInLiquidationIsolated()

				const unauthorized = context.signers.affiliate1
				await expect(context.clearingHouse.connect(unauthorized).cancelOpenIntents([id]))
					.to.be.revertedWithCustomError(context.clearingHouse, "MissingRole")
					.withArgs(await unauthorized.getAddress(), CLEARING_HOUSE_ROLE)

				await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([id])).not.reverted
			})

			it("Should expire a pending open intent if deadline passed (and party is in liquidation)", async () => {
				const now = await getLatestBlockTime()
				const req = openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.address])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateral.getAddress())
					.symbolId(2)
					.deadline(now + 40) // already expired
					.expirationTimestamp(now + 150)
					.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
					.quantity(e(50))
					.strikePrice(e(10000))
					.price(e(10))
					.mm(0)
					.tradeSide(TradeSide.BUY)
					.marginType(MarginType.ISOLATED)
					.build()

				const id = 1
				await partyA2.setBalances(context.collateral, e(10000), e(1000))
				await partyA2.sendOpenIntent(req)
				await partyB2.lockOpenIntent(id)

				await makePartyInLiquidationIsolated()
				await moveTime(60)

				await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([id])).not.to.be.reverted

				const intent = await context.viewFacet.getOpenIntent(id)
				expect(intent.status).to.equal(IntentStatus.EXPIRED)
			})

			it("Should fail to cancel open intents when open intent is filled", async () => {
				const request1 = openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.address])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateralNL.getAddress())
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
				const openIntentId2 = 2
				await partyA2.setBalances(context.collateral, e(10000), e(1000))
				await partyA2.setBalances(context.collateralNL, e(100), e(10))
				await partyA2.sendOpenIntent(request1)
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId1)
				await partyB2.lockOpenIntent(openIntentId2)
				await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

				await makePartyInLiquidationIsolated()
				await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId1])).to.be.revertedWithCustomError(
					context.clearingHouse,
					"InvalidState",
				)

				await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId2])).not.reverted
				expect((await context.viewFacet.getOpenIntent(openIntentId2)).status).to.equal(IntentStatus.CANCELED)
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

			it("Should cancel open intents,Update state to Canceled", async () => {
				const request1 = openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.address])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateralNL.getAddress())
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

				const openIntentId2 = 2
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId2)

				await makePartyInLiquidationIsolated()
				expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId2])).not.reverted

				expect((await context.viewFacet.getOpenIntent(openIntentId2)).status).to.be.equal(IntentStatus.CANCELED)
			})

			it("Should cancel open intents,Unlock Fees", async () => {
				const request1 = openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.address])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateralNL.getAddress())
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

				const openIntentId2 = 2
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId2)

				await makePartyInLiquidationIsolated()
				const intent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())

				const balanceLockedBefore = await context.viewFacet.getIsolatedLockedBalance(partyA2.address, context.collateralNL.getAddress())
				const affiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(intent.id)
				const platformFee = await context.viewFacet.getOpenIntentPlatformFee(intent.id)
				const solverFee =
					(BigInt(intent.price) * BigInt(intent.tradeAgreements.quantity) * BigInt(intent.feeStructure.solverFee.openFee)) /
					((await context.oracle.getPrice(
						intent.feeStructure.feeToken,
						(await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)).collateral,
					)) *
						parseUnits("1", 18))
				expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId2])).not.reverted

				expect((await context.viewFacet.getOpenIntent(openIntentId2)).status).to.be.equal(IntentStatus.CANCELED)

				const balanceLockedAfter = await context.viewFacet.getIsolatedLockedBalance(partyA2.address, context.collateralNL.getAddress())
				expect(balanceLockedBefore - balanceLockedAfter).to.be.equal(affiliateFee + platformFee + solverFee)
			})

			it("Should cancel open intents,Unlock Fees in Cross Margin", async () => {
				const request1 = openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.address])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateralNL.getAddress())
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
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId1)
				await partyB2.fillOpenIntent(openIntentId1, e(50), e(10))

				const openIntentId2 = 2
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId2)

				await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
					isActive: true,
					lossCoverage: e(1),
					oracleId: 1,
				})

				/////////////// Flag Cross Parties //////////////////
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress())

				const liquidationID = await context.viewFacet.getLastLiquidationId()

				/////////////// Liquidate Cross Parties //////////////////
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyA(liquidationID, partyA2.address, partyB2.address, context.collateral.getAddress(), e(-1200000), e(10))

				const intent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())

				const balanceLockedBefore = await context.viewFacet.getCrossBalance(partyA2.address, context.collateralNL.getAddress(), partyB2.address)
				const affiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(intent.id)
				const platformFee = await context.viewFacet.getOpenIntentPlatformFee(intent.id)
				const solverFee =
					(BigInt(intent.price) * BigInt(intent.tradeAgreements.quantity) * BigInt(intent.feeStructure.solverFee.openFee)) /
					((await context.oracle.getPrice(
						intent.feeStructure.feeToken,
						(await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)).collateral,
					)) *
						parseUnits("1", 18))
				expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId2])).not.reverted

				expect((await context.viewFacet.getOpenIntent(openIntentId2)).status).to.be.equal(IntentStatus.CANCELED)

				const balanceLockedAfter = await context.viewFacet.getCrossBalance(partyA2.address, context.collateralNL.getAddress(), partyB2.address)
				expect(balanceLockedBefore.locked - balanceLockedAfter.locked).to.be.equal(affiliateFee + platformFee + solverFee)
			})

			it("Should set open intents as Pending, in Buy Trade Isolated, more than One Party B whitelisted", async () => {
				const request1 = openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.address, partyB1.address])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateralNL.getAddress())
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

				const openIntentId2 = 2
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId2)

				await makePartyInLiquidationIsolated()

				const lastID = await context.viewFacet.getLastOpenIntentId()
				const premium = await context.viewFacet.getOpenIntentPremium(lastID)
				const balanceLockedBefore = await context.viewFacet.getIsolatedLockedBalance(partyA2.address, context.collateral.getAddress())

				expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId2])).not.reverted

				expect((await context.viewFacet.getOpenIntent(openIntentId2)).status).to.be.equal(IntentStatus.PENDING)
				const balanceLockedAfter = await context.viewFacet.getIsolatedLockedBalance(partyA2.address, context.collateral.getAddress())
				expect(balanceLockedBefore - balanceLockedAfter).to.be.equal(0)

				await expect(partyB1.lockOpenIntent(openIntentId2)).not.be.reverted
				await expect(partyB1.fillOpenIntent(openIntentId2, request1.quantity, request1.price)).not.be.reverted
			})

			it("should be LOCKed by another PartyB in case state Changed to Pending", async () => {
				const request1 = openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.address, partyB1.address])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateralNL.getAddress())
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

				const openIntentId2 = 2
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId2)

				await makePartyInLiquidationIsolated()

				const lastID = await context.viewFacet.getLastOpenIntentId()
				const premium = await context.viewFacet.getOpenIntentPremium(lastID)
				const balanceLockedBefore = await context.viewFacet.getIsolatedLockedBalance(partyA2.address, context.collateral.getAddress())

				expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId2])).not.reverted

				expect((await context.viewFacet.getOpenIntent(openIntentId2)).status).to.be.equal(IntentStatus.PENDING)
				const balanceLockedAfter = await context.viewFacet.getIsolatedLockedBalance(partyA2.address, context.collateral.getAddress())
				expect(balanceLockedBefore - balanceLockedAfter).to.be.equal(0)
			})

			it("Should Cancel open intents, in Buy Trade Isolated, with One Party B whitelisted", async () => {
				const request1 = openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.address])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateralNL.getAddress())
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

				const openIntentId2 = 2
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId2)

				await makePartyInLiquidationIsolated()

				const lastID = await context.viewFacet.getLastOpenIntentId()
				const premium = await context.viewFacet.getOpenIntentPremium(lastID)
				const balanceLockedBefore = await context.viewFacet.getIsolatedLockedBalance(partyA2.address, context.collateral.getAddress())

				expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId2])).not.reverted

				expect((await context.viewFacet.getOpenIntent(openIntentId2)).status).to.be.equal(IntentStatus.CANCELED)
				const balanceLockedAfter = await context.viewFacet.getIsolatedLockedBalance(partyA2.address, context.collateral.getAddress())
				expect(balanceLockedBefore - balanceLockedAfter).to.be.equal(premium)
			})

			it("Should cancel open intents,Unlock Premium in Buy Trade Cross", async () => {
				const request1 = openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.address])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateralNL.getAddress())
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

				const openIntentId2 = 2
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId2)

				await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
					isActive: true,
					lossCoverage: e(1),
					oracleId: 1,
				})
				/////////////// Flag Cross Parties //////////////////
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagCrossPartyBLiquidation(partyB2.address, partyA2.address, context.collateral.getAddress())

				/////////////// Liquidate Cross Parties //////////////////
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyB(partyB2.address, partyA2.address, context.collateral.getAddress(), e(-1200000), e(10))

				const lastID = await context.viewFacet.getLastOpenIntentId()
				const premium = await context.viewFacet.getOpenIntentPremium(lastID)
				const balanceLockedBefore = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral.getAddress(), partyB2.address)
				const detail = await context.viewFacet.getLiquidationDetail(await context.viewFacet.getLastLiquidationId())

				expect(detail.partyA).equal(partyA2.address)
				expect(detail.partyB).equal(partyB2.address)
				expect(detail.status).equal(LiquidationStatus.IN_PROGRESS)

				expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId2])).not.reverted

				expect((await context.viewFacet.getOpenIntent(openIntentId2)).status).to.be.equal(IntentStatus.CANCELED)
				const balanceLockedAfter = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral.getAddress(), partyB2.address)
				expect(balanceLockedBefore.locked - balanceLockedAfter.locked).to.be.equal(premium)
			})

			it("Should cancel open intents,Unlock MM in Sell Trade Cross", async () => {
				const request1 = openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.address])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateralNL.getAddress())
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

				const openIntentId2 = 2
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId2)

				await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
					isActive: true,
					lossCoverage: e(1),
					oracleId: 1,
				})
				/////////////// Flag Cross Parties //////////////////
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress())

				const liquidationID = await context.viewFacet.getLastLiquidationId()

				/////////////// Liquidate Cross Parties //////////////////
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyA(liquidationID, partyA2.address, partyB2.address, context.collateral.getAddress(), e(-1200000), e(10))

				const lastID = await context.viewFacet.getLastOpenIntentId()
				const intent = await context.viewFacet.getOpenIntent(openIntentId2)
				const balanceLockedBefore = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral.getAddress(), partyB2.address)

				expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId2])).not.reverted

				expect((await context.viewFacet.getOpenIntent(openIntentId2)).status).to.be.equal(IntentStatus.CANCELED)
				const balanceLockedAfter = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral.getAddress(), partyB2.address)
				expect(balanceLockedBefore.totalMM - balanceLockedAfter.totalMM).to.be.equal(intent.tradeAgreements.mm)
			})

			it("Should cancel open intents,Unlock MM in Sell Trade Cross", async () => {
				const request1 = openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.address])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateralNL.getAddress())
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

				const openIntentId2 = 2
				await partyA2.sendOpenIntent(request1)
				await partyB2.lockOpenIntent(openIntentId2)

				await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
					isActive: true,
					lossCoverage: e(1),
					oracleId: 1,
				})
				/////////////// Flag Cross Parties //////////////////
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagPartyALiquidation(partyA2.address, partyB2.address, context.collateral.getAddress())

				const liquidationID = await context.viewFacet.getLastLiquidationId()

				/////////////// Liquidate Cross Parties //////////////////
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateCrossPartyA(liquidationID, partyA2.address, partyB2.address, context.collateral.getAddress(), e(-1200000), e(10))

				const lastID = await context.viewFacet.getLastOpenIntentId()
				const intent = await context.viewFacet.getOpenIntent(openIntentId2)
				const balanceLockedBefore = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral.getAddress(), partyB2.address)

				expect(await context.clearingHouse.connect(context.signers.clearingHouse).cancelOpenIntents([openIntentId2])).not.reverted

				expect((await context.viewFacet.getOpenIntent(openIntentId2)).status).to.be.equal(IntentStatus.CANCELED)
				const balanceLockedAfter = await context.viewFacet.getCrossBalance(partyA2.address, context.collateral.getAddress(), partyB2.address)
				expect(balanceLockedBefore.totalMM - balanceLockedAfter.totalMM).to.be.equal(intent.tradeAgreements.mm)
			})
		})

		describe("Cancel Close Intents", async function () {
			it("Should be callable only by CLEARING_HOUSE_ROLE and emit CancelCloseIntentsForLiquidation", async () => {
				// minimal setup: one pending close intent
				const req = openIntentRequestBuilder()
					.partyBsWhiteList([partyB2.address])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateral.getAddress())
					.symbolId(2)
					.deadline((await getLatestBlockTime()) + 2000)
					.expirationTimestamp((await getLatestBlockTime()) + 3000)
					.exerciseFee({ cap: e(0.002), rate: e(0.0002) })
					.quantity(e(5))
					.strikePrice(e(10000))
					.price(e(10))
					.mm(0)
					.tradeSide(TradeSide.BUY)
					.marginType(MarginType.ISOLATED)
					.build()

				await partyA2.setBalances(context.collateral, e(10000), e(1000))
				await partyB2.setBalances(context.collateral, e(10000), e(1000))
				await partyA2.sendOpenIntent(req)
				await partyB2.lockOpenIntent(1)
				await partyB2.fillOpenIntent(1, e(5), e(10))

				await partyA2.sendCloseIntent(1, e(3), e(12), (await getLatestBlockTime()) + 2000)
				const closeIntentId = 1

				// Put partyB in liquidation to pass the solvency check
				await context.controlFacet.setPartyBConfig(context.signers.partyB2, { isActive: true, lossCoverage: e(1), oracleId: 1 })
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress())
				await context.clearingHouse
					.connect(context.signers.clearingHouse)
					.liquidateIsolatedPartyB(partyB2.address, context.collateral.getAddress(), e(-1200000), e(10))

				// Non-authorized should revert
				await expect(context.clearingHouse.connect(context.signers.partyA2).cancelCloseIntents([closeIntentId])).to.be.revertedWithCustomError(
					context.clearingHouse,
					"MissingRole",
				)

				// Authorized should emit event
				await expect(context.clearingHouse.connect(context.signers.clearingHouse).cancelCloseIntents([closeIntentId]))
					.to.emit(context.clearingHouse, "CancelCloseIntentsForLiquidation")
					.withArgs(context.signers.clearingHouse.address, [closeIntentId])
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
				await partyB2.setBalances(context.collateral, e(10000), e(1000))
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

			it("Should fail to cancel Close intents when party is not in liquidation", async () => {
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
						.flagIsolatedPartyBLiquidation(partyB2.address, context.collateral.getAddress()),
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
	})
}
