import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { PartyB } from "./models/partyB.model"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { IntentStatus, MarginType, TradeSide } from "./option-enums"
import { RunContext } from "./run-context"
import { e } from "../utils/e"
import { getLatestBlockTime } from "../utils/time"

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
const FIXTURE_PLATFORM_OPEN_FEE = e(0.01)
const FIXTURE_AFFILIATE_OPEN_FEE = e(0.01)

describe("Deferred PartyB sell escrow", function () {
	let context: RunContext
	let partyA1: PartyA
	let partyB1: PartyB
	let partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyA1.setBalances(context.collateral, e(100000), e(30000))
		await partyA1.setBalances(context.collateralNL, e(100000), e(30000))
		await partyB1.setBalances(context.collateral, e(100000), e(30000))
		await partyB1.setBalances(context.collateralNL, e(100000), e(30000))
		await partyB2.setBalances(context.collateral, e(100000), e(30000))
		await partyB2.setBalances(context.collateralNL, e(100000), e(30000))
	})

	async function deferredSellRequest(overrides: { quantity?: bigint; mm?: bigint; price?: bigint } = {}) {
		const latestBlock = await getLatestBlockTime()
		return openIntentRequestBuilder()
			.partyBsWhiteList([])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateralNL)
			.symbolId(1)
			.deadline(latestBlock + 140)
			.expirationTimestamp(latestBlock + 120)
			.exerciseFee({ cap: e(1), rate: "0" })
			.quantity(overrides.quantity ?? e(1))
			.tradeSide(TradeSide.SELL)
			.marginType(MarginType.CROSS)
			.price(overrides.price ?? e(10))
			.mm(overrides.mm ?? e(2))
			.solverFee({
				openFee: e(0.01),
				closeFee: e(0.01),
			})
			.build()
	}

	function openFeeAmount(quantity: bigint, price: bigint, rate: bigint) {
		return (quantity * price * rate) / e(1) / e(1)
	}

	function totalOpenFeeAmount(quantity: bigint, price: bigint, solverOpenFee: bigint) {
		return (
			openFeeAmount(quantity, price, FIXTURE_PLATFORM_OPEN_FEE) +
			openFeeAmount(quantity, price, FIXTURE_AFFILIATE_OPEN_FEE) +
			openFeeAmount(quantity, price, solverOpenFee)
		)
	}

	async function sendDeferredSell() {
		const request = await deferredSellRequest()
		await partyA1.sendOpenIntent(request)
		const intentId = await context.viewFacet.getLastOpenIntentId()
		return { request, intentId }
	}

	it("locks MM and fee escrow from isolated balances for a cross sell without a PartyB", async function () {
		const request = await deferredSellRequest()
		const collateral = await context.collateral.getAddress()
		const feeToken = await context.collateralNL.getAddress()

		const collateralLockedBefore = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedBefore = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)

		await expect(partyA1.sendOpenIntent(request)).not.to.be.reverted

		const intentId = await context.viewFacet.getLastOpenIntentId()
		const platformFee = await context.viewFacet.getOpenIntentPlatformFee(intentId)
		const affiliateFee = await context.viewFacet.getOpenIntentAffiliateFee(intentId)
		const solverFee =
			(BigInt(request.quantity.toString()) * BigInt(request.price.toString()) * BigInt(request.solverFee.openFee.toString())) / e(1) / e(1)

		const collateralLockedAfter = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedAfter = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)

		expect(collateralLockedAfter - collateralLockedBefore).to.equal(request.mm)
		expect(feeLockedAfter - feeLockedBefore).to.equal(platformFee + affiliateFee + solverFee)
	})

	it("fills by converting isolated escrow into the selected PartyB cross buckets", async function () {
		const { request, intentId } = await sendDeferredSell()
		const collateral = await context.collateral.getAddress()
		const feeToken = await context.collateralNL.getAddress()
		const fillPrice = e(12)

		const collateralLockedBefore = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedBefore = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)
		const escrowBeforeFill = await context.viewFacet.getOpenIntentEscrow(intentId)

		await partyB2.lockOpenIntent(intentId)
		await partyB2.fillOpenIntent(intentId, request.quantity, fillPrice)

		const trade = await context.viewFacet.getTrade(1)
		const escrow = await context.viewFacet.getOpenIntentEscrow(intentId)
		const partyACollateralCross = await context.viewFacet.getCrossBalance(partyA1.address, collateral, partyB2.address)
		const partyAFeeCross = await context.viewFacet.getCrossBalance(partyA1.address, feeToken, partyB2.address)
		const partyBFeeCross = await context.viewFacet.getCrossBalance(partyB2.address, feeToken, partyA1.address)
		const collateralLockedAfter = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedAfter = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)

		const premium = (BigInt(request.quantity.toString()) * fillPrice) / e(1)
		const solverFee = openFeeAmount(BigInt(request.quantity.toString()), fillPrice, BigInt(request.solverFee.openFee.toString()))

		expect(trade.partyA).to.equal(partyA1.address)
		expect(trade.partyB).to.equal(partyB2.address)
		expect(escrow.exists).to.equal(false)
		expect(collateralLockedAfter).to.equal(collateralLockedBefore - BigInt(request.mm.toString()))
		expect(feeLockedAfter).to.equal(feeLockedBefore - escrowBeforeFill.feeLockAmount)
		expect(partyACollateralCross.totalMM).to.equal(request.mm)
		expect(partyACollateralCross.balance).to.equal(BigInt(request.mm.toString()) + premium)
		expect(partyAFeeCross.balance).to.equal(0)
		expect(partyBFeeCross.balance).to.equal(solverFee)
	})

	it("partially fills by consuming pro-rata escrow and carrying the residual escrow to a child intent", async function () {
		const request = await deferredSellRequest({ quantity: e(4), mm: e(8) })
		await partyA1.sendOpenIntent(request)
		const intentId = await context.viewFacet.getLastOpenIntentId()
		const collateral = await context.collateral.getAddress()
		const feeToken = await context.collateralNL.getAddress()
		const fillQuantity = e(1)
		const fillPrice = e(12)
		const originalQuantity = BigInt(request.quantity.toString())
		const originalMM = BigInt(request.mm.toString())
		const solverOpenFee = BigInt(request.solverFee.openFee.toString())
		const consumedMM = (originalMM * fillQuantity) / originalQuantity
		const consumedLimitFee = totalOpenFeeAmount(fillQuantity, BigInt(request.price.toString()), solverOpenFee)

		const collateralLockedBefore = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedBefore = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)
		const escrowBeforeFill = await context.viewFacet.getOpenIntentEscrow(intentId)

		await partyB1.lockOpenIntent(intentId)
		await partyB1.fillOpenIntent(intentId, fillQuantity, fillPrice)

		const childIntentId = await context.viewFacet.getLastOpenIntentId()
		const originalIntent = await context.viewFacet.getOpenIntent(intentId)
		const childIntent = await context.viewFacet.getOpenIntent(childIntentId)
		const trade = await context.viewFacet.getTrade(1)
		const originalEscrow = await context.viewFacet.getOpenIntentEscrow(intentId)
		const childEscrow = await context.viewFacet.getOpenIntentEscrow(childIntentId)
		const partyACollateralCross = await context.viewFacet.getCrossBalance(partyA1.address, collateral, partyB1.address)
		const partyAFeeCross = await context.viewFacet.getCrossBalance(partyA1.address, feeToken, partyB1.address)
		const partyBFeeCross = await context.viewFacet.getCrossBalance(partyB1.address, feeToken, partyA1.address)

		const premium = (fillQuantity * fillPrice) / e(1)
		const solverFee = openFeeAmount(fillQuantity, fillPrice, solverOpenFee)

		expect(originalIntent.status).to.equal(IntentStatus.FILLED)
		expect(originalIntent.tradeAgreements.quantity).to.equal(fillQuantity)
		expect(trade.tradeAgreements.quantity).to.equal(fillQuantity)
		expect(trade.tradeAgreements.mm).to.equal(consumedMM)
		expect(originalEscrow.exists).to.equal(false)

		expect(childIntentId).to.equal(intentId + 1n)
		expect(childIntent.parentId).to.equal(intentId)
		expect(childIntent.status).to.equal(IntentStatus.PENDING)
		expect(childIntent.partyB).to.equal(ZERO_ADDRESS)
		expect(childIntent.partyBsWhiteList.length).to.equal(0)
		expect(childIntent.tradeAgreements.quantity).to.equal(originalQuantity - fillQuantity)
		expect(childIntent.tradeAgreements.mm).to.equal(originalMM - consumedMM)
		expect(await context.viewFacet.isDeferredPartyBSellIntent(childIntentId)).to.equal(true)

		expect(childEscrow.exists).to.equal(true)
		expect(childEscrow.partyA).to.equal(partyA1.address)
		expect(childEscrow.collateral).to.equal(collateral)
		expect(childEscrow.feeToken).to.equal(feeToken)
		expect(childEscrow.mm).to.equal(escrowBeforeFill.mm - consumedMM)
		expect(childEscrow.feeLockAmount).to.equal(escrowBeforeFill.feeLockAmount - consumedLimitFee)

		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)).to.equal(collateralLockedBefore - consumedMM)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)).to.equal(feeLockedBefore - consumedLimitFee)
		expect(partyACollateralCross.totalMM).to.equal(consumedMM)
		expect(partyACollateralCross.balance).to.equal(consumedMM + premium)
		expect(partyAFeeCross.balance).to.equal(0)
		expect(partyBFeeCross.balance).to.equal(solverFee)
	})

	it("allows the residual child escrow to be filled by a different PartyB", async function () {
		const request = await deferredSellRequest({ quantity: e(4), mm: e(8) })
		await partyA1.sendOpenIntent(request)
		const intentId = await context.viewFacet.getLastOpenIntentId()
		const collateral = await context.collateral.getAddress()
		const feeToken = await context.collateralNL.getAddress()
		const firstFillQuantity = e(1)

		await partyB1.lockOpenIntent(intentId)
		await partyB1.fillOpenIntent(intentId, firstFillQuantity, e(12))

		const childIntentId = await context.viewFacet.getLastOpenIntentId()
		const childIntentBeforeFill = await context.viewFacet.getOpenIntent(childIntentId)
		const childEscrowBeforeFill = await context.viewFacet.getOpenIntentEscrow(childIntentId)
		const collateralLockedBeforeChildFill = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedBeforeChildFill = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)

		await partyB2.lockOpenIntent(childIntentId)
		await partyB2.fillOpenIntent(childIntentId, childIntentBeforeFill.tradeAgreements.quantity, e(15))

		const childIntentAfterFill = await context.viewFacet.getOpenIntent(childIntentId)
		const childEscrowAfterFill = await context.viewFacet.getOpenIntentEscrow(childIntentId)
		const secondTrade = await context.viewFacet.getTrade(2)
		const partyB1CollateralCross = await context.viewFacet.getCrossBalance(partyA1.address, collateral, partyB1.address)
		const partyB2CollateralCross = await context.viewFacet.getCrossBalance(partyA1.address, collateral, partyB2.address)

		expect(childIntentAfterFill.status).to.equal(IntentStatus.FILLED)
		expect(childEscrowAfterFill.exists).to.equal(false)
		expect(secondTrade.partyB).to.equal(partyB2.address)
		expect(secondTrade.tradeAgreements.quantity).to.equal(childIntentBeforeFill.tradeAgreements.quantity)
		expect(secondTrade.tradeAgreements.mm).to.equal(childEscrowBeforeFill.mm)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)).to.equal(
			collateralLockedBeforeChildFill - childEscrowBeforeFill.mm,
		)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)).to.equal(
			feeLockedBeforeChildFill - childEscrowBeforeFill.feeLockAmount,
		)
		expect(partyB1CollateralCross.totalMM).to.equal(e(2))
		expect(partyB2CollateralCross.totalMM).to.equal(e(6))
	})

	it("releases the residual child escrow when PartyA cancels it after a partial fill", async function () {
		const request = await deferredSellRequest({ quantity: e(4), mm: e(8) })
		await partyA1.sendOpenIntent(request)
		const intentId = await context.viewFacet.getLastOpenIntentId()
		const collateral = await context.collateral.getAddress()
		const feeToken = await context.collateralNL.getAddress()

		await partyB1.lockOpenIntent(intentId)
		await partyB1.fillOpenIntent(intentId, e(1), e(12))

		const childIntentId = await context.viewFacet.getLastOpenIntentId()
		const childEscrowBeforeCancel = await context.viewFacet.getOpenIntentEscrow(childIntentId)
		const collateralLockedBeforeCancel = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedBeforeCancel = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)

		await partyA1.sendCancelOpenIntent([childIntentId])

		const childIntent = await context.viewFacet.getOpenIntent(childIntentId)
		const childEscrowAfterCancel = await context.viewFacet.getOpenIntentEscrow(childIntentId)
		expect(childIntent.status).to.equal(IntentStatus.CANCELED)
		expect(childEscrowAfterCancel.exists).to.equal(false)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)).to.equal(
			collateralLockedBeforeCancel - childEscrowBeforeCancel.mm,
		)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)).to.equal(
			feeLockedBeforeCancel - childEscrowBeforeCancel.feeLockAmount,
		)
	})

	it("releases residual escrow when a cancel-pending deferred sell is partially filled", async function () {
		const request = await deferredSellRequest({ quantity: e(4), mm: e(8) })
		await partyA1.sendOpenIntent(request)
		const intentId = await context.viewFacet.getLastOpenIntentId()
		const collateral = await context.collateral.getAddress()
		const feeToken = await context.collateralNL.getAddress()
		const fillQuantity = e(1)
		const fillPrice = e(12)

		await partyB1.lockOpenIntent(intentId)
		const escrowBeforeCancel = await context.viewFacet.getOpenIntentEscrow(intentId)
		const collateralLockedBeforeCancel = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedBeforeCancel = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)

		await partyA1.sendCancelOpenIntent([intentId])
		await partyB1.fillOpenIntent(intentId, fillQuantity, fillPrice)

		const childIntentId = await context.viewFacet.getLastOpenIntentId()
		const originalIntent = await context.viewFacet.getOpenIntent(intentId)
		const childIntent = await context.viewFacet.getOpenIntent(childIntentId)
		const originalEscrow = await context.viewFacet.getOpenIntentEscrow(intentId)
		const childEscrow = await context.viewFacet.getOpenIntentEscrow(childIntentId)
		const partyACollateralCross = await context.viewFacet.getCrossBalance(partyA1.address, collateral, partyB1.address)

		expect(originalIntent.status).to.equal(IntentStatus.FILLED)
		expect(childIntent.status).to.equal(IntentStatus.CANCELED)
		expect(originalEscrow.exists).to.equal(false)
		expect(childEscrow.exists).to.equal(false)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)).to.equal(
			collateralLockedBeforeCancel - escrowBeforeCancel.mm,
		)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)).to.equal(
			feeLockedBeforeCancel - escrowBeforeCancel.feeLockAmount,
		)
		expect(partyACollateralCross.totalMM).to.equal(e(2))
	})

	it("releases escrow when PartyA cancels a pending deferred sell", async function () {
		const { intentId } = await sendDeferredSell()
		const collateral = await context.collateral.getAddress()
		const feeToken = await context.collateralNL.getAddress()

		const collateralLockedBeforeCancel = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedBeforeCancel = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)
		const escrowBeforeCancel = await context.viewFacet.getOpenIntentEscrow(intentId)

		await partyA1.sendCancelOpenIntent([intentId])

		const intent = await context.viewFacet.getOpenIntent(intentId)
		const escrowAfterCancel = await context.viewFacet.getOpenIntentEscrow(intentId)
		const collateralLockedAfterCancel = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedAfterCancel = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)

		expect(intent.status).to.equal(IntentStatus.CANCELED)
		expect(escrowAfterCancel.exists).to.equal(false)
		expect(collateralLockedAfterCancel).to.equal(collateralLockedBeforeCancel - escrowBeforeCancel.mm)
		expect(feeLockedAfterCancel).to.equal(feeLockedBeforeCancel - escrowBeforeCancel.feeLockAmount)
	})

	it("keeps escrow locked during cancel-pending and releases it when PartyB accepts", async function () {
		const { intentId } = await sendDeferredSell()
		const collateral = await context.collateral.getAddress()
		const feeToken = await context.collateralNL.getAddress()

		await partyB1.lockOpenIntent(intentId)

		const collateralLockedBeforeCancel = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedBeforeCancel = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)
		const escrowBeforeCancel = await context.viewFacet.getOpenIntentEscrow(intentId)

		await partyA1.sendCancelOpenIntent([intentId])

		const cancelPendingIntent = await context.viewFacet.getOpenIntent(intentId)
		expect(cancelPendingIntent.status).to.equal(IntentStatus.CANCEL_PENDING)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)).to.equal(collateralLockedBeforeCancel)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)).to.equal(feeLockedBeforeCancel)

		await partyB1.acceptCancelOpenIntent(intentId)

		const canceledIntent = await context.viewFacet.getOpenIntent(intentId)
		const escrowAfterAccept = await context.viewFacet.getOpenIntentEscrow(intentId)
		expect(canceledIntent.status).to.equal(IntentStatus.CANCELED)
		expect(escrowAfterAccept.exists).to.equal(false)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)).to.equal(
			collateralLockedBeforeCancel - escrowBeforeCancel.mm,
		)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)).to.equal(
			feeLockedBeforeCancel - escrowBeforeCancel.feeLockAmount,
		)
	})

	it("releases escrow on expiry", async function () {
		const { intentId } = await sendDeferredSell()
		const collateral = await context.collateral.getAddress()
		const feeToken = await context.collateralNL.getAddress()
		const escrowBeforeExpire = await context.viewFacet.getOpenIntentEscrow(intentId)
		const collateralLockedBeforeExpire = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedBeforeExpire = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)

		await time.increase(141)
		await partyA1.expireOpenIntent([intentId])

		const intent = await context.viewFacet.getOpenIntent(intentId)
		const escrowAfterExpire = await context.viewFacet.getOpenIntentEscrow(intentId)

		expect(intent.status).to.equal(IntentStatus.EXPIRED)
		expect(escrowAfterExpire.exists).to.equal(false)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)).to.equal(
			collateralLockedBeforeExpire - escrowBeforeExpire.mm,
		)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)).to.equal(
			feeLockedBeforeExpire - escrowBeforeExpire.feeLockAmount,
		)
	})

	it("releases escrow on force cancel", async function () {
		const { intentId } = await sendDeferredSell()
		const collateral = await context.collateral.getAddress()
		const feeToken = await context.collateralNL.getAddress()

		await context.controlFacet.setForceCancelOpenIntentTimeout(1)
		await partyB1.lockOpenIntent(intentId)
		await partyA1.sendCancelOpenIntent([intentId])

		const escrowBeforeForceCancel = await context.viewFacet.getOpenIntentEscrow(intentId)
		const collateralLockedBeforeForceCancel = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)
		const feeLockedBeforeForceCancel = await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)

		await time.increase(2)
		await partyA1.forceCancelOpenIntent(intentId.toString())

		const intent = await context.viewFacet.getOpenIntent(intentId)
		const escrowAfterForceCancel = await context.viewFacet.getOpenIntentEscrow(intentId)

		expect(intent.status).to.equal(IntentStatus.CANCELED)
		expect(escrowAfterForceCancel.exists).to.equal(false)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, collateral)).to.equal(
			collateralLockedBeforeForceCancel - escrowBeforeForceCancel.mm,
		)
		expect(await context.viewFacet.getIsolatedLockedBalance(partyA1.address, feeToken)).to.equal(
			feeLockedBeforeForceCancel - escrowBeforeForceCancel.feeLockAmount,
		)
	})

	it("keeps other broadcast modes rejected in v1", async function () {
		const crossBuy = { ...(await deferredSellRequest()), tradeSide: TradeSide.BUY }
		const multiPartySell = { ...(await deferredSellRequest()), partyBsWhiteList: [partyB1.address, partyB2.address] }
		const isolatedSell = { ...(await deferredSellRequest()), marginType: MarginType.ISOLATED }

		await expect(partyA1.sendOpenIntent(crossBuy)).to.be.revertedWithCustomError(context.partyAOpenFacet, "MultiplePartyBNotAllowed")
		await expect(partyA1.sendOpenIntent(multiPartySell)).to.be.revertedWithCustomError(context.partyAOpenFacet, "MultiplePartyBNotAllowed")
		await expect(partyA1.sendOpenIntent(isolatedSell)).to.be.revertedWithCustomError(context.partyAOpenFacet, "IsolatedModeSellNotAllowed")
	})

	it("rejects deferred sells from a PartyA bound to a PartyB", async function () {
		await partyA1.bindToCounterParty(partyB1.address)

		await expect(partyA1.sendOpenIntent(await deferredSellRequest())).to.be.revertedWithCustomError(
			context.partyAOpenFacet,
			"DeferredSellNotAllowedForBoundPartyA",
		)
	})
})
