import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { OpenIntent, openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { ContractEventPayload, parseUnits, ZeroAddress } from "ethers"
import { IntentStatus, MarginType, TradeSide } from "./option-enums"
import { CrossEntryStruct, OpenIntentStruct, SymbolStruct } from "../types/contracts/interfaces/ISymmio"
import { BigNumber } from "@ethersproject/bignumber"
import { bigint, int } from "hardhat/internal/core/params/argumentTypes"
import { partyAOpen } from "../types/contracts/facets"

import { getLatestBlockTime } from "../utils/time"

export function shouldBehaveLikePartyAOpenFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)

		await context.controlFacet.setAffiliateStatus(context.signers.others[0], true)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyB1.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateralNL, e(100000), e(100000))
	})

	describe("sendOpenIntent", async function () {
		beforeEach(async () => {
			// await context.controlFacet.addOracle("test orancel", context.signers.others[0])
			// await context.controlFacet.addSymbol("BTC", 0, 1, context.collateral.getAddress(), { openFee: 10, closeFee: 20 }, 0)
		})

		it("Should fail when partyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "PartyAActionsPaused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "GlobalPaused")
		})

		it("Should be failed when Sender address is Suspended", async () => {
			await context.controlFacet.suspendAddress(partyA1.getSigner, true)

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "UserSuspended")
		})

		it("Should fail when instance mode is active", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await partyA1.bindToCounterParty(partyB1.getSigner)
			await partyA1.activateInstantActionMode()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InstantModeActive")
		})

		it("Should fail when Sender is Party B", async function () {
			const latestBlock = await getLatestBlockTime()
			const request: OpenIntent = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await expect(
				context.partyAOpenFacet
					.connect(partyB1.getSigner)
					.sendOpenIntent(
						request.partyBsWhiteList,
						request.symbolId,
						request.price,
						request.quantity,
						request.strikePrice,
						request.expirationTimestamp,
						request.mm,
						request.tradeSide,
						request.marginType,
						request.exerciseFee,
						request.solverFee,
						request.deadline,
						request.feeToken,
						request.affiliate,
						request.userData,
					),
			).to.be.revertedWithCustomError(context.partyAOpenFacet, "PartyBSender")
		})

		it("Should fail when symbolId be wrong", async function () {
			const latestBlock = await getLatestBlockTime()

			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.expirationTimestamp(latestBlock + 100)
				.deadline(latestBlock + 100)
				.symbolId(1)
				.build()

			await context.controlFacet.setSymbolsValidationState([1], [false])

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InvalidSymbol")
		})

		it("Should fail when deadline be low", async function () {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "ExpirationTimestampPassed")
		})

		it("Should fail when expiration timestamp be low", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "ExpirationTimestampPassed")
		})

		it("Should fail when cap for exercise fee be high", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(2), rate: "0" })
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InvalidExerciseFee")
		})

		it("Should fail when affiliate be zero address or invalid", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)

			request.affiliate(ZeroAddress)
			expect(await partyA1.sendOpenIntent(request.build())).to.be.not.reverted

			request.affiliate(context.signers.others[1])
			await context.controlFacet.setAffiliateStatus(context.signers.others[1], true)
			expect(await partyA1.sendOpenIntent(request.build())).to.be.not.reverted

			await context.controlFacet.setAffiliateStatus(context.signers.others[1], false)
			await expect(partyA1.sendOpenIntent(request.build())).to.be.revertedWithCustomError(context.partyAOpenFacet, "InvalidAffiliate")
		})

		it("Should fail when partyA has NO partyB whitelisted ", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(partyB1.getSigner)
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "BoundedToAnotherPartyB")
		})

		it("Should fail when partyA bound to a partyB that is not in whitelisted partyB", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(partyB1.getSigner)
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "BoundedToAnotherPartyB")
		})

		it("Should fail as MSG Sender is in whitelisted partyB", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyA1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InvalidWhitelistEntry")
		})

		it("Should fail when partyA sends Sell intent with isolated margin", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner, context.signers.partyB1])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.ISOLATED)
				.tradeSide(TradeSide.SELL)
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "IsolatedModeSellNotAllowed")
		})

		it("Should fail when DeadLine Low", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner, context.signers.partyB1])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock - 12)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "LowDeadline")
		})

		it("Should fail when partyA have more than 1 PartyB in cross margin ", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner, context.signers.partyB1])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.SELL)
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "MultiplePartyBNotAllowed")
		})

		it("Should fail when partyA is not solvent in cross margin", async function () {
			await context.clearingHouse.flagPartyALiquidation(partyA1.address, partyB1.address, context.collateral)

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.SELL)
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "NotSolvent")
		})

		it("Should fail when partyB is not solvent in cross/Isolated margin", async function () {
			await context.controlFacet.setPartyBConfig(partyB1.address, {
				isActive: false,
				lossCoverage: 1,
				oracleId: 1,
			})
			await context.clearingHouse.flagCrossPartyBLiquidation(partyB1.address, partyA1.address, context.collateral)

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.BUY)
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "NotSolvent")
		})

		it("Should fail when partyB is not solvent in Isolated margin", async function () {
			await context.controlFacet.setPartyBConfig(partyB1.address, {
				isActive: true,
				lossCoverage: 1,
				oracleId: 1,
			})
			await context.clearingHouse.flagIsolatedPartyBLiquidation(partyB1.address, context.collateral)

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.ISOLATED)
				.tradeSide(TradeSide.BUY)
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "NotSolvent")
		})

		it("Should fail when partyB is not solvent in cross margin", async function () {
			await context.controlFacet.setPartyBConfig(partyB1.address, {
				isActive: true,
				lossCoverage: 1,
				oracleId: 1,
			})
			await context.clearingHouse.flagCrossPartyBLiquidation(partyB1.address, partyA1.address, context.collateral)

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.SELL)
				.mm(1000)
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "NotSolvent")
		})

		it("should fail when partyA have intent with 0 quantity", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(0))
				.price(7)
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InvalidOpenQuantity")
		})

		it("Should fail when partyB whiteListed and available Isolated Balance is insufficient", async function () {
			const amountToMint = 10000
			const amountToDeposit = 100
			const amountToAllocate = 50
			let partyALocal = new PartyA(context, context.signers.others[0])
			await partyALocal.setBalances(context.collateral, amountToMint, amountToDeposit)
			await partyALocal.setBalances(context.collateralNL, amountToMint, amountToDeposit)

			await context.accountFacet.connect(partyALocal.getSigner).allocate(context.collateral, partyB1.address, amountToAllocate)
			await context.accountFacet.connect(partyALocal.getSigner).allocate(context.collateralNL, partyB1.address, amountToAllocate)

			await context.controlFacet.setPriceOracleAddress(context.oracle)

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateralNL.getAddress())
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(1))
				.marginType(MarginType.ISOLATED)
				.tradeSide(TradeSide.BUY)
				.solverFee({ openFee: e(0.5), closeFee: e(0.5) })
				.price(100)
				.build()

			await context.controlFacet.setDefaultReleaseInterval(12) // Scheduled release Entry is first updated in sync function using Default Release Interval
			// if default Release Entry is Zero no update is taken and isolated sub is taken place instead of Sub For CounterParty

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.5), closeFee: e(0.5) }])
			await context.controlFacet.setSymbolsPlatformFees([1], [{ openFee: e(0.5), closeFee: e(0.5) }])

			await expect(partyALocal.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InsufficientBalance")

			console.log("Sender Isolated Balance:", await context.viewFacet.getIsolatedBalance(partyALocal.address, await context.collateral.getAddress()))
			console.log(
				"Sender Isolated Locked Balance:",
				await context.viewFacet.getIsolatedLockedBalance(partyALocal.address, await context.collateral.getAddress()),
			)
			console.log("Sender Isolated Fee Balance:", await context.viewFacet.getIsolatedBalance(partyALocal.address, context.collateralNL))
			console.log("Sender Isolated Locked Fee Balance:", await context.viewFacet.getIsolatedLockedBalance(partyALocal.address, context.collateralNL))
			console.log("Sender Cross Balance:", await context.viewFacet.getCrossBalance(partyALocal.address, context.collateral, partyB1.address))
			console.log("Sender Cross Fee Balance:", await context.viewFacet.getCrossBalance(partyALocal.address, context.collateralNL, partyB1.address))
			console.log(
				"Sender Scheduled Release Entry:",
				await context.viewFacet.getScheduledReleaseEntry(partyALocal.address, context.collateralNL, partyB1.address),
			)
			console.log("Oracle returns:", await context.oracle.getPrice(context.collateralNL, context.collateral))
		})

		it("Should fail when  Multiple partyBs whiteListed and available balance is insufficient", async function () {
			const amountToMint = 10000
			const amountToDeposit = 100
			const amountToAllocate = 50
			let partyALocal = new PartyA(context, context.signers.others[0])
			await partyALocal.setBalances(context.collateral, amountToMint, amountToDeposit)
			await partyALocal.setBalances(context.collateralNL, amountToMint, amountToDeposit)

			await context.accountFacet.connect(partyALocal.getSigner).allocate(context.collateral, partyB1.address, amountToAllocate)
			await context.accountFacet.connect(partyALocal.getSigner).allocate(context.collateralNL, partyB1.address, amountToAllocate)

			await context.controlFacet.setPriceOracleAddress(context.oracle)

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.address, partyB1.address])
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateralNL.getAddress())
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(1))
				.marginType(MarginType.ISOLATED)
				.tradeSide(TradeSide.BUY)
				.solverFee({ openFee: e(0.5), closeFee: e(0.5) })
				.price(100)
				.build()

			await context.controlFacet.setDefaultReleaseInterval(12) // Scheduled release Entry is first updated in sync function using Default Release Interval
			// if default Release Entry is Zero no update is taken and isolated sub is taken place instead of Sub For CounterParty

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.5), closeFee: e(0.5) }])
			await context.controlFacet.setSymbolsPlatformFees([1], [{ openFee: e(0.5), closeFee: e(0.5) }])

			await expect(partyALocal.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InsufficientBalance")

			console.log("Sender Isolated Balance:", await context.viewFacet.getIsolatedBalance(partyALocal.address, await context.collateral.getAddress()))
			console.log(
				"Sender Isolated Locked Balance:",
				await context.viewFacet.getIsolatedLockedBalance(partyALocal.address, await context.collateral.getAddress()),
			)
			console.log("Sender Isolated Fee Balance:", await context.viewFacet.getIsolatedBalance(partyALocal.address, context.collateralNL))
			console.log("Sender Isolated Locked Fee Balance:", await context.viewFacet.getIsolatedLockedBalance(partyALocal.address, context.collateralNL))
			console.log("Sender Cross Balance:", await context.viewFacet.getCrossBalance(partyALocal.address, context.collateral, partyB1.address))
			console.log("Sender Cross Fee Balance:", await context.viewFacet.getCrossBalance(partyALocal.address, context.collateralNL, partyB1.address))
			console.log(
				"Sender Scheduled Release Entry:",
				await context.viewFacet.getScheduledReleaseEntry(partyALocal.address, context.collateralNL, partyB1.address),
			)
			console.log("Oracle returns:", await context.oracle.getPrice(context.collateralNL, context.collateral))
		})

		it("Should NOT fail In Cross Margin when available CROSS balance insufficient(Fee/Premium in Buy Trade)", async function () {
			const amountToMint = 10000
			const amountToDeposit = 100
			const amountToAllocate = 50
			let partyALocal = new PartyA(context, context.signers.others[0])
			await partyALocal.setBalances(context.collateral, amountToMint, amountToDeposit)
			await partyALocal.setBalances(context.collateralNL, amountToMint, amountToDeposit)

			await context.accountFacet.connect(partyALocal.getSigner).allocate(context.collateral, partyB1.address, amountToAllocate)
			await context.accountFacet.connect(partyALocal.getSigner).allocate(context.collateralNL, partyB1.address, amountToAllocate)

			await context.controlFacet.setPriceOracleAddress(context.oracle)

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateralNL.getAddress())
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(1))
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.BUY)
				.solverFee({ openFee: e(0.5), closeFee: e(0.5) })
				.price(100)
				.build()

			await context.controlFacet.setDefaultReleaseInterval(12) // Scheduled release Entry is first updated in sync function using Default Release Interval
			// if default Release Entry is Zero no update is taken and isolated sub is taken place instead of Sub For CounterParty

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.5), closeFee: e(0.5) }])
			await context.controlFacet.setSymbolsPlatformFees([1], [{ openFee: e(0.5), closeFee: e(0.5) }])

			await expect(partyALocal.sendOpenIntent(request)).not.to.be.reverted

			console.log("Sender Isolated Balance:", await context.viewFacet.getIsolatedBalance(partyALocal.address, await context.collateral.getAddress()))
			console.log(
				"Sender Isolated Locked Balance:",
				await context.viewFacet.getIsolatedLockedBalance(partyALocal.address, await context.collateral.getAddress()),
			)
			console.log("Sender Isolated Fee Balance:", await context.viewFacet.getIsolatedBalance(partyALocal.address, context.collateralNL))
			console.log("Sender Isolated Locked Fee Balance:", await context.viewFacet.getIsolatedLockedBalance(partyALocal.address, context.collateralNL))
			console.log("Sender Cross Balance:", await context.viewFacet.getCrossBalance(partyALocal.address, context.collateral, partyB1.address))
			console.log("Sender Cross Fee Balance:", await context.viewFacet.getCrossBalance(partyALocal.address, context.collateralNL, partyB1.address))
			console.log(
				"Sender Scheduled Release Entry:",
				await context.viewFacet.getScheduledReleaseEntry(partyALocal.address, context.collateralNL, partyB1.address),
			)
			console.log("Oracle returns:", await context.oracle.getPrice(context.collateralNL, context.collateral))
		})

		it("Should NOT fail In Cross Margin when available CROSS balance insufficient(Fee/Premium in Sell Trade)", async function () {
			const amountToMint = 10000
			const amountToDeposit = 100
			const amountToAllocate = 50
			let partyALocal = new PartyA(context, context.signers.others[0])
			await partyALocal.setBalances(context.collateral, amountToMint, amountToDeposit)
			await partyALocal.setBalances(context.collateralNL, amountToMint, amountToDeposit)

			await context.accountFacet.connect(partyALocal.getSigner).allocate(context.collateral, partyB1.address, amountToAllocate)
			await context.accountFacet.connect(partyALocal.getSigner).allocate(context.collateralNL, partyB1.address, amountToAllocate)

			await context.controlFacet.setPriceOracleAddress(context.oracle)

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateralNL.getAddress())
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(1))
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.SELL)
				.solverFee({ openFee: e(0.5), closeFee: e(0.5) })
				.strikePrice(e(1))
				.mm(5000)
				.price(100)
				.build()

			await context.controlFacet.setDefaultReleaseInterval(12) // Scheduled release Entry is first updated in sync function using Default Release Interval
			// if default Release Entry is Zero no update is taken and isolated sub is taken place instead of Sub For CounterParty

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.5), closeFee: e(0.5) }])
			await context.controlFacet.setSymbolsPlatformFees([1], [{ openFee: e(0.5), closeFee: e(0.5) }])

			await expect(partyALocal.sendOpenIntent(request)).not.to.be.reverted

			console.log("Sender Isolated Balance:", await context.viewFacet.getIsolatedBalance(partyALocal.address, await context.collateral.getAddress()))
			console.log(
				"Sender Isolated Locked Balance:",
				await context.viewFacet.getIsolatedLockedBalance(partyALocal.address, await context.collateral.getAddress()),
			)
			console.log("Sender Isolated Fee Balance:", await context.viewFacet.getIsolatedBalance(partyALocal.address, context.collateralNL))
			console.log("Sender Isolated Locked Fee Balance:", await context.viewFacet.getIsolatedLockedBalance(partyALocal.address, context.collateralNL))
			console.log("Sender Cross Balance:", await context.viewFacet.getCrossBalance(partyALocal.address, context.collateral, partyB1.address))
			console.log("Sender Cross Fee Balance:", await context.viewFacet.getCrossBalance(partyALocal.address, context.collateralNL, partyB1.address))
			console.log(
				"Sender Scheduled Release Entry:",
				await context.viewFacet.getScheduledReleaseEntry(partyALocal.address, context.collateralNL, partyB1.address),
			)
			console.log("Oracle returns:", await context.oracle.getPrice(context.collateralNL, context.collateral))
		})

		it("Should Successfully create Intent Object", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateralNL.getAddress())
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.marginType(MarginType.ISOLATED)
				.tradeSide(TradeSide.BUY)
				.strikePrice(e(1))
				.price(7)
				.build()

			expect(await partyA1.sendOpenIntent(request)).to.be.not.reverted

			const intent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())

			expect(intent.id).to.be.equal(await context.viewFacet.getLastOpenIntentId())
			expect(intent.tradeId).to.be.equal(0)
			expect(intent.partyBsWhiteList.length).to.be.equal(request.partyBsWhiteList.length)
			expect(intent.partyBsWhiteList).to.be.deep.equal(request.partyBsWhiteList)
			expect(intent.price).to.be.equal(request.price)
			expect(intent.tradeAgreements.symbolId).to.be.equal(request.symbolId)
			expect(intent.tradeAgreements.quantity).to.be.equal(request.quantity)
			expect(intent.tradeAgreements.strikePrice).to.be.equal(request.strikePrice)
			expect(intent.tradeAgreements.expirationTimestamp).to.be.equal(request.expirationTimestamp)
			expect(intent.tradeAgreements.exerciseFee.cap).to.be.equal(request.exerciseFee.cap)
			expect(intent.tradeAgreements.exerciseFee.rate).to.be.equal(request.exerciseFee.rate)
			expect(intent.tradeAgreements.mm).to.be.equal(request.mm)
			expect(intent.tradeAgreements.marginType).to.be.equal(request.marginType)
			expect(intent.tradeAgreements.tradeSide).to.be.equal(request.tradeSide)
			expect(intent.partyA).to.be.equal(partyA1.address)
			expect(intent.partyB).to.be.equal(ZeroAddress)
			expect(intent.status).to.be.equal(IntentStatus.PENDING) // IntentStatus.PENDING
			expect(intent.parentId).to.be.equal(0)
			expect(intent.createTimestamp).to.be.equal(await getLatestBlockTime())
			expect(intent.deadline).to.be.equal(request.deadline)
			expect(intent.feeStructure.platformFee).to.be.deep.equal((await context.viewFacet.getSymbol(request.symbolId)).platformFee)
			expect(intent.feeStructure.affiliateFee.toString()).to.be.deep.equal(
				(await context.viewFacet.getAffiliateFee(request.affiliate, request.symbolId)).toString(),
			)
			expect(intent.feeStructure.solverFee.closeFee).to.be.equal(request.solverFee.closeFee)
			expect(intent.feeStructure.solverFee.openFee).to.be.equal(request.solverFee.openFee)
			expect(intent.feeStructure.feeToken).to.be.equal(request.feeToken)
			expect(intent.feeStructure.tokenPriceInCollateral).to.be.equal(
				await context.oracle.getPrice(intent.feeStructure.feeToken, (await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)).collateral),
			)
			expect(intent.affiliate).to.be.equal(request.affiliate)
		})

		it("Should Successfully Lock Premium in Isolate Margin", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateralNL.getAddress())
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.marginType(MarginType.ISOLATED)
				.tradeSide(TradeSide.BUY)
				.strikePrice(e(1))
				.price(7)
				.build()

			await context.controlFacet.setDefaultReleaseInterval(12)

			expect(await partyA1.sendOpenIntent(request)).to.be.not.reverted
			const intent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())

			expect(
				await context.viewFacet.getIsolatedLockedBalance(
					intent.partyA,
					(await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)).collateral,
				),
			).to.be.equal(await context.viewFacet.getOpenIntentPremium(intent.id))
		})

		it("Should Successfully Lock Premium in Cross Margin, Buy Trade", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.BUY)
				.strikePrice(e(1))
				.price(7)
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.not.reverted
			const intent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())

			const crossBalance = await context.viewFacet.getCrossBalance(
				intent.partyA,
				(await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)).collateral,
				partyB1.address,
			)
			expect(crossBalance.locked).to.be.equal(await context.viewFacet.getOpenIntentPremium(intent.id))
		})

		it("Should Successfully Lock Premium in Cross Margin, Sell Trade", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateralNL.getAddress())
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.SELL)
				.strikePrice(e(1))
				.solverFee({ openFee: e(0.5), closeFee: e(0.5) })
				.mm(1000)
				.price(e(1))
				.build()

			// await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.5), closeFee: e(0.5) }])
			// await context.controlFacet.setSymbolsPlatformFees([1], [{ openFee: e(0.5), closeFee: e(0.5) }])

			const crossBalanceBefore: CrossEntryStruct = await context.viewFacet.getCrossBalance(
				partyA1.address,
				(await context.viewFacet.getSymbol(request.symbolId)).collateral,
				partyB1.address,
			)
			console.log("Cross Balance Sell Trade Before:", crossBalanceBefore)
			await expect(partyA1.sendOpenIntent(request)).to.be.not.reverted
			const intent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())

			const crossBalanceAfter: CrossEntryStruct = await context.viewFacet.getCrossBalance(
				intent.partyA,
				(await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)).collateral,
				partyB1.address,
			)
			console.log("Cross Balance Sell Trade After:", crossBalanceAfter)
			expect(crossBalanceAfter.locked).to.be.equal(request.mm)
		})

		it("Should Successfully Lock Fees in Isolated Margin", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateralNL.getAddress())
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.marginType(MarginType.ISOLATED)
				.tradeSide(TradeSide.BUY)
				.strikePrice(e(1))
				.solverFee({ openFee: e(0.5), closeFee: e(0.5) })
				.price(1)
				.build()

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.5), closeFee: e(0.5) }])
			await context.controlFacet.setSymbolsPlatformFees([1], [{ openFee: e(0.5), closeFee: e(0.5) }])
			const balanceBefore = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, request.feeToken)
			await expect(partyA1.sendOpenIntent(request)).to.be.not.reverted
			const intent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())

			const balanceAfter = await context.viewFacet.getIsolatedLockedBalance(intent.partyA, intent.feeStructure.feeToken)

			const solverFee =
				(BigInt(request.price) * BigInt(request.quantity) * BigInt(request.solverFee.openFee)) /
				((await context.oracle.getPrice(request.feeToken, (await context.viewFacet.getSymbol(request.symbolId)).collateral)) * parseUnits("1", 18))

			const affiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(intent.id)
			const platformFee = await context.viewFacet.getOpenIntentPlatformFee(intent.id)
			console.log("Affiliate Fee:", affiliateFee)
			console.log("Platform Fee:", platformFee)
			console.log("Solver Fee:", solverFee)
			expect(balanceAfter - balanceBefore).to.be.equal(solverFee + affiliateFee + platformFee)
		})

		it("Should Successfully Lock Fees in Cross Margin", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateralNL.getAddress())
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.SELL)
				.strikePrice(e(1))
				.solverFee({ openFee: e(0.5), closeFee: e(0.5) })
				.price(1)
				.build()

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.5), closeFee: e(0.5) }])
			await context.controlFacet.setSymbolsPlatformFees([1], [{ openFee: e(0.5), closeFee: e(0.5) }])
			await context.controlFacet.setDefaultFeeCollector(context.signers.admin)

			await expect(partyA1.sendOpenIntent(request)).to.be.not.reverted
			const intent = await context.viewFacet.getOpenIntent(await context.viewFacet.getLastOpenIntentId())

			const balance = await context.viewFacet.getCrossBalance(intent.partyA, intent.feeStructure.feeToken, request.partyBsWhiteList[0])

			const solverFee =
				(BigInt(request.price) * BigInt(request.quantity) * BigInt(request.solverFee.openFee)) /
				((await context.oracle.getPrice(request.feeToken, (await context.viewFacet.getSymbol(request.symbolId)).collateral)) * parseUnits("1", 18))

			const affiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(intent.id)
			const platformFee = await context.viewFacet.getOpenIntentPlatformFee(intent.id)

			console.log("Affiliate Fee:", affiliateFee)
			console.log("Platform Fee:", platformFee)
			console.log("Solver Fee:", solverFee)

			console.log("Sender Isolated Balance:", await context.viewFacet.getIsolatedBalance(partyA1.address, await context.collateral.getAddress()))
			console.log(
				"Sender Isolated Locked Balance:",
				await context.viewFacet.getIsolatedLockedBalance(partyA1.address, await context.collateral.getAddress()),
			)
			console.log("Sender Isolated Fee Balance:", await context.viewFacet.getIsolatedBalance(partyA1.address, context.collateralNL))
			console.log("Sender Isolated Locked Fee Balance:", await context.viewFacet.getIsolatedLockedBalance(partyA1.address, context.collateralNL))
			console.log("Sender Cross Balance:", await context.viewFacet.getCrossBalance(partyA1.address, context.collateral, partyB1.address))
			console.log("Sender Cross Fee Balance:", await context.viewFacet.getCrossBalance(partyA1.address, context.collateralNL, partyB1.address))
			console.log(
				"Sender Scheduled Release Entry:",
				await context.viewFacet.getScheduledReleaseEntry(partyA1.address, context.collateralNL, partyB1.address),
			)
			console.log("Oracle returns:", await context.oracle.getPrice(context.collateralNL, context.collateral))

			expect(balance.locked).to.be.equal(solverFee + affiliateFee + platformFee)
		})
	})

	describe("cancelOpenIntent", async function () {
		beforeEach(async () => {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1.address)
				.feeToken(context.collateralNL)
				.expirationTimestamp(latestBlock + 120)
				.deadline(latestBlock + 100)
				.symbolId(1)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.ISOLATED)
				.tradeSide(TradeSide.BUY)
				.quantity(e(100))
				.solverFee({ openFee: e(0.5), closeFee: e(0.5) })
				.price(7)
				.build()

			const requestCrossBuy = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1.address)
				.feeToken(context.collateralNL)
				.expirationTimestamp(latestBlock + 120)
				.deadline(latestBlock + 100)
				.symbolId(1)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.BUY)
				.quantity(e(100))
				.solverFee({ openFee: e(0.5), closeFee: e(0.5) })
				.price(7)
				.build()

			const requestCrossSell = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1.address)
				.feeToken(context.collateralNL)
				.expirationTimestamp(latestBlock + 120)
				.deadline(latestBlock + 100)
				.symbolId(1)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.SELL)
				.quantity(e(100))
				.mm(5000)
				.solverFee({ openFee: e(0.5), closeFee: e(0.5) })
				.price(7)
				.build()

			await expect(partyA1.sendOpenIntent(request)).not.to.be.reverted
			await expect(partyA1.sendOpenIntent(requestCrossBuy)).not.to.be.reverted
			await expect(partyA1.sendOpenIntent(requestCrossSell)).not.to.be.reverted
		})

		it("Should be failed when Sender address is Suspended", async () => {
			await context.controlFacet.suspendAddress(partyA1.getSigner, true)
			// await expect(partyA1.sendCancelOpenIntent(["1"])).to.be.revertedWithCustomError(context.partyAOpenFacet, "UserSuspended")
			//TODO ::: Suspended address is for any party in any state?
		})

		it("Should be failed when in Emergency Mode", async () => {
			// await context.controlFacet.activeEmergencyMode();
			// await expect(partyA1.sendCancelOpenIntent(['1'])).to.be.revertedWithCustomError(context.partyAOpenFacet, "EmergencyMode")
			//TODO ::: Emergency mode is only for partyB?
		})

		it("Should be failed when Globally Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(partyA1.sendCancelOpenIntent(["1"])).to.be.revertedWithCustomError(context.partyAOpenFacet, "GlobalPaused")
		})

		it("Should fail when partyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await expect(partyA1.sendCancelOpenIntent(["1"])).to.be.revertedWithCustomError(context.partyAOpenFacet, "PartyAActionsPaused")
		})

		it("Should failed when msgSender is not the intent owner", async () => {
			await expect(partyA2.sendCancelOpenIntent(["1"])).to.be.revertedWithCustomError(context.partyAOpenFacet, "UnauthorizedSender")
		})

		it("Should fail when not in appropriate state", async function () {
			await context.controlFacet.setPartyBSupportedSymbolTypes(partyB1.getSigner.address, [0], [true])

			await expect(partyB1.lockOpenIntent(1)).not.to.be.reverted
			await expect(partyB1.fillOpenIntent(1, e(100), 6)).not.to.reverted
			await expect(partyA1.sendCancelOpenIntent(["1"])).to.be.revertedWithCustomError(context.partyAOpenFacet, "InvalidState")
		})

		it("Should expire when deadline is reached", async function () {
			let newBlockTimeStamp = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 120
			await network.provider.send("evm_setNextBlockTimestamp", [newBlockTimeStamp])
			await network.provider.send("evm_mine")

			expect(await partyA1.sendCancelOpenIntent(["1"])).not.to.be.reverted
			let intent = await context.viewFacet.getOpenIntent(1)
			expect(intent.status).to.be.equal(IntentStatus.EXPIRED)
		})

		it("Should Unlock premium on Isolated Margin", async () => {
			// take snapshot
			let isolatedLocketBalance = await context.viewFacet.getIsolatedLockedBalance(partyA1.getSigner, await context.collateral.getAddress())
			let isolatedBalance = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral.getAddress())
			let premium: BigInt = await context.viewFacet.getOpenIntentPremium(1)

			expect(await partyA1.sendCancelOpenIntent(["1"])).to.be.not.reverted

			let isolatedLocketBalanceLatter = await context.viewFacet.getIsolatedLockedBalance(partyA1.getSigner, await context.collateral.getAddress())
			let isolatedBalanceLatter = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral.getAddress())
			console.log("Locked Balance Before", isolatedLocketBalance)
			console.log("Locke Balance After", isolatedLocketBalanceLatter)

			expect(isolatedLocketBalance - isolatedLocketBalanceLatter).be.equal(premium)
		})

		it("Should Unlock premium on Cross Buy Margin", async () => {
			// take snapshot
			let crossBalance = await context.viewFacet.getCrossBalance(partyA1.address, await context.collateral.getAddress(), partyB1.address)
			let premium: BigInt = await context.viewFacet.getOpenIntentPremium(1)

			expect(await partyA1.sendCancelOpenIntent(["2"])).to.be.not.reverted

			let crossBalanceLatter = await context.viewFacet.getCrossBalance(partyA1.getSigner, await context.collateral.getAddress(), partyB1.address)
			console.log("Cross Balance Before", crossBalance)
			console.log("Cross Balance After", crossBalanceLatter)

			expect(crossBalance.locked - crossBalanceLatter.locked).be.equal(premium)
		})

		it("Should Unlock premium on Cross Sell Margin", async () => {
			// take snapshot
			let crossBalance = await context.viewFacet.getCrossBalance(partyA1.address, await context.collateral.getAddress(), partyB1.address)
			let premium: BigInt = await context.viewFacet.getOpenIntentPremium(1)

			expect(await partyA1.sendCancelOpenIntent(["3"])).to.be.not.reverted

			const intent = await context.viewFacet.getOpenIntent(3)

			let crossBalanceLatter = await context.viewFacet.getCrossBalance(partyA1.getSigner, await context.collateral.getAddress(), partyB1.address)
			console.log("Cross Balance Before", crossBalance)
			console.log("Cross Balance After", crossBalanceLatter)

			expect(crossBalance.locked - crossBalanceLatter.locked).be.equal(intent.tradeAgreements.mm)
		})

		it("Should Unlock Fees on Isolated Margin", async () => {
			// take snapshot
			let isolatedLocketBalance = await context.viewFacet.getIsolatedLockedBalance(partyA1.getSigner, await context.collateralNL.getAddress())

			const intent = await context.viewFacet.getOpenIntent(1)
			const affiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(1)
			const platformFee = await context.viewFacet.getOpenIntentPlatformFee(1)
			const solverFee =
				(BigInt(intent.price) * BigInt(intent.tradeAgreements.quantity) * BigInt(intent.feeStructure.solverFee.openFee)) /
				((await context.oracle.getPrice(
					intent.feeStructure.feeToken,
					(await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)).collateral,
				)) *
					parseUnits("1", 18))

			expect(await partyA1.sendCancelOpenIntent(["1"])).to.be.not.reverted

			let isolatedLocketBalanceLatter = await context.viewFacet.getIsolatedLockedBalance(partyA1.getSigner, await context.collateralNL.getAddress())

			console.log("Locked Fee Balance Before", isolatedLocketBalance)
			console.log("Locke Fee Balance After", isolatedLocketBalanceLatter)

			expect(isolatedLocketBalance - isolatedLocketBalanceLatter).be.equal(affiliateFee + platformFee + solverFee)
		})

		it("Should Unlock Fees on Cross Margin", async () => {
			// take snapshot
			let crossLocketBalance = await context.viewFacet.getCrossBalance(partyA1.getSigner, await context.collateralNL.getAddress(), partyB1.address)

			const intent = await context.viewFacet.getOpenIntent(2)
			const affiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(2)
			const platformFee = await context.viewFacet.getOpenIntentPlatformFee(2)
			const solverFee =
				(BigInt(intent.price) * BigInt(intent.tradeAgreements.quantity) * BigInt(intent.feeStructure.solverFee.openFee)) /
				((await context.oracle.getPrice(
					intent.feeStructure.feeToken,
					(await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)).collateral,
				)) *
					parseUnits("1", 18))

			expect(await partyA1.sendCancelOpenIntent(["2"])).to.be.not.reverted

			let crossLocketBalanceLatter = await context.viewFacet.getCrossBalance(
				partyA1.getSigner,
				await context.collateralNL.getAddress(),
				partyB1.address,
			)

			console.log("Locked Fee Balance Before", crossLocketBalance)
			console.log("Locke Fee Balance After", crossLocketBalanceLatter)

			expect(crossLocketBalance.locked - crossLocketBalanceLatter.locked).be.equal(affiliateFee + platformFee + solverFee)
		})

		it("Should be removed when canceled with pending state", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.expirationTimestamp(latestBlock + 120)
				.deadline(latestBlock + 100)
				.symbolId(1)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.ISOLATED)
				.tradeSide(TradeSide.BUY)
				.quantity(e(100))
				.price(7)
				.build()
			expect(await partyA1.sendOpenIntent(request)).not.to.be.reverted
			expect(await partyA1.sendOpenIntent(request)).not.to.be.reverted

			expect(await partyA1.sendCancelOpenIntent(["2"])).not.to.be.reverted
			let activeIntentIds: BigInt[] = await context.viewFacet.getActiveOpenIntentIds(partyA1.getSigner)
			for (let a of activeIntentIds) {
				expect(a).not.to.be.equal(2)
			}
			expect(await context.viewFacet.getPartyAOpenIntentIndex(2)).to.be.equal(0)
		})

		it("Should be change state to cancel_pending when locked", async function () {
			expect(await partyB1.lockOpenIntent(1)).to.not.reverted
			expect(await partyA1.sendCancelOpenIntent(["1"])).not.to.be.reverted

			let intent = await context.viewFacet.getOpenIntent(1)
			expect(intent.status).to.be.equal(IntentStatus.CANCEL_PENDING)
		})

		it("Should update status modifying timestamp", async function () {
			const latestBlock = await getLatestBlockTime()
			expect(await partyA1.sendCancelOpenIntent(["1"])).not.to.be.reverted

			let intent = await context.viewFacet.getOpenIntent(1)
			expect(intent.statusModifyTimestamp).to.be.approximately(latestBlock, 3)
		})

		it("Should Handle Multiple Intent Cancel at once", async function () {
			let intent1 = await context.viewFacet.getOpenIntent(1)
			let intent2 = await context.viewFacet.getOpenIntent(2)
			let intent3 = await context.viewFacet.getOpenIntent(3)

			expect(intent1.status).to.be.equal(IntentStatus.PENDING)
			expect(intent2.status).to.be.equal(IntentStatus.PENDING)
			expect(intent3.status).to.be.equal(IntentStatus.PENDING)

			expect(await partyA1.sendCancelOpenIntent(["1", "2", "3"])).not.to.be.reverted

			intent1 = await context.viewFacet.getOpenIntent(1)
			intent2 = await context.viewFacet.getOpenIntent(2)
			intent3 = await context.viewFacet.getOpenIntent(3)

			expect(intent1.status).to.be.equal(IntentStatus.CANCELED)
			expect(intent2.status).to.be.equal(IntentStatus.CANCELED)
			expect(intent3.status).to.be.equal(IntentStatus.CANCELED)

			expect(await context.viewFacet.getPartyAOpenIntentIndex(1)).to.be.equal(0)
			expect(await context.viewFacet.getPartyAOpenIntentIndex(2)).to.be.equal(0)
			expect(await context.viewFacet.getPartyAOpenIntentIndex(3)).to.be.equal(0)

			let activeIntentIds: BigInt[] = await context.viewFacet.getActiveOpenIntentIds(partyA1.getSigner)
			for (let a of activeIntentIds) {
				expect(a).not.to.be.equal(1)
				expect(a).not.to.be.equal(2)
				expect(a).not.to.be.equal(3)
			}
		})
	})

	// After each intent sent, PatryA is Paying the fees and premium
	// Here we are testing the balance changes
	describe("sendOpenIntent Fee and premium management", async function () {
		beforeEach(async () => {})

		it("should fail on premium not locked on partyA isolatedLocked balance when margin is isolated", async function () {
			// take snapshot
			let isolatedLocketBalance = await context.viewFacet.getIsolatedLockedBalance(partyA1.getSigner, await context.collateral.getAddress())
			let isolatedBalance = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral.getAddress())

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(1))
				.price(700)
				.marginType(MarginType.ISOLATED)
				.build()

			expect(await partyA1.sendOpenIntent(request)).to.be.not.reverted

			const intent = await context.viewFacet.getOpenIntent(1)

			let premium = ethers.formatUnits((intent.tradeAgreements.quantity * intent.price).toString(), 18)
			const premiumFromView = await context.viewFacet.getOpenIntentPremium(1)
			// partyA pays the fees in so:
			// we are in isolated margin
			let isolatedLocketBalance2 = await context.viewFacet.getIsolatedLockedBalance(partyA1.getSigner, await context.collateral.getAddress())
			let isolatedBalance2 = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateral.getAddress())

			console.log("PartyA isolatedBalance:", isolatedBalance)
			console.log("PartyA Balance equals: isolatedBalance - isolatedLocketBalance2:", isolatedBalance - isolatedLocketBalance2)
			console.log("isolatedLocketBalance2 after sending intent:", isolatedLocketBalance2)
			console.log("isolatedLocketBalance before sending intent:", isolatedLocketBalance)
			console.log("isolatedLocketBalance before sending intent:", isolatedLocketBalance)
			console.log("Calculated premium:", premium)
			expect(isolatedLocketBalance2 - isolatedLocketBalance).to.be.equal(premiumFromView)
		})

		it("should fail on premium not locked on partyA cross Lock balance when margin is cross", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(1))
				.price(700)
				.marginType(MarginType.CROSS)
				.build()

			// take snapshot
			const symbol: SymbolStruct = await context.viewFacet.getSymbol(1)
			const crossBalance: CrossEntryStruct = await context.viewFacet.getCrossBalance(partyA1.getSigner, symbol.collateral, partyB1.getSigner)
			const isolatedBalance = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, symbol.collateral)

			expect(await partyA1.sendOpenIntent(request)).to.be.not.reverted

			const intent = await context.viewFacet.getOpenIntent(1)
			const premium = ethers.formatUnits((intent.tradeAgreements.quantity * intent.price).toString(), 18)
			const premiumFromView = await context.viewFacet.getOpenIntentPremium(intent.id)

			// take second snapshot
			const isolatedBalance2 = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateral.getAddress())
			const crossBalance2: CrossEntryStruct = await context.viewFacet.getCrossBalance(partyA1.getSigner, symbol.collateral, partyB1.getSigner)

			console.log("Before sending Intent:")
			console.log("PartyA cross locked balance:", crossBalance.locked)
			console.log("PartyA  isolated balance:", isolatedBalance)

			console.log("After sending Intent:")
			console.log("PartyA cross locked balance:", crossBalance2.locked)
			console.log("PartyA  isolated balance:", isolatedBalance2)
			console.log("Calculated premium:", premium)
			expect(BigInt(crossBalance2.locked) - BigInt(crossBalance.locked)).to.be.equal(premiumFromView)
		})

		it("should fail on Fee not paid accordingly when only one partyB whitelisted ", async function () {
			// take snapshot from Fee token
			let isolatedBalance = await context.viewFacet.getIsolatedBalance(partyA1.address, await context.collateralNL.getAddress())
			let isolatedLockeBalance = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, await context.collateralNL.getAddress())

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7000)
				.marginType(MarginType.ISOLATED)
				.tradeSide(TradeSide.BUY)
				.build()

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.01), closeFee: e(0.01) }])
			await context.controlFacet.setSymbolsPlatformFees([1], [{ openFee: e(0.01), closeFee: e(0.01) }])

			await expect(partyA1.sendOpenIntent(request)).not.to.reverted

			const intent = await context.viewFacet.getOpenIntent(1)
			const symbol: SymbolStruct = await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)
			const premiumFromView = await context.viewFacet.getOpenIntentPremium(1)
			const affiliateFeeFromView = await context.viewFacet.getOpenIntentAffiliateFee(intent.id)
			const platformFeeFromView = await context.viewFacet.getOpenIntentPlatformFee(1)
			const solverFee = request.solverFee.openFee

			const solverFeePaid =
				(intent.price * intent.tradeAgreements.quantity * intent.feeStructure.solverFee.openFee) /
				(intent.feeStructure.tokenPriceInCollateral * parseUnits("1", 18))

			// partyA pays the fees in so:
			// we are in isolated margin
			let isolatedBalance2 = await context.viewFacet.getIsolatedBalance(partyA1.address, await context.collateralNL.getAddress())
			let isolatedLockedBalance2 = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, await context.collateralNL.getAddress())

			console.log("PartyA isolated balance:", isolatedBalance)
			console.log("PartyA isolated balance after sending Intent:", isolatedBalance2)
			console.log("PartyA Locked balance:", isolatedLockeBalance)
			console.log("PartyA isolated locked balance after sending Intent:", isolatedLockedBalance2)
			console.log("Affiliate Fee paid:", affiliateFeeFromView)
			console.log("Platform Fee paid:", platformFeeFromView)
			console.log("Solver Fee:", solverFee)
			console.log("Trading Fee + Affiliate Fee + Solver Fee:", platformFeeFromView + affiliateFeeFromView + BigInt(solverFeePaid))
			console.log("Quantity: ", intent.tradeAgreements.quantity)
			console.log("price: ", intent.price)

			expect(isolatedLockedBalance2 - isolatedLockeBalance).to.be.equal(affiliateFeeFromView + platformFeeFromView + BigInt(solverFeePaid))
		})

		it("should fail on Fee not paid accordingly when more than one partyB whitelisted ", async function () {
			// take snapshot
			let isolatedBalance = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateralNL.getAddress())
			let isolatedLockedBalance = await context.viewFacet.getIsolatedLockedBalance(partyA1.getSigner, await context.collateralNL.getAddress())

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner, partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.marginType(MarginType.ISOLATED)
				.build()

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.01), closeFee: e(0.01) }])
			await context.controlFacet.setSymbolsPlatformFees([1], [{ openFee: e(0.01), closeFee: e(0.01) }])

			expect(await partyA1.sendOpenIntent(request)).not.to.reverted
			const intent = await context.viewFacet.getOpenIntent(1)

			// partyA pays the fees in so:
			// we are in isolated margin
			let isolatedBalance2 = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateralNL.getAddress())
			let isolatedLockedBalance2 = await context.viewFacet.getIsolatedLockedBalance(partyA1.getSigner, await context.collateralNL.getAddress())
			const symbol: SymbolStruct = await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)
			const feeTokenPriceInCollateral = await context.oracle.getPrice(context.collateral, symbol.collateral)
			const tradingFeeFromView = await context.viewFacet.getOpenIntentPlatformFee(1)
			const premiumFromView = await context.viewFacet.getOpenIntentPremium(1)
			const affiliateFeeFromView = await context.viewFacet.getOpenIntentAffiliateFee(intent.id)

			const solverFeePaid =
				(intent.price * intent.tradeAgreements.quantity * intent.feeStructure.solverFee.openFee) /
				(intent.feeStructure.tokenPriceInCollateral * parseUnits("1", 18))

			console.log("PartyA isolated balance:", isolatedBalance)
			console.log("PartyA isolated balance After sending Intent:", isolatedBalance2)
			console.log("tradingFee + affiliateFee + Solver Fee Paid:", tradingFeeFromView + affiliateFeeFromView + solverFeePaid)
			console.log("Fee Token Price:", feeTokenPriceInCollateral)
			console.log("Trading Fee From View:", tradingFeeFromView)
			console.log("Affiliate Fee From View:", affiliateFeeFromView)
			console.log("Solver Fee Paid:", solverFeePaid)
			console.log("Premium Fee From View:", premiumFromView)

			expect(intent.feeStructure.platformFee).to.deep.equal(symbol.platformFee)
			expect(isolatedLockedBalance2 - isolatedLockedBalance).to.be.equal(tradingFeeFromView + affiliateFeeFromView + solverFeePaid)
		})

		it("should fail on Fee not paid accordingly when in Cross mode", async function () {
			// take snapshot from Fee token
			let crossBalance: CrossEntryStruct = await context.viewFacet.getCrossBalance(
				partyA1.getSigner,
				await context.collateralNL.getAddress(),
				partyB1.getSigner,
			)

			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateralNL)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7000)
				.marginType(MarginType.CROSS)
				.build()

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.01), closeFee: e(0.01) }])
			await context.controlFacet.setSymbolsPlatformFees([1], [{ openFee: e(0.01), closeFee: e(0.01) }])

			expect(await partyA1.sendOpenIntent(request)).not.to.reverted
			const intent = await context.viewFacet.getOpenIntent(1)
			const symbol: SymbolStruct = await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)
			const premiumFromView = await context.viewFacet.getOpenIntentPremium(1)
			const affiliateFeeFromView = await context.viewFacet.getOpenIntentAffiliateFee(intent.id)
			const tradingFeeFromView = await context.viewFacet.getOpenIntentPlatformFee(1)

			// partyA pays the fees in so:
			// we are in isolated margin
			let crossBalance2: CrossEntryStruct = await context.viewFacet.getCrossBalance(
				partyA1.getSigner,
				await context.collateralNL.getAddress(),
				partyB1.getSigner,
			)

			const solverFeePaid =
				(intent.price * intent.tradeAgreements.quantity * intent.feeStructure.solverFee.openFee) /
				(intent.feeStructure.tokenPriceInCollateral * parseUnits("1", 18))

			console.log("PartyA cross balance:", crossBalance)
			console.log("PartyA cross balance after sending Intent:", crossBalance2)
			console.log("affiliateFee:", affiliateFeeFromView)
			console.log("tradingFee:", tradingFeeFromView)
			console.log("tradingFee + affiliateFee + Solver Fee Paid:", tradingFeeFromView + affiliateFeeFromView + solverFeePaid)
			console.log("Quantity: ", intent.tradeAgreements.quantity)
			console.log("price: ", intent.price)

			expect(BigInt(crossBalance2.locked) - BigInt(crossBalance.locked)).to.be.equal(affiliateFeeFromView + tradingFeeFromView + solverFeePaid)
		})
	})
}
