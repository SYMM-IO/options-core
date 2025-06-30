import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { toUtf8Bytes, ZeroAddress } from "ethers"
import { bigint } from "hardhat/internal/core/params/argumentTypes"
import { moveTime } from "../utils/time"

export function shouldBehaveLikeBridgeFacet(): void {
	let context: RunContext, partyA1: PartyA, partyB1: PartyB
	const ONE_DAY_IN_SEC = 86400
	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyB1 = new PartyB(context, context.signers.partyB1)

		await context.controlFacet.setPartyBConfig(partyB1.getSigner, {
			isActive: true,
			lossCoverage: 0,
			oracleId: 1,
			symbolType: 0,
		})

		await partyA1.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateralNL, e(100000), e(100000))

		await context.controlFacet.setBridgeValidationState(context.signers.bridge1, true)

		await context.controlFacet.setPartyADeallocateCooldown(ONE_DAY_IN_SEC)
	})

	describe("transferToBridge", async function () {
		it("Should fail when partyA Suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.address, true)
			await expect(
				context.bridgeFacet
					.connect(partyA1.getSigner)
					.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "UserSuspended")
		})

		it("Should fail when system global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(
				context.bridgeFacet
					.connect(partyA1.getSigner)
					.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "GlobalPaused")
		})

		it("Should fail when msgSender be partyB", async function () {
			await expect(
				context.bridgeFacet
					.connect(partyB1.getSigner)
					.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "PartyBUser")
		})

		it("Should fail when collateral not whitelisted", async function () {
			// await context.controlFacet.removeCollateralFromWhitelist(await context.collateralNL.getAddress())
			// await expect(
			// 	context.bridgeFacet
			// 		.connect(partyA1.getSigner)
			// 		.transferToBridge(context.collateralNL, e(1000), context.signers.bridge1.address, partyA1.address),
			// ).to.be.revertedWithCustomError(context.bridgeFacet, "CollateralNotWhitelisted")
			//TODO whitelisted collateral for bridge
		})

		it("Should fail when bridge not whitelisted", async function () {
			await expect(
				context.bridgeFacet
					.connect(partyA1.getSigner)
					.transferToBridge(context.collateral, e(1000), context.signers.bridge2.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "BridgeNotWhitelisted")
		})

		it("Should fail when bridge and msgSender be same", async function () {
			await expect(
				context.bridgeFacet
					.connect(context.signers.bridge1)
					.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "SelfBridgeNotAllowed")
		})

		it("Should fail when receiver address be Zero", async function () {
			await expect(
				context.bridgeFacet.connect(partyA1.getSigner).transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, ZeroAddress),
			).to.be.revertedWithCustomError(context.bridgeFacet, "ZeroAddress")
		})

		it("Should fail when Balance is Insufficient", async function () {
			await expect(
				context.bridgeFacet
					.connect(partyA1.getSigner)
					.transferToBridge(context.collateral, e(100000000), context.signers.bridge1.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "InsufficientBalance(address,address,uint256,uint256)")
		})

		it("Should fail when msgSender instant action mode active", async function () {
			await partyA1.bindToCounterParty(partyB1.address)
			await partyA1.activateInstantActionMode()
			await expect(
				context.bridgeFacet
					.connect(partyA1.getSigner)
					.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "InstantModeActive")
		})

		it("Should transfer to bridge successfully", async function () {
			await expect(
				context.bridgeFacet
					.connect(partyA1.getSigner)
					.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address),
			).to.not.reverted

			const bridgeTxId = await context.viewFacet.getLastBridgeTransactionId()
			const bridgeTx = await context.viewFacet.getBridgeTransaction(bridgeTxId)

			expect(bridgeTx.amount).to.be.equal(e(1000))
			expect(bridgeTx.id).to.be.equal(bridgeTxId)
			expect(bridgeTx.collateral).to.be.equal(await context.collateral.getAddress())
			expect(bridgeTx.sender).to.be.equal(partyA1.address)
			expect(bridgeTx.receiver).to.be.equal(partyA1.address)
			expect(bridgeTx.bridge).to.be.equal(context.signers.bridge1)
			// TODO ::: check timestamp -> expect(bridgeTx.timestamp).to.be.equal(???)
			expect(bridgeTx.status).to.be.equal(0)

			const currentIsolatedBalance = await context.viewFacet.getIsolatedBalance(partyA1.address, context.collateral)
			expect(currentIsolatedBalance).to.be.equal(e(99000))
		})
	})

	describe("withdrawReceivedBridgeValues", async function () {
		let LastBridgeTransactionId = BigInt(0)
		beforeEach(async () => {
			await context.bridgeFacet
				.connect(partyA1.getSigner)
				.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address)

			LastBridgeTransactionId = await context.viewFacet.getLastBridgeTransactionId()
		})
		it("Should fail when partyA Suspended", async function () {
			await context.controlFacet.suspendAddress(context.signers.bridge1.address, true)
			await expect(
				context.bridgeFacet.connect(context.signers.bridge1).withdrawReceivedBridgeValues([LastBridgeTransactionId]),
			).to.be.revertedWithCustomError(context.bridgeFacet, "UserSuspended")
		})

		it("Should fail when Bridge Withdraw Paused", async function () {
			await context.controlFacet.pauseBridgeWithdraw()
			await expect(
				context.bridgeFacet.connect(context.signers.bridge1).withdrawReceivedBridgeValues([LastBridgeTransactionId]),
			).to.be.revertedWithCustomError(context.bridgeFacet, "BridgeWithdrawPaused")
		})

		it("Should not fail when Bridge Withdraw unPaused", async function () {
			// 	await context.controlFacet.pauseBridgeWithdraw()
			// 	await context.controlFacet.unpauseBridgeWithdraw()
			// 	await expect(
			// 		context.bridgeFacet.connect(context.signers.bridge1).withdrawReceivedBridgeValues([LastBridgeTransactionId]),
			// 	).to.be.revertedWithCustomError(context.bridgeFacet, "BridgeWithdrawPaused")
			//TODO develop for unpausing
		})

		it("Should fail when system global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(
				context.bridgeFacet.connect(context.signers.bridge1).withdrawReceivedBridgeValues([LastBridgeTransactionId]),
			).to.be.revertedWithCustomError(context.bridgeFacet, "GlobalPaused")
		})

		it("Should fail when transactionIds list be empty", async function () {
			await expect(context.bridgeFacet.connect(context.signers.bridge1).withdrawReceivedBridgeValues([])).to.be.revertedWithCustomError(
				context.bridgeFacet,
				"EmptyList",
			)
		})

		it("Should fail if transactionId invalid", async function () {
			await expect(
				context.bridgeFacet.connect(context.signers.bridge1).withdrawReceivedBridgeValues([LastBridgeTransactionId + BigInt(10)]),
			).to.be.revertedWithCustomError(context.bridgeFacet, "TransactionIdNotFound")
		})

		it("Should transaction status be RECEIVED", async function () {
			await context.controlFacet.grantRole(context.signers.admin, ethers.keccak256(toUtf8Bytes("SUSPENDER_ROLE")))

			await context.bridgeFacet.suspendBridgeTransaction(LastBridgeTransactionId)
			await expect(
				context.bridgeFacet.connect(context.signers.bridge1).withdrawReceivedBridgeValues([LastBridgeTransactionId]),
			).to.be.revertedWithCustomError(context.bridgeFacet, "InvalidState")
		})

		it("Should fail when withdraw cooldown not pass", async function () {
			await expect(
				context.bridgeFacet.connect(context.signers.bridge1).withdrawReceivedBridgeValues([LastBridgeTransactionId]),
			).to.be.revertedWithCustomError(context.bridgeFacet, "CooldownNotOver")
		})

		it("Should fail when msgSender is not Bridge", async function () {
			await moveTime(ONE_DAY_IN_SEC)
			await expect(
				context.bridgeFacet.connect(context.signers.bridge2).withdrawReceivedBridgeValues([LastBridgeTransactionId]),
			).to.be.revertedWithCustomError(context.bridgeFacet, "UnauthorizedSender")
		})

		it("Should fail when multi transactionId collateral not same", async function () {
			await context.bridgeFacet
				.connect(partyA1.getSigner)
				.transferToBridge(context.collateralNL, e(1000), context.signers.bridge1.address, partyA1.address)

			await expect(
				context.bridgeFacet
					.connect(context.signers.bridge1)
					.withdrawReceivedBridgeValues([LastBridgeTransactionId, LastBridgeTransactionId + BigInt(1)]),
			).to.be.revertedWithCustomError(context.bridgeFacet, "MismatchedCollateral")
		})

		it("Should transfer to bridge successfully single transactionId", async function () {
			const beforeBalance = await context.collateral.balanceOf(context.signers.bridge1)
			await moveTime(ONE_DAY_IN_SEC)
			await expect(context.bridgeFacet.connect(context.signers.bridge1).withdrawReceivedBridgeValues([LastBridgeTransactionId])).to.not.reverted
			const afterBalance = await context.collateral.balanceOf(context.signers.bridge1)

			const bridgeTx = await context.viewFacet.getBridgeTransaction(LastBridgeTransactionId)

			expect(bridgeTx.amount).to.be.equal(e(1000))
			expect(bridgeTx.id).to.be.equal(LastBridgeTransactionId)
			expect(bridgeTx.collateral).to.be.equal(await context.collateral.getAddress())
			expect(bridgeTx.sender).to.be.equal(partyA1.address)
			expect(bridgeTx.receiver).to.be.equal(partyA1.address)
			expect(bridgeTx.bridge).to.be.equal(context.signers.bridge1)
			expect(bridgeTx.status).to.be.equal(2) // BridgeTransactionStatus.WITHDRAWN

			expect(afterBalance).equal(beforeBalance + bridgeTx.amount)
		})

		it("Should transfer to bridge successfully with bulk transactionIds", async function () {
			// Create a second bridge transaction
			await context.bridgeFacet
				.connect(partyA1.getSigner)
				.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address)

			const txIds = [LastBridgeTransactionId, LastBridgeTransactionId + BigInt(1)]

			const beforeBalance = await context.collateral.balanceOf(context.signers.bridge1)
			await moveTime(ONE_DAY_IN_SEC)

			await expect(context.bridgeFacet.connect(context.signers.bridge1).withdrawReceivedBridgeValues(txIds)).to.not.reverted

			const afterBalance = await context.collateral.balanceOf(context.signers.bridge1)

			for (const txId of txIds) {
				const bridgeTx = await context.viewFacet.getBridgeTransaction(txId)
				expect(bridgeTx.amount).to.be.equal(e(1000))
				expect(bridgeTx.id).to.be.equal(txId)
				expect(bridgeTx.collateral).to.be.equal(await context.collateral.getAddress())
				expect(bridgeTx.sender).to.be.equal(partyA1.address)
				expect(bridgeTx.receiver).to.be.equal(partyA1.address)
				expect(bridgeTx.bridge).to.be.equal(context.signers.bridge1)
				expect(bridgeTx.status).to.be.equal(2) // BridgeTransactionStatus.WITHDRAWN
			}

			expect(afterBalance).to.equal(beforeBalance + e(2000))
		})
	})

	describe("suspendBridgeTransaction", async function () {
		let LastBridgeTransactionId = BigInt(0)
		beforeEach(async () => {
			await context.bridgeFacet
				.connect(partyA1.getSigner)
				.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address)

			LastBridgeTransactionId = await context.viewFacet.getLastBridgeTransactionId()

			await context.controlFacet.grantRole(context.signers.admin, ethers.keccak256(toUtf8Bytes("SUSPENDER_ROLE")))
		})
		it("Should only SUSPENDER_ROLE can call it", async function () {
			await context.controlFacet.revokeRole(context.signers.admin, ethers.keccak256(toUtf8Bytes("SUSPENDER_ROLE")))

			await expect(context.bridgeFacet.suspendBridgeTransaction(LastBridgeTransactionId)).to.be.revertedWithCustomError(
				context.bridgeFacet,
				"MissingRole",
			)
		})

		it("Should fail if transactionId invalid", async function () {
			await expect(context.bridgeFacet.suspendBridgeTransaction(LastBridgeTransactionId + BigInt(10))).to.be.revertedWithCustomError(
				context.bridgeFacet,
				"TransactionIdNotFound",
			)
		})

		it("Should transaction status be RECEIVED", async function () {
			await context.controlFacet.grantRole(context.signers.admin, ethers.keccak256(toUtf8Bytes("SUSPENDER_ROLE")))

			await context.bridgeFacet.suspendBridgeTransaction(LastBridgeTransactionId)
			await expect(context.bridgeFacet.suspendBridgeTransaction(LastBridgeTransactionId)).to.be.revertedWithCustomError(
				context.bridgeFacet,
				"InvalidState",
			)
		})

		it("Should suspend bridge transaction successfully", async function () {
			await expect(context.bridgeFacet.suspendBridgeTransaction(LastBridgeTransactionId)).to.not.reverted

			const bridgeTx = await context.viewFacet.getBridgeTransaction(LastBridgeTransactionId)

			expect(bridgeTx.amount).to.be.equal(e(1000))
			expect(bridgeTx.id).to.be.equal(LastBridgeTransactionId)
			expect(bridgeTx.collateral).to.be.equal(await context.collateral.getAddress())
			expect(bridgeTx.sender).to.be.equal(partyA1.address)
			expect(bridgeTx.receiver).to.be.equal(partyA1.address)
			expect(bridgeTx.bridge).to.be.equal(context.signers.bridge1)
			expect(bridgeTx.status).to.be.equal(1) // BridgeTransactionStatus.SUSPENDED
		})
	})

	describe("restoreBridgeTransaction", async () => {
		let LastBridgeTransactionId = BigInt(0)
		beforeEach(async () => {
			await context.bridgeFacet
				.connect(partyA1.getSigner)
				.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address)

			LastBridgeTransactionId = await context.viewFacet.getLastBridgeTransactionId()

			await context.controlFacet.grantRole(context.signers.admin, ethers.keccak256(toUtf8Bytes("SUSPENDER_ROLE")))
			await context.controlFacet.grantRole(context.signers.admin, ethers.keccak256(toUtf8Bytes("DISPUTE_ROLE")))

			await context.bridgeFacet.suspendBridgeTransaction(LastBridgeTransactionId)
		})

		it("Should fail if transaction is not suspended", async function () {
			await context.controlFacet.setInvalidBridgedAmountsPool(context.signers.others[0])

			// restoreBridgeTransaction requires status SUSPENDED
			await context.bridgeFacet.restoreBridgeTransaction(LastBridgeTransactionId, e(900))
			// Try restoring again (now status is RECEIVED)
			await expect(context.bridgeFacet.restoreBridgeTransaction(LastBridgeTransactionId, e(800))).to.be.revertedWithCustomError(
				context.bridgeFacet,
				"InvalidState",
			)
		})

		it("Should fail if invalidBridgedAmountsPool is zero address", async function () {
			await expect(context.bridgeFacet.restoreBridgeTransaction(LastBridgeTransactionId, e(900))).to.be.revertedWithCustomError(
				context.bridgeFacet,
				"ZeroAddress",
			)
		})

		it("Should fail if validAmount > transaction.amount", async function () {
			await context.controlFacet.setInvalidBridgedAmountsPool(context.signers.others[0])
			await expect(context.bridgeFacet.restoreBridgeTransaction(LastBridgeTransactionId, e(2000))).to.be.revertedWithCustomError(
				context.bridgeFacet,
				"ValidAmountExceedsOriginal",
			)
		})

		it("Should restore bridge transaction successfully", async function () {
			await context.controlFacet.setInvalidBridgedAmountsPool(context.signers.others[0])
			const txBefore = await context.viewFacet.getBridgeTransaction(LastBridgeTransactionId)
			expect(txBefore.status).to.equal(1) // SUSPENDED

			await expect(context.bridgeFacet.restoreBridgeTransaction(LastBridgeTransactionId, e(900))).to.not.reverted

			const txAfter = await context.viewFacet.getBridgeTransaction(LastBridgeTransactionId)
			expect(txAfter.status).to.equal(0) // RECEIVED
			expect(txAfter.amount).to.equal(e(900))
		})

		it("Should update invalidBridgedAmountsPool balance", async function () {
			await context.controlFacet.setInvalidBridgedAmountsPool(context.signers.others[0])

			const pool = await context.viewFacet.getInvalidBridgedAmountsPool()
			const before = await context.viewFacet.getIsolatedBalance(pool, context.collateral)
			await context.bridgeFacet.restoreBridgeTransaction(LastBridgeTransactionId, e(900))
			const after = await context.viewFacet.getIsolatedBalance(pool, context.collateral)
			expect(after - before).to.equal(e(100)) // amount - validAmount
		})
	})
}
