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

export function shouldBehaveLikePartyAFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyB1.setBalances(e(100000), e(100000))
		await partyA1.setBalances(e(100000), e(100000))
	})

	describe("sendOpenIntent", async function () {
		it("Should fail when partyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner()])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWith("Pausable: PartyA actions paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner()])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when symbolId be wrong", async function () {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner()])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(3)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Symbol is not valid")
		})

		it("Should fail when deadline be low", async function () {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner()])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Low deadline")
		})

		it("Should fail when expiration timestamp be low", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner()])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Low expiration timestamp")
		})

		it("Should fail when cap for exercise fee be high", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner()])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(2), rate: "0" })
				.build()
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: High cap for exercise fee")
		})

		it("Should fail when instance mode is active", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner()])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await context.controlFacet.setInstantActionsMode(partyA1.getSigner(), true)
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Instant action mode is activated")
		})

		it("Should fail when affiliate be zero address or invalid", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner()])
				.affiliate(context.signers.others[0])
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })

			await expect(partyA1.sendOpenIntent(request.build())).to.be.revertedWith("PartyAFacet: Invalid affiliate")

			request.affiliate(context.signers.others[1])
			await expect(partyA1.sendOpenIntent(request.build())).to.be.revertedWith("PartyAFacet: Invalid affiliate")

			await context.controlFacet.setAffiliateStatus(context.signers.others[1], true)
			await expect(partyA1.sendOpenIntent(request.build())).to.be.not.revertedWith("PartyAFacet: Invalid affiliate")
		})

		it("Should fail when partyA bound to a partyB that is not in whitelisted partyB", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner()])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(partyB1.getSigner())
			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: User is bound to another PartyB")
		})

		it("Should fail when sender in whitelisted partyB", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyA1.getSigner()])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Sender isn't allowed in partyBWhiteList")
		})

		it("Should fail when partyB whiteListed and available balance be insufficient", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner()])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100000000))
				.price(e(200))
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: insufficient available balance")
		})

		it("Should fail when partyB not whiteListed and available balance be insufficient", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB2.getSigner(), context.signers.partyB1])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100000000))
				.price(e(200))
				.build()

			await expect(partyA1.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: insufficient available balance")
		})

		it("Should fail when partyB whiteListed and available balance be insufficient", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner()])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build()

			expect(await partyA1.sendOpenIntent(request)).to.be.not.reverted

			const intent = await context.viewFacet.getOpenIntent(1)

			expect(intent.tradeId).to.be.equal(0)
			expect(intent.partyBsWhiteList).to.be.deep.equal([await partyB1.getSigner().getAddress()])
			expect(intent.symbolId).to.be.equal(1)
			expect(intent.price).to.be.equal(7)
			expect(intent.quantity).to.be.equal(e(100))
			expect(intent.strikePrice).to.be.equal(0)
			expect(intent.expirationTimestamp).to.be.equal((latestBlock?.timestamp ?? 0) + 120)
			expect(intent.exerciseFee.cap).to.be.equal(e(1))
			expect(intent.exerciseFee.rate).to.be.equal(0)
			expect(intent.partyA).to.be.equal(await partyA1.getSigner().getAddress())
			expect(intent.partyB).to.be.equal(ZeroAddress)
			expect(intent.status).to.be.equal(0) // IntentStatus.PENDING
			expect(intent.parentId).to.be.equal(0)
			// expect(intent.createTimestamp).to.be.equal(latestBlock?.timestamp ?? 0)
			// expect(intent.status).to.be.equal(latestBlock?.timestamp ?? 0)
			expect(intent.deadline).to.be.equal((latestBlock?.timestamp ?? 0) + 120)
			// expect(intent.tradingFee).to.be.equal(0)
			expect(intent.affiliate).to.be.equal(await context.signers.affiliate1.getAddress())

			expect(await context.viewFacet.lockedBalancesOf(partyA1.getSigner(), context.collateral.getAddress())).to.be.equal(700)
		})
	})

	describe("cancelOpenIntent", async function () {
		beforeEach(async () => {
			const latestBlock = await ethers.provider.getBlock("latest")

			await partyA1.sendOpenIntent(
				openIntentRequestBuilder()
					.partyBsWhiteList([partyB1.getSigner()])
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
			await expect(partyA1.sendCancelOpenIntent(["1"])).to.be.revertedWith("Pausable: PartyA actions paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(partyA1.sendCancelOpenIntent(["1"])).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when intent status not be pending or locked", async function () {
			// TODO :::
		})

		it("Should fail when msgSender not be PartyA", async function () {
			await expect(partyA2.sendCancelOpenIntent(["1"])).to.be.revertedWith("PartyAFacet: Should be partyA of Intent")
		})

		it("Should fail when instance mode is active", async function () {
			await partyA1.activateInstantActionMode()
			await expect(partyA1.sendCancelOpenIntent(["1"])).to.be.revertedWith("PartyAFacet: Instant action mode is activated")
		})

		// it("Should set status to EXPIRED when deadline reached", async function () {
		// 	const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 150
		// 	await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
		// 	expect(await user.sendCancelOpenIntent(['1'])).to.be.not.reverted

		// 	const intent = await context.viewFacet.getOpenIntent(1)

		// 	expect(intent.status).to.be.equal(2)
		// })
	})
}
