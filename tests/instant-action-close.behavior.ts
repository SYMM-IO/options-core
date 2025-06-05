import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"

import { initializeTestFixture } from "./initialize-test.fixture"
import { hashSignedCloseIntent, hashSignedFillCloseIntent, hashSignedFillCloseIntentById, hashSignedSimpleActionIntent } from "./utils/hash"

import { RunContext } from "./run-context"
import { PartyA } from "./models/partyA.model"
import { PartyB } from "./models/partyB.model"
import { e } from "../utils/e"
import { getLatestBlockTime } from "../utils/time"
import { signedSimpleActionIntentBuilder } from "./models/builders/signed-simple-action-intent.builder"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { SignedFillIntentByIdBuilder } from "./models/builders/signed-fill-close-intent-by-id.builder"
import { SignedFillIntentByIdStruct } from "../types/contracts/interfaces/ISymmio"
import { SignedCloseIntentBuilder } from "./models/builders/signed-close-intent.builder"
import { signedFillIntentBuilder } from "./models/builders/signed-fill-intent.builder"

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

		await context.controlFacet.setMaxTradePerPartyA(3)
	})

	describe("instantCancelCloseIntent", function () {
		beforeEach(async () => {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.expirationTimestamp(latestBlock + 120)
				.deadline(latestBlock + 150)
				.build()

			// Create and fill open intent
			await partyA1.sendOpenIntent(request)
			await partyB1.lockOpenIntent(1)
			await partyB1.fillOpenIntent(1, request.quantity, request.price)
			await partyA1.sendCloseIntent(1, request.quantity, request.price, request.expirationTimestamp)
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
				context.instantActionCloseFacet.instantCancelCloseIntent(
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
				context.instantActionCloseFacet.instantCancelCloseIntent(
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
				context.instantActionCloseFacet.instantCancelCloseIntent(
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
				context.instantActionCloseFacet.instantCancelCloseIntent(
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
				await context.instantActionCloseFacet.instantCancelCloseIntent(
					signedCancelCloseIntent,
					await partyA1.sign(signedCancelCloseIntentHash),
					signedAcceptCancelCloseIntent,
					await partyB1.sign(signedAcceptCancelOpenIntentHash),
				),
			).to.not.reverted

			const close = await context.viewFacet.getCloseIntent(1)

			expect(close.status).to.equal(2) // 2 is CANCELLED
		})
	})

	describe("instantFillCloseIntent", function () {
		beforeEach(async () => {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.expirationTimestamp(latestBlock + 120)
				.deadline(latestBlock + 150)
				.build()

			// Create and fill open intent
			await partyA1.sendOpenIntent(request)
			await partyB1.lockOpenIntent(1)
			await partyB1.fillOpenIntent(1, request.quantity, request.price)
			await partyA1.sendCloseIntent(1, request.price, request.quantity, request.expirationTimestamp)
		})

		it("Should fail when partyB actions paused", async function () {
			await context.controlFacet.pausePartyBActions()

			const signedFillCloseIntent = SignedFillIntentByIdBuilder().partyB(partyB1.address).build()
			const signedFillCloseIntentHash = hashSignedFillCloseIntentById(signedFillCloseIntent, context.common.chainId, context.common.diamondAddress)

			await expect(
				context.instantActionCloseFacet.instantFillCloseIntent(signedFillCloseIntent, await partyB1.sign(signedFillCloseIntentHash)),
			).to.be.revertedWithCustomError(context.instantActionCloseFacet, "PartyBActionsPaused")
		})

		it("Should fail when thirdParty actions paused", async function () {
			await context.controlFacet.pauseThirdPartyActions()

			const signedFillCloseIntent = SignedFillIntentByIdBuilder().partyB(partyB1.address).build()
			const signedFillCloseIntentHash = hashSignedFillCloseIntentById(signedFillCloseIntent, context.common.chainId, context.common.diamondAddress)

			await expect(
				context.instantActionCloseFacet.instantFillCloseIntent(signedFillCloseIntent, await partyB1.sign(signedFillCloseIntentHash)),
			).to.be.revertedWithCustomError(context.instantActionCloseFacet, "ThirdPartyActionsPaused")
		})

		it("Should fail when partyB signature is invalid", async function () {
			const signedFillCloseIntent = SignedFillIntentByIdBuilder().partyB(partyB2.address).build()
			const signedFillCloseIntentHash = hashSignedFillCloseIntentById(signedFillCloseIntent, context.common.chainId, context.common.diamondAddress)

			await expect(
				context.instantActionCloseFacet.instantFillCloseIntent(signedFillCloseIntent, await partyB1.sign(signedFillCloseIntentHash)),
			).to.be.revertedWithCustomError(context.instantActionCloseFacet, "InvalidSignature")
		})

		it("Should instant fill close intent successfully", async function () {
			const signedFillCloseIntent = SignedFillIntentByIdBuilder().partyB(partyB1.address).build()

			const signedFillCloseIntentHash = hashSignedFillCloseIntentById(signedFillCloseIntent, context.common.chainId, context.common.diamondAddress)

			await expect(await context.instantActionCloseFacet.instantFillCloseIntent(signedFillCloseIntent, await partyB1.sign(signedFillCloseIntentHash)))
				.to.not.reverted

			const trade = await context.viewFacet.getTrade(1)
			expect(trade.status).to.equal(1) // 1 is CLOSE

			const closeIntent = await context.viewFacet.getCloseIntent(1)
			expect(closeIntent.status).to.equal(3) // 3 is FILL
		})
	})

	describe("instantCloseAndFillCloseIntent", function () {
		beforeEach(async () => {
			const latestBlock = await getLatestBlockTime()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.expirationTimestamp(latestBlock + 120)
				.deadline(latestBlock + 150)
				.build()

			// Create and fill open intent
			await partyA1.sendOpenIntent(request)
			await partyB1.lockOpenIntent(1)
			await partyB1.fillOpenIntent(1, request.quantity, request.price)
		})

		it("Should fail when partyB actions paused", async function () {
			await context.controlFacet.pausePartyBActions()

			const signedCloseIntent = SignedCloseIntentBuilder().partyA(partyA1.address).build()
			const signedCloseIntentHash = hashSignedCloseIntent(signedCloseIntent, context.common.chainId, context.common.diamondAddress)

			const signedFillIntent = signedFillIntentBuilder().partyB(partyB1.address).intentHash(signedCloseIntentHash).build()
			const signedFillIntentHash = hashSignedFillCloseIntent(signedFillIntent, context.common.chainId, context.common.diamondAddress)

			await expect(
				context.instantActionCloseFacet.instantCloseAndFillCloseIntent(
					signedCloseIntent,
					await partyA1.sign(signedCloseIntentHash),
					signedFillIntent,
					await partyB1.sign(signedFillIntentHash),
				),
			).to.be.revertedWithCustomError(context.instantActionCloseFacet, "PartyBActionsPaused")
		})

		it("Should fail when thirdParty actions paused", async function () {
			await context.controlFacet.pauseThirdPartyActions()

			const signedCloseIntent = SignedCloseIntentBuilder().partyA(partyA1.address).build()
			const signedCloseIntentHash = hashSignedCloseIntent(signedCloseIntent, context.common.chainId, context.common.diamondAddress)

			const signedFillIntent = signedFillIntentBuilder().partyB(partyB1.address).intentHash(signedCloseIntentHash).build()
			const signedFillIntentHash = hashSignedFillCloseIntent(signedFillIntent, context.common.chainId, context.common.diamondAddress)

			await expect(
				context.instantActionCloseFacet.instantCloseAndFillCloseIntent(
					signedCloseIntent,
					await partyA1.sign(signedCloseIntentHash),
					signedFillIntent,
					await partyB1.sign(signedFillIntentHash),
				),
			).to.be.revertedWithCustomError(context.instantActionCloseFacet, "ThirdPartyActionsPaused")
		})

		it("Should fail when partyA signature is invalid", async function () {
			const signedCloseIntent = SignedCloseIntentBuilder().partyA(partyA2.address).build() // invalid partyA
			const signedCloseIntentHash = hashSignedCloseIntent(signedCloseIntent, context.common.chainId, context.common.diamondAddress)

			const signedFillIntent = signedFillIntentBuilder().partyB(partyB1.address).intentHash(signedCloseIntentHash).build()
			const signedFillIntentHash = hashSignedFillCloseIntent(signedFillIntent, context.common.chainId, context.common.diamondAddress)

			await expect(
				context.instantActionCloseFacet.instantCloseAndFillCloseIntent(
					signedCloseIntent,
					await partyA1.sign(signedCloseIntentHash),
					signedFillIntent,
					await partyB1.sign(signedFillIntentHash),
				),
			).to.be.revertedWithCustomError(context.instantActionCloseFacet, "InvalidSignature")
		})

		it("Should fail when partyB signature is invalid", async function () {
			const signedCloseIntent = SignedCloseIntentBuilder().partyA(partyA1.address).build()
			const signedCloseIntentHash = hashSignedCloseIntent(signedCloseIntent, context.common.chainId, context.common.diamondAddress)

			const signedFillIntent = signedFillIntentBuilder().partyB(partyB2.address).intentHash(signedCloseIntentHash).build() // invalid partyB
			const signedFillIntentHash = hashSignedFillCloseIntent(signedFillIntent, context.common.chainId, context.common.diamondAddress)

			await expect(
				context.instantActionCloseFacet.instantCloseAndFillCloseIntent(
					signedCloseIntent,
					await partyA1.sign(signedCloseIntentHash),
					signedFillIntent,
					await partyB1.sign(signedFillIntentHash),
				),
			).to.be.revertedWithCustomError(context.instantActionCloseFacet, "InvalidSignature")
		})

		it("Should instant close and fill close intent successfully", async function () {
			const signedCloseIntent = SignedCloseIntentBuilder()
				.partyA(partyA1.address)
				.deadline((await getLatestBlockTime()) + 120)
				.build()

			const signedCloseIntentHash = hashSignedCloseIntent(signedCloseIntent, context.common.chainId, context.common.diamondAddress)

			const signedFillIntent = signedFillIntentBuilder().partyB(partyB1.address).intentHash(signedCloseIntentHash).build()
			const signedFillIntentHash = hashSignedFillCloseIntent(signedFillIntent, context.common.chainId, context.common.diamondAddress)

			await expect(
				await context.instantActionCloseFacet.instantCloseAndFillCloseIntent(
					signedCloseIntent,
					await partyA1.sign(signedCloseIntentHash),
					signedFillIntent,
					await partyB1.sign(signedFillIntentHash),
				),
			).to.not.reverted

			const trade = await context.viewFacet.getTrade(1)
			expect(trade.status).to.equal(1) // 1 is CLOSE

			const closeIntent = await context.viewFacet.getCloseIntent(1)
			expect(closeIntent.status).to.equal(3) // 3 is FILL
		})
	})
}
