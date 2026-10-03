import { ethers, networkHelpers } from "./connection.js"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture.js"
import { PartyA } from "./models/partyA.model.js"
import { RunContext } from "./run-context.js"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder.js"
import { PartyB } from "./models/partyB.model.js"
import { e } from "../utils/e.js"

export function shouldBehaveLikeForceActionFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await networkHelpers.loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyB1 = new PartyB(context, context.signers.partyB1)
		await partyA1.setBalances(context.collateral, "500")

		await context.controlFacet.setPartyBConfig(partyB1.getSigner, {
			isActive: true,
			lossCoverage: 0,
			oracleId: 1,
		})

		await context.controlFacet.setAffiliateStatus(context.signers.others[0], true)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyB1.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateral, e(100000), e(100000))

		await context.controlFacet.setForceCancelOpenIntentTimeout(100)
	})

	describe("forceCancelOpenIntent", async function () {
		beforeEach(async () => {
			const latestBlock = await ethers.provider.getBlock("latest")

			await partyA1.sendOpenIntent(
				openIntentRequestBuilder()
					.partyBsWhiteList([partyB1.getSigner])
					.affiliate(context.signers.affiliate1)
					.feeToken(context.collateral)
					.symbolId(1)
					.deadline((latestBlock?.timestamp ?? 0) + 120)
					.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
					.exerciseFee({ cap: e(1), rate: "0" })
					.quantity(e(100))
					.price(7)
					.build(),
			)
		})

		it("Should fail when partyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await expect(partyA1.forceCancelOpenIntent("1")).to.be.revertedWithCustomError(context.forceActionsFacet, "PartyAActionsPaused")
		})

		it("Should fail when intent status is not CANCEL_PENDING", async function () {
			await expect(partyA1.forceCancelOpenIntent("1")).to.be.revertedWithCustomError(context.forceActionsFacet, "InvalidState")
		})

		describe("", async function () {
			beforeEach(async function () {
				await partyB1.lockOpenIntent(1)
				await partyA1.sendCancelOpenIntent(["1"])
			})

			it("Should fail when intetn status is not CANCEL_PENDING", async function () {
				await expect(partyA1.forceCancelOpenIntent("1")).to.be.revertedWithCustomError(context.forceActionsFacet, "CooldownNotOver")
			})

			it("Should force cancel open intent successfuly", async function () {
				await networkHelpers.time.increase(await context.viewFacet.getForceCancelOpenIntentTimeout())
				await expect(partyA1.forceCancelOpenIntent("1")).not.to.revert(ethers)

				const { statusModifyTimestamp, status } = await context.viewFacet.getOpenIntent(1)

				const latestBlock = await ethers.provider.getBlock("latest")

				expect(status).to.be.equal(3)
				expect(statusModifyTimestamp).to.be.equal(latestBlock?.timestamp)
			})
		})
	})
}
