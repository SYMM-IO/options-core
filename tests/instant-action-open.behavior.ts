import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { ethers } from "hardhat"

import { initializeTestFixture } from "./initialize-test.fixture"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { signedOpenIntentBuilder } from "./models/builders/signed-open-intent.builder"
import { signedFillIntentBuilder } from "./models/builders/signed-fill-intent.builder"
import { hashSignedOpenIntent, hashSignedFillOpenIntent } from "./utils/hash"

import { RunContext } from "./run-context"
import { PartyA } from "./models/partyA.model"
import { PartyB } from "./models/partyB.model"
import { e } from "../utils/e"

export function shouldBehaveLikeInstantActionOpenFacet(): void {
	let context: RunContext
	let partyA1: PartyA
	let partyB1: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyB1 = new PartyB(context, context.signers.partyB1)

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

		it("Should fail when partyB actions paused", async function () {
			await context.controlFacet.pausePartyBActions()
			const timestamp = (await ethers.provider.getBlock("latest"))?.timestamp ?? 0

			console.log("AAAAAAAAAAAAAAAAAaaa")
			const signedOpenIntent = signedOpenIntentBuilder()
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateral.getAddress())
				.symbolId(1)
				.deadline(timestamp + 120)
				.expirationTimestamp(timestamp + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build()

			const hash = hashSignedOpenIntent(signedOpenIntent, context.common.chainId, context.common.diamondAddress)
			console.log("BBBBBBBBBBBBBB")

			const signedFillIntent = signedFillIntentBuilder()
				.quantity(signedOpenIntent.quantity)
				.deadline(signedOpenIntent.deadline)
				.intentHash(hash)
				.partyB(partyB1.address)
				.build()

			console.log("CCCCCCCCCCCCCCCCCCCCCCCC")


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

		it("Should fail when thirdParty actions paused", async function () {
			await context.controlFacet.pauseThirdPartyActions()
			const timestamp = (await ethers.provider.getBlock("latest"))?.timestamp ?? 0

			const signedOpenIntent = signedOpenIntentBuilder()
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateral.getAddress())
				.symbolId(1)
				.deadline(timestamp + 120)
				.expirationTimestamp(timestamp + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
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

		it("Should fail when partyA signature is invalid", async function () {
			const timestamp = (await ethers.provider.getBlock("latest"))?.timestamp ?? 0

			const signedOpenIntent = signedOpenIntentBuilder()
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateral.getAddress())
				.symbolId(1)
				.deadline(timestamp + 120)
				.expirationTimestamp(timestamp + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
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

		it("Should fail when partyB signature is invalid", async function () {
			const timestamp = (await ethers.provider.getBlock("latest"))?.timestamp ?? 0

			const signedOpenIntent = signedOpenIntentBuilder()
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateral.getAddress())
				.symbolId(1)
				.deadline(timestamp + 120)
				.expirationTimestamp(timestamp + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
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

		it("Should instant create and fill open intent successfully", async function () {
			const timestamp = (await ethers.provider.getBlock("latest"))?.timestamp ?? 0

			const signedOpenIntent = signedOpenIntentBuilder()
				.affiliate(await context.signers.affiliate1.getAddress())
				.feeToken(await context.collateral.getAddress())
				.symbolId(1)
				.deadline(timestamp + 120)
				.expirationTimestamp(timestamp + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
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
		})
	})
}
