import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { ZeroAddress } from "ethers"

export function shouldBehaveLikeBridgeFacet(): void {
	let context: RunContext, partyA1: PartyA, partyB1: PartyB

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

		await context.controlFacet.setBridgeStatus(context.signers.bridge1, true)
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

		it("Should fail when msgSender be partyB", async function () {
			await expect(
				context.bridgeFacet
					.connect(partyB1.getSigner)
					.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "IsPartyB")
		})

		it("Should fail when collateral not whitelisted", async function () {
			await context.controlFacet.connect(context.signers.admin).removeFromWhiteListCollateral(await context.collateralNL.getAddress())
			await expect(
				context.bridgeFacet
					.connect(partyA1.getSigner)
					.transferToBridge(context.collateralNL, e(1000), context.signers.bridge1.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "CollateralNotWhitelisted")
		})

		it("Should fail when bridge not whitelisted", async function () {
			await expect(
				context.bridgeFacet
					.connect(partyA1.getSigner)
					.transferToBridge(context.collateral, e(1000), context.signers.bridge2.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "InvalidBridge")
		})

		it("Should fail when bridge not whitelisted", async function () {
			await expect(
				context.bridgeFacet
					.connect(partyA1.getSigner)
					.transferToBridge(context.collateral, e(1000), context.signers.bridge2.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "InvalidBridge")
		})

		it("Should fail when bridge and msgSender be same", async function () {
			await expect(
				context.bridgeFacet
					.connect(context.signers.bridge1)
					.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "SameBridgeAndSender")
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
			await context.accountFacet.connect(partyA1.getSigner).activateInstantActionMode()
			await expect(
				context.bridgeFacet
					.connect(partyA1.getSigner)
					.transferToBridge(context.collateral, e(1000), context.signers.bridge1.address, partyA1.address),
			).to.be.revertedWithCustomError(context.bridgeFacet, "InstantActionModeActive")
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

			const currentIsolatedBalance = await context.viewFacet.balanceOf(partyA1.address, context.collateral)
			expect(currentIsolatedBalance).to.be.equal(e(99000))
		})
	})
}
