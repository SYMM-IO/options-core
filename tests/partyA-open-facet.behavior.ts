import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { ZeroAddress } from "ethers"
import { IntentStatus, MarginType, TradeSide } from "./option-enums"
import { OpenIntentStruct, SymbolStruct } from "../types/contracts/interfaces/ISymmio"
import { BigNumber } from "@ethersproject/bignumber"
import { bigint, int } from "hardhat/internal/core/params/argumentTypes"
import { partyAOpen } from "../types/contracts/facets"
import { CrossEntryStruct } from "../types/contracts/facets/ViewFacet/VeiwFacet.sol/ViewFacet"
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
			await context.controlFacet.addOracle("test orancel", context.signers.others[0])
			await context.controlFacet.addSymbol("BTC", 0, 1, context.collateral.getAddress(), 0, 0)
		})

		it("Should fail when partyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "PartyAActionsPaused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "GlobalPaused")
		})

		it("Should fail when symbolId be wrong", async function () {
			const latestBlock = await getLatestBlockTime()

			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.expirationTimestamp(latestBlock + 100)
				.deadline(latestBlock + 100)
				.symbolId(1)
				.build()

			await context.controlFacet.setSymbolState(1, false)

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InvalidSymbol")
		})

		it("Should fail when deadline be low", async function () {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "ExpirationTimestampPassed")
		})

		it("Should fail when expiration timestamp be low", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
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
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(2), rate: "0" })
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InvalidExerciseFee")
		})

		it("Should fail when instance mode is active", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await context.controlFacet.setInstantActionsMode(partyA1.getSigner, true)
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InstantModeActive")
		})

		it("Should fail when affiliate be zero address or invalid", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.feeToken(context.collateral)
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

		it("Should fail when partyA bound to a partyB that is not in whitelisted partyB", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(partyB1.getSigner)
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "BoundedToAnotherPartyB")
		})

		it("Should fail when sender in whitelisted partyB", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyA1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InvalidWhitelistEntry")
		})

		it("Should fail when partyA sends Short intent with isolated margin", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner, context.signers.partyB1])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.ISOLATED)
				.tradeSide(TradeSide.SELL)
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "IsolatedModeSellNotAllowed")
		})

		it("Should fail when partyA have more than 1 PartyB in cross margin ", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner, context.signers.partyB1])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
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
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.SELL)
				.build()

			//TODO ::: it is implemented after clearing house development

			// await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "NotSolvent")
		})

		it("Should fail when partyB is not solvent in cross/Isolated margin", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.CROSS)
				.tradeSide(TradeSide.SELL)
				.build()

			//TODO ::: it is implemented after clearing house development

			// await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "NotSolvent")
		})

		it("Should fail when partyB whiteListed and available balance be insufficient", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100000000))
				.price(e(200))
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InsufficientBalance")
		})

		it("should fail when partyA have intent with 0 quantity", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(0))
				.price(7)
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "ZeroQuantity")
			//TODO ::: intent with quantity zero?
		})

		it("Should fail when partyB not whiteListed and available balance be insufficient", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner, context.signers.partyB1])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100000000))
				.price(e(200))
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWithCustomError(context.partyAOpenFacet, "InsufficientBalance")
		})

		it("Should fail when partyB whiteListed and available balance be insufficient", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline(latestBlock + 120)
				.expirationTimestamp(latestBlock + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build()

			expect(await partyA1.sendOpenIntent(request)).to.be.not.reverted

			const intent = await context.viewFacet.getOpenIntent(1)

			expect(intent.tradeId).to.be.equal(0)
			expect(intent.partyBsWhiteList).to.be.deep.equal([await partyB1.getSigner.getAddress()])
			expect(intent.tradeAgreements.symbolId).to.be.equal(1)
			expect(intent.price).to.be.equal(7)
			expect(intent.tradeAgreements.quantity).to.be.equal(e(100))
			expect(intent.tradeAgreements.strikePrice).to.be.equal(1)
			expect(intent.tradeAgreements.expirationTimestamp).to.be.equal(latestBlock + 120)
			expect(intent.tradeAgreements.exerciseFee.cap).to.be.equal(e(1))
			expect(intent.tradeAgreements.exerciseFee.rate).to.be.equal(0)
			expect(intent.partyA).to.be.equal(await partyA1.getSigner.getAddress())
			expect(intent.partyB).to.be.equal(ZeroAddress)
			expect(intent.status).to.be.equal(0) // IntentStatus.PENDING
			expect(intent.parentId).to.be.equal(0)
			// expect(intent.createTimestamp).to.be.equallatestBlock
			// expect(intent.status).to.be.equallatestBlock
			expect(intent.deadline).to.be.equal(latestBlock + 120)
			// expect(intent.tradingFee).to.be.equal(0)
			expect(intent.affiliate).to.be.equal(await context.signers.affiliate1.getAddress())

			// expect(await context.viewFacet.lockedBalancesOf(partyA1.getSigner, context.collateral.getAddress())).to.be.equal(700)
		})
	})

	describe("cancelOpenIntent", async function () {
		beforeEach(async () => {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
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

		it("Should release premium", async () => {
			// take snapshot
			let isolatedLocketBalance = await context.viewFacet.getIsolatedLockedBalance(partyA1.getSigner, await context.collateral.getAddress())
			let isolatedBalance = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral.getAddress())
			let premium: BigInt = await context.viewFacet.getPremium(1)

			expect(await partyA1.sendCancelOpenIntent(["1"])).to.be.not.reverted

			let isolatedLocketBalanceLatter = await context.viewFacet.getIsolatedLockedBalance(partyA1.getSigner, await context.collateral.getAddress())
			let isolatedBalanceLatter = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral.getAddress())

			expect(isolatedLocketBalance - isolatedLocketBalanceLatter).be.equal(premium)
		})

		it("Should be removed when canceled with pending state", async function () {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.expirationTimestamp(latestBlock + 120)
				.deadline(latestBlock + 100)
				.symbolId(1)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(0) // 0 Isolated, 1 Cross
				.tradeSide(0) // 0 Buy, 1 Sell
				.quantity(e(100))
				.price(7)
				.build()
			expect(await partyA1.sendOpenIntent(request)).not.to.be.reverted
			expect(await partyA1.sendOpenIntent(request)).not.to.be.reverted

			expect(await partyA1.sendCancelOpenIntent(["1"])).not.to.be.reverted
			let activeIntentIds: BigInt[] = await context.viewFacet.getActiveOpenIntentIds(partyA1.getSigner)
			for (let a of activeIntentIds) {
				expect(a).not.to.be.equal(1)
			}
			expect(await context.viewFacet.getPartyAOpenIntentIndex(1)).to.be.equal(0)
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
				.feeToken(context.collateral)
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
			const premiumFromView = await context.viewFacet.getPremium(1)
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
			const premiumFromView = await context.viewFacet.getPremium(intent.id)

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
			let isolatedBalance = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateralNL.getAddress())

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
				.price(7)
				.marginType(MarginType.ISOLATED)
				.build()

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, 1, e(50))
			await context.controlFacet.setSymbolTradingFee(1, e(100))

			expect(await partyA1.sendOpenIntent(request)).not.to.reverted
			const intent = await context.viewFacet.getOpenIntent(1)
			const symbol: SymbolStruct = await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)
			const premiumFromView = await context.viewFacet.getPremium(1)
			const affiliateFeeFromView = await context.viewFacet.getAffiliateFee(intent.affiliate, symbol.symbolId)
			const tradingFeeFromView = await context.viewFacet.getTradingFee(1)

			// partyA pays the fees in so:
			// we are in isolated margin
			let isolatedBalance2 = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateralNL.getAddress())

			console.log("PartyA isolated balance:", isolatedBalance)
			console.log("PartyA isolated balance after sending Intent:", isolatedBalance2)
			console.log("affiliateFee:", affiliateFeeFromView)
			console.log("tradingFee:", tradingFeeFromView)
			console.log("tradingFee + affiliateFee:", tradingFeeFromView + affiliateFeeFromView)
			console.log("Quantity: ", intent.tradeAgreements.quantity)
			console.log("price: ", intent.price)

			expect(isolatedBalance - isolatedBalance2).to.be.equal(affiliateFeeFromView + tradingFeeFromView)
		})

		it("should fail on Fee not paid accordingly when more than one partyB whitelisted ", async function () {
			// take snapshot
			let isolatedBalance = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateralNL.getAddress())

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

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, 1, e(50))
			await context.controlFacet.setSymbolTradingFee(1, e(100))

			expect(await partyA1.sendOpenIntent(request)).not.to.reverted
			const intent = await context.viewFacet.getOpenIntent(1)

			// partyA pays the fees in so:
			// we are in isolated margin
			let isolatedBalance2 = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateralNL.getAddress())
			const symbol: SymbolStruct = await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)
			const feeTokenPriceInCollateral = await context.oracle.getPrice(context.collateral, symbol.collateral)
			const tradingFeeFromView = await context.viewFacet.getTradingFee(1)
			const premiumFromView = await context.viewFacet.getPremium(1)
			const affiliateFeeFromView = await context.viewFacet.getAffiliateFee(intent.affiliate, symbol.symbolId)

			console.log("PartyA isolated balance:", isolatedBalance)
			console.log("PartyA isolated balance After sending Intent:", isolatedBalance2)
			console.log("tradingFee + affiliateFee:", tradingFeeFromView + affiliateFeeFromView)
			console.log("Fee Token Price:", feeTokenPriceInCollateral)
			console.log("Trading Fee From View:", tradingFeeFromView)
			console.log("Affiliate Fee From View:", affiliateFeeFromView)
			console.log("Premium Fee From View:", premiumFromView)

			expect(intent.tradingFee.platformFee).to.equal(symbol.tradingFee)
			expect(isolatedBalance - isolatedBalance2).to.be.equal(tradingFeeFromView + affiliateFeeFromView)
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
				.price(7)
				.marginType(MarginType.CROSS)
				.build()

			await context.controlFacet.setAffiliateFees(context.signers.affiliate1, 1, e(50))
			await context.controlFacet.setSymbolTradingFee(1, e(100))

			expect(await partyA1.sendOpenIntent(request)).not.to.reverted
			const intent = await context.viewFacet.getOpenIntent(1)
			const symbol: SymbolStruct = await context.viewFacet.getSymbol(intent.tradeAgreements.symbolId)
			const premiumFromView = await context.viewFacet.getPremium(1)
			const affiliateFeeFromView = await context.viewFacet.getAffiliateFee(intent.affiliate, symbol.symbolId)
			const tradingFeeFromView = await context.viewFacet.getTradingFee(1)

			// partyA pays the fees in so:
			// we are in isolated margin
			let crossBalance2: CrossEntryStruct = await context.viewFacet.getCrossBalance(
				partyA1.getSigner,
				await context.collateralNL.getAddress(),
				partyB1.getSigner,
			)

			console.log("PartyA cross balance:", crossBalance.balance)
			console.log("PartyA cross balance after sending Intent:", crossBalance2.balance)
			console.log("affiliateFee:", affiliateFeeFromView)
			console.log("tradingFee:", tradingFeeFromView)
			console.log("tradingFee + affiliateFee:", tradingFeeFromView + affiliateFeeFromView)
			console.log("Quantity: ", intent.tradeAgreements.quantity)
			console.log("price: ", intent.price)

			expect(BigInt(crossBalance2.balance) - BigInt(crossBalance.balance)).to.be.equal(-affiliateFeeFromView - tradingFeeFromView)
		})
	})
}
