import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"

import { initializeTestFixture } from "./initialize-test.fixture"
import { hashSignedSimpleActionIntent } from "./utils/hash"

import { RunContext } from "./run-context"
import { PartyA } from "./models/partyA.model"
import { PartyB } from "./models/partyB.model"
import { e } from "../utils/e"
import { getLatestBlockTime } from "../utils/time"
import { signedSimpleActionIntentBuilder } from "./models/builders/signed-simple-action-intent.builder"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"

export function shouldBehaveLikeInstantActionCloseFacet(): void {
	let context: RunContext
	let partyA1: PartyA
	let partyA2: PartyA
	let partyB1: PartyB
	let partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyA1.setBalances(undefined, "500", "500")

		await context.controlFacet.setPartyBConfig(partyB1.getSigner, {
			isActive: true,
			lossCoverage: 0,
			oracleId: 1,
			symbolType: 0,
		})

		await context.controlFacet.setAffiliateStatus(context.signers.others[0], true)

		await partyB1.setBalances(undefined, e(100000), e(100000))
		await partyA1.setBalances(undefined, e(100000), e(100000))
	})

	describe("instantCancelCloseIntent", function () {
		beforeEach(async () => {
			await context.controlFacet.setMaxTradePerPartyA(3)
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.expirationTimestamp(latestBlock + 120)
				.deadline(latestBlock + 150)
				.symbolId(1)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(0) // 0 Isolated, 1 Cross
				.tradeSide(0) // 0 Buy, 1 Sell
				.quantity(e(100))
				.price(7)
				.build()

			// Create and fill open intent
			await partyA1.sendOpenIntent(request)
			await partyB1.lockOpenIntent(1)
			await partyB1.fillOpenIntent(1, e(100), 7)
			await partyA1.sendCloseIntent(1, e(100), 7, latestBlock + 120)
		})

		it("Should fail when partyB actions paused", async function () {
			await context.controlFacet.pausePartyBActions()

			const signedCancelCloseIntent = signedSimpleActionIntentBuilder().signer(partyA1.address).build()
			const signedAcceptCancelCloseIntent = signedSimpleActionIntentBuilder().signer(partyB1.address).build()

			const signedCancelCloseIntentHash = hashSignedSimpleActionIntent(
				signedCancelCloseIntent,
				"CancelClose",
				context.common.chainId,
				context.common.diamondAddress,
			)
			const signedAcceptCancelOpenIntentHash = hashSignedSimpleActionIntent(
				signedAcceptCancelCloseIntent,
				"AcceptCancelClose",
				context.common.chainId,
				context.common.diamondAddress,
			)

			await expect(
				context.instantActionCloseFacet
					.connect(partyA1.getSigner)
					.instantCancelCloseIntent(
						signedCancelCloseIntent,
						await partyA1.sign(signedCancelCloseIntentHash),
						signedAcceptCancelCloseIntent,
						await partyB1.sign(signedAcceptCancelOpenIntentHash),
					),
			).to.be.revertedWithCustomError(context.instantActionCloseFacet, "PartyBActionsPaused")
		})

		it("Should fail when thirdParty actions paused", async function () {
			await context.controlFacet.pauseThirdPartyActions()

			const signedCancelCloseIntent = signedSimpleActionIntentBuilder().signer(partyA1.address).build()
			const signedAcceptCancelCloseIntent = signedSimpleActionIntentBuilder().signer(partyB1.address).build()

			const signedCancelCloseIntentHash = hashSignedSimpleActionIntent(
				signedCancelCloseIntent,
				"CancelClose",
				context.common.chainId,
				context.common.diamondAddress,
			)
			const signedAcceptCancelOpenIntentHash = hashSignedSimpleActionIntent(
				signedAcceptCancelCloseIntent,
				"AcceptCancelClose",
				context.common.chainId,
				context.common.diamondAddress,
			)

			await expect(
				context.instantActionCloseFacet
					.connect(partyA1.getSigner)
					.instantCancelCloseIntent(
						signedCancelCloseIntent,
						await partyA1.sign(signedCancelCloseIntentHash),
						signedAcceptCancelCloseIntent,
						await partyB1.sign(signedAcceptCancelOpenIntentHash),
					),
			).to.be.revertedWithCustomError(context.instantActionCloseFacet, "ThirdPartyActionsPaused")
		})

		it("Should fail when partyA signature is invalid", async function () {
			const signedCancelCloseIntent = signedSimpleActionIntentBuilder().signer(partyA2.address).build()
			const signedAcceptCancelCloseIntent = signedSimpleActionIntentBuilder().signer(partyB1.address).build()

			const signedCancelCloseIntentHash = hashSignedSimpleActionIntent(
				signedCancelCloseIntent,
				"CancelClose",
				context.common.chainId,
				context.common.diamondAddress,
			)
			const signedAcceptCancelOpenIntentHash = hashSignedSimpleActionIntent(
				signedAcceptCancelCloseIntent,
				"AcceptCancelClose",
				context.common.chainId,
				context.common.diamondAddress,
			)

			await expect(
				context.instantActionCloseFacet
					.connect(partyA1.getSigner)
					.instantCancelCloseIntent(
						signedCancelCloseIntent,
						await partyA1.sign(signedCancelCloseIntentHash),
						signedAcceptCancelCloseIntent,
						await partyB1.sign(signedAcceptCancelOpenIntentHash),
					),
			).to.be.revertedWithCustomError(context.instantActionCloseFacet, "InvalidSignature")
		})

		it("Should fail when partyB signature is invalid", async function () {
			const signedCancelCloseIntent = signedSimpleActionIntentBuilder().signer(partyA1.address).build()
			const signedAcceptCancelCloseIntent = signedSimpleActionIntentBuilder().signer(partyB2.address).build()

			const signedCancelCloseIntentHash = hashSignedSimpleActionIntent(
				signedCancelCloseIntent,
				"CancelClose",
				context.common.chainId,
				context.common.diamondAddress,
			)
			const signedAcceptCancelOpenIntentHash = hashSignedSimpleActionIntent(
				signedAcceptCancelCloseIntent,
				"AcceptCancelClose",
				context.common.chainId,
				context.common.diamondAddress,
			)

			await expect(
				context.instantActionCloseFacet
					.connect(partyA1.getSigner)
					.instantCancelCloseIntent(
						signedCancelCloseIntent,
						await partyA1.sign(signedCancelCloseIntentHash),
						signedAcceptCancelCloseIntent,
						await partyB1.sign(signedAcceptCancelOpenIntentHash),
					),
			).to.be.revertedWithCustomError(context.instantActionCloseFacet, "InvalidSignature")
		})

		it("Should instant cancel close intent successfully", async function () {
			const signedCancelCloseIntent = signedSimpleActionIntentBuilder().signer(partyA1.address).build()
			const signedAcceptCancelCloseIntent = signedSimpleActionIntentBuilder().signer(partyB1.address).build()

			const signedCancelCloseIntentHash = hashSignedSimpleActionIntent(
				signedCancelCloseIntent,
				"CancelClose",
				context.common.chainId,
				context.common.diamondAddress,
			)
			const signedAcceptCancelOpenIntentHash = hashSignedSimpleActionIntent(
				signedAcceptCancelCloseIntent,
				"AcceptCancelClose",
				context.common.chainId,
				context.common.diamondAddress,
			)

			expect(
				await context.instantActionCloseFacet
					.connect(partyA1.getSigner)
					.instantCancelCloseIntent(
						signedCancelCloseIntent,
						await partyA1.sign(signedCancelCloseIntentHash),
						signedAcceptCancelCloseIntent,
						await partyB1.sign(signedAcceptCancelOpenIntentHash),
					),
			).to.not.reverted

			const intent = await context.viewFacet.getCloseIntent(1)

			expect(intent.status).to.equal(3) // 3 is Cancelled
		})
	})
}
