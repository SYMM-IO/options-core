import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { ethers } from "hardhat"

import { initializeTestFixture } from "./initialize-test.fixture"
import { signedOpenIntentBuilder } from "./models/builders/signed-open-intent.builder"
import { signedFillIntentBuilder } from "./models/builders/signed-fill-intent.builder"
import { hashSignedOpenIntent, hashSignedFillOpenIntent, hashSignedCancelOpenIntent, hashSignedAcceptCancelOpenIntent } from "./utils/hash"

import { RunContext } from "./run-context"
import { PartyA } from "./models/partyA.model"
import { PartyB } from "./models/partyB.model"
import { e } from "../utils/e"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { MarginType } from "./option-enums"
import { signedSimpleActionIntentBuilder } from "./models/builders/signed-simple-action-intent.builder"
import { getCurrentLatestBlockTime } from "../utils/time"

export function shouldBehaveLikeInstantActionOpenFacet(): void {
	let context: RunContext
	let partyA1: PartyA
	let partyB1: PartyB
	let partyA2: PartyA
	let partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyA2 = new PartyA(context, context.signers.partyA2)
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

	describe("instantCreateAndFillOpenIntent", function () {
		beforeEach(async () => {
			await context.controlFacet.setMaxTradePerPartyA(3)
		})

		it("Should reverts if partyB actions are paused", async function () {
			await context.controlFacet.pausePartyBActions()
			const blockTime = await getCurrentLatestBlockTime()

			const signedOpenIntent = signedOpenIntentBuilder()
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateral.getAddress())
				.deadline(blockTime)
				.expirationTimestamp(blockTime + 120)
				.price(7)
				.build()

			const hash = hashSignedOpenIntent(signedOpenIntent, context.common.chainId, context.common.diamondAddress)

			const signedFillIntent = signedFillIntentBuilder()
				.quantity(signedOpenIntent.quantity)
				.deadline(signedOpenIntent.deadline)
				.intentHash(hash)
				.partyB(partyB1.address)
				.build()

			await expect(
				context.instantActionOpenFacet
					.connect(partyA1.getSigner)
					.instantCreateAndFillOpenIntent(
						signedOpenIntent,
						await partyA1.sign(hash),
						signedFillIntent,
						await partyB1.sign(hashSignedFillOpenIntent(signedFillIntent, context.common.chainId, context.common.diamondAddress)),
					),
			).to.be.revertedWithCustomError(context.instantActionOpenFacet, "PartyBActionsPaused")
		})

		it("Should reverts if third-party actions are paused", async function () {
			await context.controlFacet.pauseThirdPartyActions()
			const blockTime = await getCurrentLatestBlockTime()

			const signedOpenIntent = signedOpenIntentBuilder()
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateral.getAddress())
				.deadline(blockTime + 120)
				.expirationTimestamp(blockTime + 120)
				.price(7)
				.build()

			const hash = hashSignedOpenIntent(signedOpenIntent, context.common.chainId, context.common.diamondAddress)

			const signedFillIntent = signedFillIntentBuilder()
				.quantity(signedOpenIntent.quantity)
				.deadline(signedOpenIntent.deadline)
				.intentHash(hash)
				.partyB(partyB1.address)
				.build()

			await expect(
				context.instantActionOpenFacet
					.connect(partyA1.getSigner)
					.instantCreateAndFillOpenIntent(
						signedOpenIntent,
						await partyA1.sign(hash),
						signedFillIntent,
						await partyB1.sign(hashSignedFillOpenIntent(signedFillIntent, context.common.chainId, context.common.diamondAddress)),
					),
			).to.be.revertedWithCustomError(context.instantActionOpenFacet, "ThirdPartyActionsPaused")
		})

		it("Should reverts with invalid partyA signature", async function () {
			const blockTime = await getCurrentLatestBlockTime()

			const signedOpenIntent = signedOpenIntentBuilder()
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateral.getAddress())
				.deadline(blockTime + 120)
				.expirationTimestamp(blockTime + 120)
				.price(7)
				.partyA(partyB1.address) // Wrong partyA
				.build()

			const hash = hashSignedOpenIntent(signedOpenIntent, context.common.chainId, context.common.diamondAddress)

			const signedFillIntent = signedFillIntentBuilder()
				.quantity(signedOpenIntent.quantity)
				.deadline(signedOpenIntent.deadline)
				.intentHash(hash)
				.partyB(partyB1.address)
				.build()

			await expect(
				context.instantActionOpenFacet
					.connect(partyA1.getSigner)
					.instantCreateAndFillOpenIntent(
						signedOpenIntent,
						await partyA1.sign(hash),
						signedFillIntent,
						await partyB1.sign(hashSignedFillOpenIntent(signedFillIntent, context.common.chainId, context.common.diamondAddress)),
					),
			).to.be.revertedWithCustomError(context.instantActionOpenFacet, "InvalidSignature")
		})

		it("Should reverts with invalid partyB signature", async function () {
			const blockTime = await getCurrentLatestBlockTime()

			const signedOpenIntent = signedOpenIntentBuilder()
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateral.getAddress())
				.deadline(blockTime + 120)
				.expirationTimestamp(blockTime + 120)
				.price(7)
				.partyA(partyA1.address)
				.build()

			const hash = hashSignedOpenIntent(signedOpenIntent, context.common.chainId, context.common.diamondAddress)

			const signedFillIntent = signedFillIntentBuilder()
				.quantity(signedOpenIntent.quantity)
				.deadline(signedOpenIntent.deadline)
				.intentHash(hash)
				.partyB(partyA1.address) // Wrong partyB
				.build()

			await expect(
				context.instantActionOpenFacet
					.connect(partyA1.getSigner)
					.instantCreateAndFillOpenIntent(
						signedOpenIntent,
						await partyA1.sign(hash),
						signedFillIntent,
						await partyB1.sign(hashSignedFillOpenIntent(signedFillIntent, context.common.chainId, context.common.diamondAddress)),
					),
			).to.be.revertedWithCustomError(context.instantActionOpenFacet, "InvalidSignature")
		})

		it("executes successfully", async function () {
			const blockTime = await getCurrentLatestBlockTime()

			const signedOpenIntent = signedOpenIntentBuilder()
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateral.getAddress())
				.deadline(blockTime + 120)
				.expirationTimestamp(blockTime + 120)
				.price(7)
				.partyA(partyA1.address)
				.partyB(partyB1.address)
				.build()

			const hash = hashSignedOpenIntent(signedOpenIntent, context.common.chainId, context.common.diamondAddress)

			const signedFillIntent = signedFillIntentBuilder()
				.quantity(signedOpenIntent.quantity)
				.deadline(signedOpenIntent.deadline)
				.intentHash(hash)
				.partyB(partyB1.address)
				.build()

			await expect(
				context.instantActionOpenFacet
					.connect(partyA1.getSigner)
					.instantCreateAndFillOpenIntent(
						signedOpenIntent,
						await partyA1.sign(hash),
						signedFillIntent,
						await partyB1.sign(hashSignedFillOpenIntent(signedFillIntent, context.common.chainId, context.common.diamondAddress)),
					),
			).to.not.be.reverted

			const intent = await context.viewFacet.getOpenIntent(1)

			expect(intent.partyA).to.be.equal(partyA1.address)
			expect(intent.partyB).to.be.equal(partyB1.address)
			expect(intent.status).to.be.equal(4) // IntentStatus.Open
		})
	})

	describe("instantCancelOpenIntent", function () {
		beforeEach(async () => {
			await context.controlFacet.setMaxTradePerPartyA(3)

			const blockTime = await getCurrentLatestBlockTime()
			const sendOpenIntentReq = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.deadline(blockTime + 120)
				.expirationTimestamp(blockTime + 120)
				.build()

			await partyA1.sendOpenIntent(sendOpenIntentReq)
			await partyB1.lockOpenIntent(1)
		})

		it("should reverts if partyB actions are paused", async function () {
			await context.controlFacet.pausePartyBActions()
			const signedCancelOpenIntent = signedSimpleActionIntentBuilder().signer(partyA1.address).build()
			const signedAcceptCancelOpenIntent = signedSimpleActionIntentBuilder().signer(partyB1.address).build()

			const signedCancelOpenIntentHash = hashSignedCancelOpenIntent(signedCancelOpenIntent, context.common.chainId, context.common.diamondAddress)
			const signedAcceptCancelOpenIntentHash = hashSignedAcceptCancelOpenIntent(
				signedAcceptCancelOpenIntent,
				context.common.chainId,
				context.common.diamondAddress,
			)

			await expect(
				context.instantActionOpenFacet
					.connect(partyA1.getSigner)
					.instantCancelOpenIntent(
						signedCancelOpenIntent,
						await partyA1.sign(signedCancelOpenIntentHash),
						signedAcceptCancelOpenIntent,
						await partyB1.sign(signedAcceptCancelOpenIntentHash),
					),
			).to.be.revertedWithCustomError(context.instantActionOpenFacet, "PartyBActionsPaused")
		})

		it("should reverts if third-party actions are paused", async function () {
			await context.controlFacet.pauseThirdPartyActions()
			const signedCancelOpenIntent = signedSimpleActionIntentBuilder().signer(partyA1.address).build()
			const signedAcceptCancelOpenIntent = signedSimpleActionIntentBuilder().signer(partyB1.address).build()

			const signedCancelOpenIntentHash = hashSignedCancelOpenIntent(signedCancelOpenIntent, context.common.chainId, context.common.diamondAddress)
			const signedAcceptCancelOpenIntentHash = hashSignedAcceptCancelOpenIntent(
				signedAcceptCancelOpenIntent,
				context.common.chainId,
				context.common.diamondAddress,
			)

			await expect(
				context.instantActionOpenFacet
					.connect(partyA1.getSigner)
					.instantCancelOpenIntent(
						signedCancelOpenIntent,
						await partyA1.sign(signedCancelOpenIntentHash),
						signedAcceptCancelOpenIntent,
						await partyB1.sign(signedAcceptCancelOpenIntentHash),
					),
			).to.be.revertedWithCustomError(context.instantActionOpenFacet, "ThirdPartyActionsPaused")
		})

		it("should reverts with invalid partyA signature", async function () {
			const signedCancelOpenIntentInvalidSigner = signedSimpleActionIntentBuilder().signer(partyA2.address).build()
			const signedAcceptCancelOpenIntent = signedSimpleActionIntentBuilder().signer(partyB1.address).build()

			const signedCancelOpenIntentHash = hashSignedCancelOpenIntent(
				signedCancelOpenIntentInvalidSigner,
				context.common.chainId,
				context.common.diamondAddress,
			)
			const signedAcceptCancelOpenIntentHash = hashSignedAcceptCancelOpenIntent(
				signedAcceptCancelOpenIntent,
				context.common.chainId,
				context.common.diamondAddress,
			)

			await expect(
				context.instantActionOpenFacet
					.connect(partyA1.getSigner)
					.instantCancelOpenIntent(
						signedCancelOpenIntentInvalidSigner,
						await partyA1.sign(signedCancelOpenIntentHash),
						signedAcceptCancelOpenIntent,
						await partyB1.sign(signedAcceptCancelOpenIntentHash),
					),
			).to.be.revertedWithCustomError(context.instantActionOpenFacet, "InvalidSignature")
		})

		it("should reverts with invalid partyB signature", async function () {
			const signedCancelOpenIntent = signedSimpleActionIntentBuilder().signer(partyA1.address).build()
			const signedAcceptCancelOpenIntentInvalidSigner = signedSimpleActionIntentBuilder().signer(partyB2.address).build()

			const signedCancelOpenIntentHash = hashSignedCancelOpenIntent(signedCancelOpenIntent, context.common.chainId, context.common.diamondAddress)
			const signedAcceptCancelOpenIntentHash = hashSignedAcceptCancelOpenIntent(
				signedAcceptCancelOpenIntentInvalidSigner,
				context.common.chainId,
				context.common.diamondAddress,
			)

			await expect(
				context.instantActionOpenFacet
					.connect(partyA1.getSigner)
					.instantCancelOpenIntent(
						signedCancelOpenIntent,
						await partyA1.sign(signedCancelOpenIntentHash),
						signedAcceptCancelOpenIntentInvalidSigner,
						await partyB1.sign(signedAcceptCancelOpenIntentHash),
					),
			).to.be.revertedWithCustomError(context.instantActionOpenFacet, "InvalidSignature")
		})

		it("executes successfully", async function () {
			const signedCancelOpenIntent = signedSimpleActionIntentBuilder().signer(partyA1.address).build()
			const signedAcceptCancelOpenIntent = signedSimpleActionIntentBuilder().signer(partyB1.address).build()

			const signedCancelOpenIntentHash = hashSignedCancelOpenIntent(signedCancelOpenIntent, context.common.chainId, context.common.diamondAddress)
			const signedAcceptCancelOpenIntentHash = hashSignedAcceptCancelOpenIntent(
				signedAcceptCancelOpenIntent,
				context.common.chainId,
				context.common.diamondAddress,
			)

			expect(
				await context.instantActionOpenFacet
					.connect(partyA1.getSigner)
					.instantCancelOpenIntent(
						signedCancelOpenIntent,
						await partyA1.sign(signedCancelOpenIntentHash),
						signedAcceptCancelOpenIntent,
						await partyB1.sign(signedAcceptCancelOpenIntentHash),
					),
			).to.not.reverted

			const deletedIntent = await context.viewFacet.getOpenIntent(1)

			expect(deletedIntent.status).eq(3) // IntentStatus.CANCELED
		})
	})
}
