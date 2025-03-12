import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { User } from "./models/user.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { ZeroAddress } from "ethers"

export function shouldBehaveLikePartyAFacet(): void {
	let context: RunContext, user: User, partyB: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		user = new User(context, context.signers.user)
		partyB = new PartyB(context, context.signers.user2)
		await user.setBalances("500")

		await context.controlFacet.setPartyBConfig(partyB.getSigner(), {
			isActive: true,
			lossCoverage: 0,
			oracleId: 0,
		})

		await context.controlFacet.setAffiliateStatus(context.signers.others[0], true)

		await context.controlFacet.addOracle("test oracel", context.signers.others[0])
		await context.controlFacet.setPriceOracleAddress(context.oracle)
		await context.controlFacet.addSymbol("BTC", 0, 1, context.collateral, true, 0)
		await context.controlFacet.setMaxConnectedPartyBs(1)
		await partyB.setBalances(e(100000))
		await user.setBalances(e(100000))
	})

	describe("sendOpenIntent", async function () {
		beforeEach(async () => {
			await context.controlFacet.addOracle("test orancel", context.oracle)
			await context.controlFacet.addSymbol("BTC", 0, 1, context.collateral, true, 0)
			await context.controlFacet.setMaxConnectedPartyBs(1)
			await partyB.setBalances(e(100000))
			await user.setBalances(e(100000))
		})
		it("Should fail when partyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.build()
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("Pausable: PartyA actions paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.build()
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when symbolId be wrong", async function () {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.symbolId(3)
				.build()
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Symbol is not valid")
		})

		it("Should fail when deadline be low", async function () {
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.symbolId(1)
				.build()
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Low deadline")
		})

		it("Should fail when expiration timestamp be low", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.build()
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Low expiration timestamp")
		})

		it("Should fail when cap for exercise fee be high", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(2), rate: "0" })
				.build()
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: High cap for exercise fee")
		})

		it("Should fail when instance mode is active", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.build()

			await context.controlFacet.setInstantActionsMode(user.getSigner(), true)
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Instant action mode is activated")
		})

		it("Should fail when affiliate be zero address or invalid", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })

			await expect(user.sendOpenIntent(request.build())).to.be.revertedWith("PartyAFacet: Invalid affiliate")

			request.affiliate(context.signers.others[1])
			await expect(user.sendOpenIntent(request.build())).to.be.revertedWith("PartyAFacet: Invalid affiliate")

			await context.controlFacet.setAffiliateStatus(context.signers.others[1], true)
			await expect(user.sendOpenIntent(request.build())).to.be.not.revertedWith("PartyAFacet: Invalid affiliate")
		})

		it("Should fail when partyA bound to a partyB that is not in whitelisted partyB", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([context.signers.partyB2])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.affiliate(context.signers.others[0])
				.build()

			await context.accountFacet.connect(user.getSigner()).bindToPartyB(partyB.getSigner())
			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: User is bound to another PartyB")
		})

		it("Should fail when sender in whitelisted partyB", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([user.getSigner()])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.affiliate(context.signers.others[0])
				.build()

			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: Sender isn't allowed in partyBWhiteList")
		})

		it("Should fail when partyB whiteListed and available balance be insufficient", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([context.signers.partyB2])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.affiliate(context.signers.others[0])
				.quantity(e(100))
				.price(7)
				.build()

			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: insufficient available balance")
		})

		it("Should fail when partyB not whiteListed and available balance be insufficient", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([context.signers.partyB2, context.signers.partyB1])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.affiliate(context.signers.others[0])
				.quantity(e(100))
				.price(7)
				.build()

			await expect(user.sendOpenIntent(request)).to.be.revertedWith("PartyAFacet: insufficient available balance")
		})

		it("Should fail when partyB whiteListed and available balance be insufficient", async function () {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.affiliate(context.signers.others[0])
				.quantity(e(100))
				.price(7)
				.build()

			await context.accountFacet.connect(partyB.getSigner()).deposit(context.collateral, e(100000))
			await context.accountFacet.connect(user.getSigner()).deposit(context.collateral, e(100000))

			expect(await user.sendOpenIntent(request)).to.be.not.reverted

			const intent = await context.viewFacet.getOpenIntent(1)

			expect(intent.tradeId).to.be.equal(0)
			expect(intent.partyBsWhiteList).to.be.deep.equal([await partyB.getSigner().getAddress()])
			expect(intent.symbolId).to.be.equal(1)
			expect(intent.price).to.be.equal(7)
			expect(intent.quantity).to.be.equal(e(100))
			expect(intent.strikePrice).to.be.equal(0)
			expect(intent.expirationTimestamp).to.be.equal((latestBlock?.timestamp ?? 0) + 120)
			expect(intent.exerciseFee.cap).to.be.equal(e(1))
			expect(intent.exerciseFee.rate).to.be.equal(0)
			expect(intent.partyA).to.be.equal(await user.getSigner().getAddress())
			expect(intent.partyB).to.be.equal(ZeroAddress)
			expect(intent.status).to.be.equal(0) // IntentStatus.PENDING
			expect(intent.parentId).to.be.equal(0)
			// expect(intent.createTimestamp).to.be.equal(latestBlock?.timestamp ?? 0)
			// expect(intent.status).to.be.equal(latestBlock?.timestamp ?? 0)
			expect(intent.deadline).to.be.equal((latestBlock?.timestamp ?? 0) + 120)
			// expect(intent.tradingFee).to.be.equal(0)
			expect(intent.affiliate).to.be.equal(await context.signers.others[0].getAddress())

			expect(await context.viewFacet.lockedBalancesOf(user.getSigner(), context.collateral.getAddress())).to.be.equal(700)
		})
	})

	describe("cancelOpenIntent", async function () {
		beforeEach(async () => {
			const latestBlock = await ethers.provider.getBlock("latest")
			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB.getSigner()])
				.affiliate(partyB.getSigner())
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 120)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.affiliate(context.signers.others[0])
				.quantity(e(100))
				.price(7)
				.build()

			await context.accountFacet.connect(partyB.getSigner()).deposit(context.collateral, e(1000))
			await context.accountFacet.connect(user.getSigner()).deposit(context.collateral, e(1000))

			await user.sendOpenIntent(request)
		})

		it("Should fail when partyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await expect(user.sendCancelOpenIntent(["1"])).to.be.revertedWith("Pausable: PartyA actions paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(user.sendCancelOpenIntent(["1"])).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when intent status not be pending or locked", async function () {
			// TODO ::: 
		})

		it("Should fail when msgSender not be PartyA", async function () {
			await expect(context.partyAFacet.connect(context.signers.user2).cancelOpenIntent(["1"])).to.be.revertedWith("PartyAFacet: Should be partyA of Intent")
		})

		it("Should fail when instance mode is active", async function () {
			await context.controlFacet.setInstantActionsMode(user.getSigner(), true)
			await expect(user.sendCancelOpenIntent(['1'])).to.be.revertedWith("PartyAFacet: Instant action mode is activated")
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
