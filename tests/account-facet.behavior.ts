import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { toUtf8Bytes, ZeroAddress } from "ethers"
import { ethers, network } from "hardhat"
import { PartyB } from "./models/partyB.model"
import { withDefaults } from "@openzeppelin/hardhat-upgrades/dist/utils"
import { WithdrawStatus } from "./option-enums"
import { send } from "process"
import { zeroPad } from "@ethersproject/bytes"
import { getLatestBlockTime } from "../utils/time"
import { WithdrawStruct } from "../types/contracts/interfaces/ISymmio"

export function shouldBehaveLikeAccountFacet(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		await partyA1.setBalances(context.collateral, "500", "100")
		await partyA2.setBalances(context.collateral, "500")

		await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
			isActive: true,
			lossCoverage: 10,
			oracleId: 1,
		})

		await context.controlFacet.setUnbindingCooldown(120)
	})

	describe("Deposit", async function () {
		it("Should fail when depositing Paused", async function () {
			await context.controlFacet.pauseDeposit()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).deposit(await context.collateral.getAddress(), "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "DepositingPaused")
		})

		it("Should fail when Global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseDeposit()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).deposit(await context.collateral.getAddress(), "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "GlobalPaused")
		})

		it("Should fail when address Suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.address, true)
			await expect(
				context.accountFacet.connect(partyA1.getSigner).deposit(await context.collateral.getAddress(), "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "UserSuspended")
		})

		it("Should fail when collateral not whitelisted", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner).deposit(partyA1.address, "100")).to.be.revertedWithCustomError(
				context.accountFacet,
				"CollateralNotWhitelisted",
			)
		})

		it("Should fail when Amount is Zero", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner).deposit(await context.collateral.getAddress(), "0")).to.be.revertedWithCustomError(
				context.accountFacet,
				"ZeroAmount",
			)
		})

		it("Should fail when Caller not Solvent", async function () {
			await expect(context.clearingHouse.flagIsolatedPartyBLiquidation(partyB1.address, await context.collateral.getAddress())).not.to.reverted
			await expect(
				context.accountFacet.connect(partyB1.getSigner).deposit(await context.collateral.getAddress(), "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "NotSolvent")
		})

		it("Should fail when Balance Limit Exceeded", async function () {
			await context.controlFacet.setBalanceLimitPerUser(
				await context.collateral.getAddress(),
				await context.viewFacet.getIsolatedBalance(partyA1.address, await context.collateral.getAddress()),
			)

			await expect(
				context.accountFacet.connect(partyA1.getSigner).deposit(await context.collateral.getAddress(), "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "BalanceLimitExceeded")
		})

		it("Should deposit successfully to its Isolated Balance", async function () {
			const balanceBefore = await context.viewFacet.getIsolatedBalance(partyA1.address, await context.collateral.getAddress())

			expect(await context.accountFacet.connect(partyA1.getSigner).deposit(await context.collateral.getAddress(), "100")).to.be.not.reverted

			const balanceAfter = await context.viewFacet.getIsolatedBalance(partyA1.address, await context.collateral.getAddress())
			expect(balanceAfter - balanceBefore).to.be.equal("100")
		})

		it("Should decrease balance successfully from its Balance", async function () {
			const balanceBefore = await context.collateral.balanceOf(partyA1.address)

			await expect(context.accountFacet.connect(partyA1.getSigner).deposit(await context.collateral.getAddress(), "100")).to.be.not.reverted

			const balanceAfter = await context.collateral.balanceOf(partyA1.address)
			expect(balanceBefore - balanceAfter).to.be.equal("100")
		})
	})

	describe("Virtual Deposit For", async function () {
		beforeEach(async function () {
			await context.controlFacet.grantRole(partyA1.address, ethers.keccak256(toUtf8Bytes("VIRTUAL_DEPOSITOR_ROLE")))
		})
		it("Should fail when depositing Paused", async function () {
			await context.controlFacet.pauseDeposit()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).virtualDepositFor(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "DepositingPaused")
		})

		it("Should fail when Global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseDeposit()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).virtualDepositFor(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "GlobalPaused")
		})

		it("Should fail when User address Suspended", async function () {
			await context.controlFacet.suspendAddress(partyA2.address, true)
			await expect(
				context.accountFacet.connect(partyA1.getSigner).virtualDepositFor(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "UserSuspended")
		})

		it("Should fail when Sender Dont have the right role", async function () {
			await context.controlFacet.revokeRole(partyA1.address, ethers.keccak256(toUtf8Bytes("VIRTUAL_DEPOSITOR_ROLE")))
			await expect(
				context.accountFacet.connect(partyA1.getSigner).virtualDepositFor(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "MissingRole")
		})

		it("Should virtualDepositFor successfully to Receivers Isolated Balance", async function () {
			const balanceBefore = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress())

			expect(await context.accountFacet.connect(partyA1.getSigner).virtualDepositFor(await context.collateral.getAddress(), partyA2.address, "100"))
				.to.be.not.reverted

			const balanceAfter = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress())
			expect(balanceAfter - balanceBefore).to.be.equal(100)
		})

		it("Should NOT Decrease Sender Balance successfully from its Collateral", async function () {
			const balanceBefore = await context.collateral.balanceOf(partyA1.address)

			await expect(context.accountFacet.connect(partyA1.getSigner).virtualDepositFor(await context.collateral.getAddress(), partyA2.address, "100"))
				.to.be.not.reverted

			const balanceAfter = await context.collateral.balanceOf(partyA1.address)
			console.log("Balance Before:", balanceBefore)
			console.log("Balance After:", balanceAfter)

			expect(balanceBefore - balanceAfter).to.be.equal(0)
		})
	})

	describe("DepositFor", async function () {
		it("Should fail when depositing Paused", async function () {
			await context.controlFacet.pauseDeposit()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).depositFor(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "DepositingPaused")
		})

		it("Should fail when Global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseDeposit()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).depositFor(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "GlobalPaused")
		})

		it("Should fail when msgSender address Suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.getSigner, true)
			await expect(
				context.accountFacet.connect(partyA1.getSigner).depositFor(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "UserSuspended")
		})

		it("Should fail when user address Suspended", async function () {
			await context.controlFacet.suspendAddress(partyA2.address, true)
			await expect(
				context.accountFacet.connect(partyA1.getSigner).depositFor(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "UserSuspended")
		})

		it("Should depositFor successfully to Receivers Isolated Balance", async function () {
			const balanceBefore = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress())

			expect(await context.accountFacet.connect(partyA1.getSigner).depositFor(await context.collateral.getAddress(), partyA2.address, "100")).to.be
				.not.reverted

			const balanceAfter = await context.viewFacet.getIsolatedBalance(partyA2.address, await context.collateral.getAddress())
			expect(balanceAfter - balanceBefore).to.be.equal("100")
		})

		it("Should decrease Sender Balance successfully from its Collateral", async function () {
			const balanceBefore = await context.collateral.balanceOf(partyA1.address)

			await expect(context.accountFacet.connect(partyA1.getSigner).deposit(await context.collateral.getAddress(), "100")).to.be.not.reverted

			const balanceAfter = await context.collateral.balanceOf(partyA1.address)
			expect(balanceBefore - balanceAfter).to.be.equal("100")
		})

		it("Should depositFor successfully", async function () {
			expect(
				await context.accountFacet
					.connect(partyA1.getSigner)
					.depositFor(await context.collateral.getAddress(), await context.signers.partyA2.getAddress(), "100"),
			).to.be.not.reverted

			expect(await context.viewFacet.getIsolatedBalance(partyA1.getSigner, await context.collateral.getAddress())).to.be.equal("100")
			expect(
				await context.viewFacet.getIsolatedBalance(await context.signers.partyA2.getAddress(), await context.collateral.getAddress()),
			).to.be.equal("100")
			expect(await context.collateral.balanceOf(partyA1.getSigner)).to.be.equal("300")
		})
	})

	describe("Internal Transfer", async function () {
		it("Should fail when withdrawing Paused", async function () {
			await context.controlFacet.pauseInternalTransfer()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).internalTransfer(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "InternalTransferPaused")
		})

		it("Should fail when Global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseWithdraw()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).internalTransfer(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "GlobalPaused")
		})

		it("Should fail when Sender address Suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.address, true)
			await expect(
				context.accountFacet.connect(partyA1.getSigner).internalTransfer(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "UserSuspended")
		})

		it("Should fail when User address Suspended", async function () {
			await context.controlFacet.suspendAddress(partyA2.address, true)
			await expect(
				context.accountFacet.connect(partyA1.getSigner).internalTransfer(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "UserSuspended")
		})

		it("Should fail when User Actions Paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).internalTransfer(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "PartyAActionsPaused")
		})

		it("Should fail when Solver Actions Paused", async function () {
			await context.controlFacet.pausePartyBActions()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).internalTransfer(await context.collateral.getAddress(), partyB1.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "PartyBActionsPaused")
		})

		it("Should fail when Sender address Of Type Part B", async function () {
			await expect(
				context.accountFacet.connect(partyB1.getSigner).internalTransfer(await context.collateral.getAddress(), partyA2.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "PartyBUser")
		})

		it("Should fail when Instant Actions is Active", async function () {
			await partyA1.bindToCounterParty(partyB1.getSigner)
			await context.counterPartyRelation.connect(partyA1.getSigner).activateInstantActionMode()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).internalTransfer(await context.collateral.getAddress(), partyB1.address, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "InstantModeActive")
		})

		it("Should fail when Receiver address be zero address", async function () {
			await expect(
				context.accountFacet.connect(partyA1.getSigner).internalTransfer(await context.collateral.getAddress(), ZeroAddress, "100"),
			).to.be.revertedWithCustomError(context.accountFacet, "ZeroAddress")
		})

		it("Should fail when Amount is Zero", async function () {
			await expect(context.accountFacet.internalTransfer(await context.collateral.getAddress(), partyA2.address, "0")).to.be.revertedWithCustomError(
				context.accountFacet,
				"ZeroAmount",
			)
		})

		it("Should fail when Transfer Amount be more than available balance", async function () {
			const more = 1n
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.internalTransfer(
						await context.collateral.getAddress(),
						await context.signers.partyA2.getAddress(),
						(await context.viewFacet.getIsolatedBalance(partyA1.address, context.collateral)) +
							((await context.viewFacet.getIsolatedLockedBalance(partyA1.address, context.collateral)) + more),
					),
			).to.be.revertedWithCustomError(context.accountFacet, "InsufficientBalance")
		})

		it("Should fail when Transfer Amount causes Balance Limit Exceed ", async function () {
			const more = 1n
			await context.controlFacet.setBalanceLimitPerUser(
				context.collateral,
				(await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateral)) +
					(await context.viewFacet.getIsolatedLockedBalance(partyA2.address, context.collateral)),
			)
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.internalTransfer(await context.collateral.getAddress(), await context.signers.partyA2.getAddress(), more),
			).to.be.revertedWithCustomError(context.accountFacet, "BalanceLimitExceeded")
		})

		it("Should Decrease Sender Balances as Expected", async function () {
			const amount = "100"
			const senderBalanceBefore = await context.viewFacet.getIsolatedBalance(partyA1.address, context.collateral)
			const receiverBalanceBefore = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateral)

			await expect(context.accountFacet.connect(partyA1.getSigner).internalTransfer(await context.collateral.getAddress(), partyA2.address, amount))
				.to.be.not.reverted

			const senderBalanceAfter = await context.viewFacet.getIsolatedBalance(partyA1.address, context.collateral)
			const receiverBalanceAfter = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateral)

			expect(senderBalanceBefore - senderBalanceAfter).to.be.equal(amount)
		})

		it("Should Increase Receiver Balances as Expected", async function () {
			const amount = "100"
			const senderBalanceBefore = await context.viewFacet.getIsolatedBalance(partyA1.address, context.collateral)
			const receiverBalanceBefore = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateral)

			await expect(context.accountFacet.connect(partyA1.getSigner).internalTransfer(await context.collateral.getAddress(), partyA2.address, amount))
				.to.be.not.reverted

			const senderBalanceAfter = await context.viewFacet.getIsolatedBalance(partyA1.address, context.collateral)
			const receiverBalanceAfter = await context.viewFacet.getIsolatedBalance(partyA2.address, context.collateral)

			expect(receiverBalanceAfter - receiverBalanceBefore).to.be.equal(amount)
		})
	})

	describe("External Transfer", async function () {
		it("Should fail when withdrawing Paused", async function () {
			await context.controlFacet.pauseExternalTransfer()
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.externalTransfer(await context.collateral.getAddress(), partyA2.address, "100", partyB1.address),
			).to.be.revertedWithCustomError(context.accountFacet, "ExternalTransferPaused")
		})

		it("Should fail when Global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseWithdraw()
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.externalTransfer(await context.collateral.getAddress(), partyA2.address, "100", partyB1.address),
			).to.be.revertedWithCustomError(context.accountFacet, "GlobalPaused")
		})

		it("Should fail when Sender address Suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.address, true)
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.externalTransfer(await context.collateral.getAddress(), partyA2.address, "100", partyB1.address),
			).to.be.revertedWithCustomError(context.accountFacet, "UserSuspended")
		})

		it("Should fail when user address Not Paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.externalTransfer(await context.collateral.getAddress(), partyA2.address, "100", partyB1.address),
			).to.be.revertedWithCustomError(context.accountFacet, "PartyAActionsPaused")
		})

		it("Should fail when user address Not Paused", async function () {
			await context.controlFacet.pausePartyBActions()
			await expect(
				context.accountFacet
					.connect(partyB1.getSigner)
					.externalTransfer(await context.collateral.getAddress(), partyA2.address, "100", partyA1.address),
			).to.be.revertedWithCustomError(context.accountFacet, "PartyBActionsPaused")
		})

		it("Should fail when Instant Actions is Active", async function () {
			await partyA1.bindToCounterParty(partyB1.getSigner)
			await context.counterPartyRelation.connect(partyA1.getSigner).activateInstantActionMode()
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.externalTransfer(await context.collateral.getAddress(), partyB1.address, "100", partyA2.address),
			).to.be.revertedWithCustomError(context.accountFacet, "InstantModeActive")
		})

		it("Should fail when Receiver address be zero address", async function () {
			await expect(
				context.accountFacet.connect(partyA1.getSigner).externalTransfer(await context.collateral.getAddress(), ZeroAddress, "100", partyA1.address),
			).to.be.revertedWithCustomError(context.accountFacet, "ZeroAddress")
		})

		it("Should fail when Target address be zero address", async function () {
			await expect(
				context.accountFacet.connect(partyA1.getSigner).externalTransfer(await context.collateral.getAddress(), partyA2.address, "100", ZeroAddress),
			).to.be.revertedWithCustomError(context.accountFacet, "ZeroAddress")
		})

		it("Should fail when Amount is Zero", async function () {
			await expect(
				context.accountFacet.externalTransfer(await context.collateral.getAddress(), partyA2.address, "0", partyA1.address),
			).to.be.revertedWithCustomError(context.accountFacet, "ZeroAmount")
		})

		it("Should fail when Target Not WhiteListed", async function () {
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.externalTransfer(await context.collateral.getAddress(), partyA2.address, "100", await context.hookHandler.getAddress()),
			).to.be.revertedWithCustomError(context.accountFacet, "ExternalTransferTargetNotWhitelisted")
		})

		it("Should Decrease Sender Isolated Balances as Expected", async function () {
			const amount = "100"
			const collateralAmountToMint = 1000n
			await context.collateral.mint(context.hookHandler, collateralAmountToMint)
			const targetCollateralBalanceBefore = await context.collateral.balanceOf(await context.hookHandler.getAddress())
			const senderBalanceBefore = await context.viewFacet.getIsolatedBalance(partyA1.address, context.collateral)

			await context.controlFacet.grantRole(context.signers.admin.address, ethers.keccak256(toUtf8Bytes("EXTERNAL_TRANSFER_TARGET_MANAGER_ROLE")))
			await context.controlFacet.setExternalTransferTargetValidationStatus(await context.hookHandler.getAddress(), context.collateral, true)

			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.externalTransfer(await context.collateral.getAddress(), partyA2.address, amount, await context.hookHandler.getAddress()),
			).not.to.be.reverted

			const senderBalanceAfter = await context.viewFacet.getIsolatedBalance(partyA1.address, context.collateral)

			expect(senderBalanceBefore - senderBalanceAfter).to.be.equal(amount)
		})

		it("Should Increase Target Collateral Balances as Expected", async function () {
			const amount = "100"
			const collateralAmountToMint = 1000n
			await context.collateral.mint(context.hookHandler, collateralAmountToMint)
			const targetCollateralBalanceBefore = await context.collateral.balanceOf(await context.hookHandler.getAddress())

			await context.controlFacet.grantRole(context.signers.admin.address, ethers.keccak256(toUtf8Bytes("EXTERNAL_TRANSFER_TARGET_MANAGER_ROLE")))
			await context.controlFacet.setExternalTransferTargetValidationStatus(await context.hookHandler.getAddress(), context.collateral, true)
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.externalTransfer(await context.collateral.getAddress(), partyA2.address, amount, await context.hookHandler.getAddress()),
			).to.be.not.reverted

			const targetCollateralBalanceAfter = await context.collateral.balanceOf(await context.hookHandler.getAddress())
			console.log("Target Collateral Before:", targetCollateralBalanceBefore)
			console.log("Target Collateral After:", targetCollateralBalanceAfter)

			expect(targetCollateralBalanceAfter - targetCollateralBalanceBefore).to.be.equal(amount)
		})

		it("Should Decrease Sender Collateral Balances as Expected", async function () {
			const amount = "100"
			const collateralAmountToMint = 1000n
			await context.collateral.mint(context.common.diamondAddress, collateralAmountToMint)
			await context.collateral.mint(context.hookHandler, collateralAmountToMint)

			const senderCollateralBalanceBefore = await context.collateral.balanceOf(context.common.diamondAddress)

			await context.controlFacet.grantRole(context.signers.admin.address, ethers.keccak256(toUtf8Bytes("EXTERNAL_TRANSFER_TARGET_MANAGER_ROLE")))
			await context.controlFacet.setExternalTransferTargetValidationStatus(await context.hookHandler.getAddress(), context.collateral, true)
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.externalTransfer(await context.collateral.getAddress(), context.common.diamondAddress, amount, await context.hookHandler.getAddress()),
			).to.be.not.reverted

			const senderCollateralBalanceAfter = await context.collateral.balanceOf(context.common.diamondAddress)
			console.log("Sender Collateral Before:", senderCollateralBalanceBefore)
			console.log("Sender Collateral After:", senderCollateralBalanceAfter)

			expect(senderCollateralBalanceBefore - senderCollateralBalanceAfter).to.be.equal(amount)
		})
	})

	describe("InitiateWithdraw", async function () {
		it("Should fail when withdrawing Paused", async function () {
			await context.controlFacet.pauseWithdraw()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).initiateWithdraw(await context.collateral.getAddress(), "100", partyA1.getSigner),
			).to.be.revertedWithCustomError(context.accountFacet, "WithdrawingPaused")
		})

		it("Should fail when Global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseWithdraw()
			await expect(
				context.accountFacet.connect(partyA1.getSigner).initiateWithdraw(await context.collateral.getAddress(), "100", partyA1.getSigner),
			).to.be.revertedWithCustomError(context.accountFacet, "GlobalPaused")
		})

		it("Should fail when msgSender address Suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.getSigner, true)
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.partyA2.getAddress()),
			).to.be.revertedWithCustomError(context.accountFacet, "UserSuspended")
		})

		it("Should fail when user address Suspended", async function () {
			await context.controlFacet.suspendAddress(await context.signers.partyA2.getAddress(), true)
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.partyA2.getAddress()),
			).to.be.revertedWithCustomError(context.accountFacet, "UserSuspended")
		})

		it("Should fail when user Actions Paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.partyA2.getAddress()),
			).to.be.revertedWithCustomError(context.accountFacet, "PartyAActionsPaused")
		})

		it("Should fail when Solver Actions Paused", async function () {
			await context.controlFacet.pausePartyBActions()
			await expect(
				context.accountFacet
					.connect(partyB1.getSigner)
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.partyA2.getAddress()),
			).to.be.revertedWithCustomError(context.accountFacet, "PartyBActionsPaused")
		})

		it("Should fail when instant actions mode is active for msgSender", async function () {
			await partyA1.bindToCounterParty(partyB1.getSigner)
			await partyA1.activateInstantActionMode()
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.partyA2.getAddress()),
			).to.be.revertedWithCustomError(context.accountFacet, "InstantModeActive")
		})

		it("Should fail when receiver address be zero address", async function () {
			await expect(
				context.accountFacet.connect(partyA1.getSigner).initiateWithdraw(await context.collateral.getAddress(), "100", ZeroAddress),
			).to.be.revertedWithCustomError(context.accountFacet, "ZeroAddress")
		})

		it("Should fail when Sent Amount is ZERO", async function () {
			await expect(
				context.accountFacet.connect(partyA1.getSigner).initiateWithdraw(await context.collateral.getAddress(), 0, partyA2.address),
			).to.be.revertedWithCustomError(context.accountFacet, "ZeroAmount")
		})

		it("Should fail when withdraw amount be more than balance", async function () {
			await expect(
				context.accountFacet.connect(partyA1.getSigner).initiateWithdraw(await context.collateral.getAddress(), "200", partyA2.address),
			).to.be.revertedWithCustomError(context.accountFacet, "InsufficientBalance(address,address,uint256,uint256)")
		})

		it("Should fail when Sender as Party B not Solvent", async function () {
			await partyB1.setBalances(context.collateral, "10000", "5000")

			await expect(context.clearingHouse.flagPartyALiquidation(ZeroAddress, partyB1.address, await context.collateral.getAddress())).not.to.reverted
			await expect(
				context.accountFacet.connect(partyB1.getSigner).initiateWithdraw(await context.collateral.getAddress(), "100", partyA2.address),
			).to.be.revertedWithCustomError(context.accountFacet, "NotSolvent")
		})

		it("Should Pass when Sender as Party A No Solvency Check", async function () {
			await expect(context.clearingHouse.flagPartyALiquidation(partyA1.address, ZeroAddress, await context.collateral.getAddress())).not.to.reverted
			await expect(context.accountFacet.connect(partyA1.getSigner).initiateWithdraw(await context.collateral.getAddress(), "100", partyA2.address)).to
				.not.reverted
		})

		it("Should Decease Sender Isolated Balance as expected", async function () {
			const amount = 100
			const isolatedBalanceBefore = await context.viewFacet.getIsolatedBalance(partyA1.address, await context.collateral.getAddress())

			await expect(context.accountFacet.connect(partyA1.getSigner).initiateWithdraw(await context.collateral.getAddress(), amount, partyA2.address))
				.to.not.reverted

			const isolatedBalanceAfter = await context.viewFacet.getIsolatedBalance(partyA1.address, await context.collateral.getAddress())

			expect(isolatedBalanceBefore - isolatedBalanceAfter).to.equal(amount)
		})

		it("Should initiate withdraw successfully", async function () {
			await partyA1.setBalances(context.collateral, "10000", "5000")
			const amount = 100
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.initiateWithdraw(await context.collateral.getAddress(), amount, await context.signers.partyA2.getAddress()),
			).to.be.not.reverted

			const lastWithdraw = await context.viewFacet.getLastWithdrawalId()
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner)
					.initiateWithdraw(await context.collateral.getAddress(), amount * 2, await context.signers.partyA2.getAddress()),
			).not.to.be.reverted

			console.log("Last ID:", lastWithdraw)
			const lastWithdrawAfter = await context.viewFacet.getLastWithdrawalId()
			console.log("Last ID After:", lastWithdrawAfter)

			const withdraw: WithdrawStruct = await context.viewFacet.getWithdrawal(lastWithdrawAfter)

			expect(withdraw.status).to.be.equal(WithdrawStatus.INITIATED) // WithdrawStatus.INITIATED
			expect(withdraw.amount).to.be.equal(amount * 2)
			expect(withdraw.user).to.be.equal(partyA1.address)
			expect(withdraw.to).to.be.equal(partyA2.address)
			expect(withdraw.collateral).to.be.equal(await context.collateral.getAddress())
			expect(withdraw.timestamp).to.be.equal(await getLatestBlockTime())
			expect(withdraw.isVirtual).to.be.equal(false)
			expect(withdraw.provider).to.be.equal(ZeroAddress.toString())
			expect(withdraw.userData).to.be.equal("0x")

			expect(lastWithdrawAfter).to.equal(2)
		})
	})

	describe("CompleteWithdraw", async function () {
		beforeEach(async function () {
			const amount = 100
			await context.accountFacet
				.connect(partyA1.getSigner)
				.initiateWithdraw(await context.collateral.getAddress(), amount, await context.signers.partyA2.getAddress())
		})

		it("Should fail when withdrawing Paused", async function () {
			await context.controlFacet.pauseWithdraw()
			await expect(context.accountFacet.connect(partyA1.getSigner).completeWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"WithdrawingPaused",
			)
		})

		it("Should fail when Global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(context.accountFacet.connect(partyA1.getSigner).completeWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"GlobalPaused",
			)
		})

		it("Should fail when user address Suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.getSigner, true)
			await expect(context.accountFacet.connect(partyA1.getSigner).completeWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"UserSuspended",
			)
		})

		it("Should fail when Target address Suspended", async function () {
			await context.controlFacet.suspendAddress(await context.signers.partyA2.getAddress(), true)
			await expect(context.accountFacet.connect(partyA1.getSigner).completeWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"UserSuspended",
			)
		})

		it("Should fail when withdrawal id Suspended", async function () {
			await context.controlFacet.suspendWithdrawal(1, true)
			await expect(context.accountFacet.connect(partyA1.getSigner).completeWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"WithdrawalSuspended",
			)
		})

		it("Should fail when withdrawal id be wrong", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner).completeWithdraw(2)).to.be.revertedWithCustomError(
				context.accountFacet,
				"InvalidWithdrawalId",
			)
		})

		it("Should fail when withdrawal status be wrong", async function () {
			await context.accountFacet.connect(partyA1.getSigner).completeWithdraw(1)
			await expect(context.accountFacet.connect(partyA1.getSigner).completeWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"InvalidState",
			)
		})

		it("Should fail when withdrawal CoolDown Not Passed Party A", async function () {
			const coolDownTimeout = (await getLatestBlockTime()) + 1000
			await context.controlFacet.setTimingParameters(
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
			)
			await expect(context.accountFacet.connect(partyA1.getSigner).completeWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"CooldownNotOver",
			)
		})

		it("Should fail when withdrawal CoolDown Not Passed Party B", async function () {
			const amount = 100
			await partyB1.setBalances(context.collateral, 1000, 500)

			const coolDownTimeout = (await getLatestBlockTime()) + 1000
			await context.controlFacet.setTimingParameters(
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
				coolDownTimeout,
			)

			await context.accountFacet
				.connect(partyB1.getSigner)
				.initiateWithdraw(await context.collateral.getAddress(), amount, await context.signers.partyA2.getAddress())

			await expect(context.accountFacet.connect(partyB1.getSigner).completeWithdraw(2)).to.be.revertedWithCustomError(
				context.accountFacet,
				"CooldownNotOver",
			)
		})

		it("Should withdraw successfully", async function () {
			const balanceBefore = await context.collateral.balanceOf(context.signers.partyA2)
			await expect(context.accountFacet.connect(partyA1.getSigner).completeWithdraw(1)).to.be.not.reverted

			const withdraw = await context.viewFacet.getWithdrawal(1)

			const balanceAfter = await context.collateral.balanceOf(partyA2.address)
			expect(withdraw.status).to.be.equal(WithdrawStatus.COMPLETED)
			expect(balanceAfter - balanceBefore).to.be.equal(withdraw.amount)
		})
	})

	describe("CancelWithdraw", async function () {
		beforeEach(async function () {
			const amount = 100
			await context.accountFacet
				.connect(partyA1.getSigner)
				.initiateWithdraw(await context.collateral.getAddress(), amount, await context.signers.partyA2.getAddress())
		})

		it("Should fail when withdrawing Paused", async function () {
			await context.controlFacet.pauseWithdraw()
			await expect(context.accountFacet.connect(partyA1.getSigner).cancelWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"WithdrawingPaused",
			)
		})

		it("Should fail when Global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseWithdraw()
			await expect(context.accountFacet.connect(partyA1.getSigner).cancelWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"GlobalPaused",
			)
		})

		it("Should fail when User address Suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.getSigner, true)
			await expect(context.accountFacet.connect(partyA1.getSigner).cancelWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"UserSuspended",
			)
		})

		it("Should fail when Target address Suspended", async function () {
			await context.controlFacet.suspendAddress(await context.signers.partyA2.getAddress(), true)
			await expect(context.accountFacet.connect(partyA1.getSigner).cancelWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"UserSuspended",
			)
		})

		it("Should fail when withdrawal id Suspended", async function () {
			await context.controlFacet.suspendWithdrawal(1, true)
			await expect(context.accountFacet.connect(partyA1.getSigner).cancelWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"WithdrawalSuspended",
			)
		})

		it("Should fail when withdrawal id be wrong", async function () {
			const lastId = await context.viewFacet.getLastWithdrawalId()
			await expect(context.accountFacet.connect(partyA1.getSigner).cancelWithdraw(lastId + 1n)).to.be.revertedWithCustomError(
				context.accountFacet,
				"InvalidWithdrawalId",
			)
		})

		it("Should fail when status is wrong", async function () {
			await context.accountFacet.completeWithdraw(1)
			await expect(context.accountFacet.connect(partyA1.getSigner).cancelWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"InvalidState",
			)
		})

		it("Should fail when status is wrong", async function () {
			// TODO express withdraw cancel not allowed
		})

		it("Should fail when Isolated Balance Exceeds Limit", async function () {
			const withdraw = await context.viewFacet.getWithdrawal(1)
			const userBalance = await context.viewFacet.getIsolatedBalance(withdraw.user, withdraw.collateral)
			await context.controlFacet.setBalanceLimitPerUser(withdraw.collateral, userBalance)

			await expect(context.accountFacet.connect(partyA1.getSigner).cancelWithdraw(1)).to.be.revertedWithCustomError(
				context.accountFacet,
				"BalanceLimitExceeded",
			)
		})

		it("Should Not fail in Isolated Balance Exceeds Limit when User is Party B", async function () {
			const amount = 100
			await partyB1.setBalances(context.collateral, 1000, 500)
			await context.accountFacet
				.connect(partyB1.getSigner)
				.initiateWithdraw(await context.collateral.getAddress(), amount, await context.signers.partyA2.getAddress())

			const withdraw = await context.viewFacet.getWithdrawal(await context.viewFacet.getLastWithdrawalId())
			const userBalance = await context.viewFacet.getIsolatedBalance(withdraw.user, withdraw.collateral)
			await context.controlFacet.setBalanceLimitPerUser(withdraw.collateral, userBalance)

			await expect(context.accountFacet.connect(partyA1.getSigner).cancelWithdraw(1)).not.to.be.reverted
		})

		it("Should fail when Sender as Party B not Solvent", async function () {
			const amount = 100
			await partyB1.setBalances(context.collateral, 1000, 500)
			await context.accountFacet
				.connect(partyB1.getSigner)
				.initiateWithdraw(await context.collateral.getAddress(), amount, await context.signers.partyA2.getAddress())

			await expect(context.clearingHouse.flagIsolatedPartyBLiquidation(partyB1.address, await context.collateral.getAddress())).not.to.reverted
			await expect(
				context.accountFacet.connect(partyB1.getSigner).cancelWithdraw(await context.viewFacet.getLastWithdrawalId()),
			).to.be.revertedWithCustomError(context.accountFacet, "NotSolvent")
		})

		it("Should Pass when Sender as Party A No Solvency Check", async function () {
			await expect(context.clearingHouse.flagPartyALiquidation(partyA1.address, ZeroAddress, await context.collateral.getAddress())).not.to.reverted
			await expect(context.accountFacet.connect(partyA1.getSigner).cancelWithdraw(await context.viewFacet.getLastWithdrawalId())).to.not.reverted
		})

		it("Should cancel withdraw successfully", async function () {
			const isolatedBalanceBefore = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral)

			expect(await context.accountFacet.connect(partyA1.getSigner).cancelWithdraw(1)).to.be.not.reverted
			const withdraw = await context.viewFacet.getWithdrawal(1)

			const isolatedBalanceAfter = await context.viewFacet.getIsolatedBalance(partyA1.getSigner, context.collateral)

			expect(withdraw.status).to.be.equal(WithdrawStatus.CANCELED)
			expect(isolatedBalanceAfter - isolatedBalanceBefore).to.be.equal(withdraw.amount)
		})
	})

	describe("Suspend Withdraw", async function () {
		beforeEach(async function () {
			const amount = 100
			await context.accountFacet
				.connect(partyA1.getSigner)
				.initiateWithdraw(await context.collateral.getAddress(), amount, await context.signers.partyA2.getAddress())
		})

		it("Should fail when Not with Proper Role", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner).suspendWithdraw(1)).to.be.reverted
		})

		it("Should fail when status is wrong", async function () {
			await context.accountFacet.completeWithdraw(1)
			await expect(context.accountFacet.suspendWithdraw(1)).to.be.revertedWithCustomError(context.accountFacet, "InvalidState")
		})

		it("Should Pass ...", async function () {
			await expect(context.accountFacet.suspendWithdraw(1)).not.to.be.reverted

			const withdraw = await context.viewFacet.getWithdrawal(await context.viewFacet.getLastWithdrawalId())
			expect(withdraw.status).to.equal(WithdrawStatus.SUSPENDED)
		})
	})

	describe("Restore Withdraw", async function () {
		beforeEach(async function () {
			const amount = 100
			await context.accountFacet
				.connect(partyA1.getSigner)
				.initiateWithdraw(await context.collateral.getAddress(), amount, await context.signers.partyA2.getAddress())
		})

		it("Should fail when Not with Proper Role", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner).restoreWithdraw(1, 98)).to.be.reverted
		})

		it("Should fail when status is wrong", async function () {
			await context.accountFacet.completeWithdraw(1)
			await expect(context.accountFacet.restoreWithdraw(1, 98)).to.be.revertedWithCustomError(context.accountFacet, "InvalidState")
		})

		it("Should fail when Withdrawal Pool not Set", async function () {
			await context.accountFacet.suspendWithdraw(1)

			// await context.controlFacet.setInvalidWithdrawalsAmountsPool(ZeroAddress.toString())

			// await expect(context.accountFacet.restoreWithdraw(1, 98)).to.be.revertedWithCustomError(context.accountFacet, "ZeroAddress")
			//TODO find a way to implement zero address
		})

		it("Should fail when Valid Amount is More than Withdrawal Amount", async function () {
			const withdraw = await context.viewFacet.getWithdrawal(await context.viewFacet.getLastWithdrawalId())

			await context.accountFacet.suspendWithdraw(1)
			await context.controlFacet.setInvalidWithdrawalsAmountsPool(partyB1.address)
			await expect(context.accountFacet.restoreWithdraw(1, withdraw.amount + 1n)).to.be.revertedWithCustomError(
				context.accountFacet,
				"ValidAmountExceedsOriginal",
			)
		})

		it("Should Successfully Update the Pool Balance and State ", async function () {
			const surplus = 10n
			let withdraw = await context.viewFacet.getWithdrawal(await context.viewFacet.getLastWithdrawalId())

			const PoolBalanceBefore = await context.viewFacet.getIsolatedBalance(partyB1.address, context.collateral)

			await context.accountFacet.suspendWithdraw(1)
			await context.controlFacet.setInvalidWithdrawalsAmountsPool(partyB1.address)
			await expect(context.accountFacet.restoreWithdraw(1, withdraw.amount - surplus)).not.to.be.reverted
			withdraw = await context.viewFacet.getWithdrawal(await context.viewFacet.getLastWithdrawalId())

			const PoolBalanceAfter = await context.viewFacet.getIsolatedBalance(partyB1.address, context.collateral)

			expect(PoolBalanceAfter - PoolBalanceBefore).to.equal(surplus)
			expect(withdraw.status).to.equal(WithdrawStatus.INITIATED)
		})
	})

	describe("activateInstantActionMode", async function () {
		beforeEach(async () => {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})
			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(partyB1.address)
		})

		it("Should fail when not bound to any partyB", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).initiateUnbindingFromPartyB()

			const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 120
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])

			await context.counterPartyRelation.connect(partyA1.getSigner).completeUnbindingFromPartyB()

			await expect(context.counterPartyRelation.connect(partyA1.getSigner).activateInstantActionMode()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"BoundedPartyBNotFound",
			)
		})

		it("Should fail when msgSender be PartyB", async function () {
			await expect(context.counterPartyRelation.connect(context.signers.partyB1).activateInstantActionMode()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"PartyBUser",
			)
		})

		it("Should fail when instance mode is active", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).activateInstantActionMode()
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).activateInstantActionMode()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"InstantModeActive",
			)
		})

		it("Should active instance mode successfully", async function () {
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).activateInstantActionMode()).to.be.not.reverted
			expect(await context.viewFacet.isInstantActionsModeActive(partyA1.getSigner)).to.be.equal(true)
		})
	})

	describe("proposeToDeactivateInstantActionMode", async function () {
		beforeEach(async () => {
			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(partyB1.address)
		})
		it("Should fail when msgSender be PartyB", async function () {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})

			await expect(
				context.counterPartyRelation.connect(context.signers.partyB1).proposeToDeactivateInstantActionMode(),
			).to.be.revertedWithCustomError(context.counterPartyRelation, "PartyBUser")
		})

		it("Should fail when instance mode is not active", async function () {
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).proposeToDeactivateInstantActionMode()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"InstantModeNotActive",
			)
		})

		it("Should propose to deactivate instance mode successfully", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).activateInstantActionMode()

			await expect(context.counterPartyRelation.connect(partyA1.getSigner).proposeToDeactivateInstantActionMode()).to.be.not.reverted
			expect(await context.viewFacet.isInstantActionsModeActive(partyA1.getSigner)).to.be.equal(true)

			const latestBlock = await ethers.provider.getBlock("latest")
			const time = (latestBlock?.timestamp ?? 0) + Number(await context.viewFacet.getDeactiveInstantActionModeCooldown())

			expect(await context.viewFacet.getInstantActionsModeDeactivateTime(partyA1.getSigner)).to.be.equal(time)
		})
	})

	describe("deactivateInstantActionMode", async function () {
		beforeEach(async () => {
			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(partyB1.address)
		})
		it("Should fail when msgSender be PartyB", async function () {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})

			await expect(
				context.counterPartyRelation.connect(context.signers.partyB1).proposeToDeactivateInstantActionMode(),
			).to.be.revertedWithCustomError(context.counterPartyRelation, "PartyBUser")
		})

		it("Should fail when instance mode is not active", async function () {
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).proposeToDeactivateInstantActionMode()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"InstantModeNotActive",
			)
		})

		it("Should fail when deactivate instance mode cooldown not reached", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).activateInstantActionMode()
			await context.counterPartyRelation.connect(partyA1.getSigner).proposeToDeactivateInstantActionMode()
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).deactivateInstantActionMode()).to.be.revertedWithCustomError(
				context.accountFacet,
				"CooldownNotOver",
			)
		})

		it("Should fail when Deactivation is not proposed", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).activateInstantActionMode()
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).deactivateInstantActionMode()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"DeactivationNotProposed",
			)
		})

		it("Should propose to deactivate instance mode successfully", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).activateInstantActionMode()

			expect(await context.counterPartyRelation.connect(partyA1.getSigner).proposeToDeactivateInstantActionMode()).to.be.not.reverted
			expect(await context.viewFacet.isInstantActionsModeActive(partyA1.getSigner)).to.be.equal(true)

			const latestBlock = await ethers.provider.getBlock("latest")
			const time = (latestBlock?.timestamp ?? 0) + Number(await context.viewFacet.getDeactiveInstantActionModeCooldown())

			expect(await context.viewFacet.getInstantActionsModeDeactivateTime(partyA1.getSigner)).to.be.equal(time)
		})
	})

	describe("bindToPartyB", async function () {
		beforeEach(async () => {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})
		})

		it("Should fail when msgSender be PartyB", async function () {
			await expect(context.counterPartyRelation.connect(context.signers.partyB1).bindToPartyB(context.signers.partyB2)).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"PartyBUser",
			)
		})

		it("Should fail when Global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"GlobalPaused",
			)
		})

		it("Should fail when PartyA actions Paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await context.controlFacet.unpauseGlobal()
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"PartyAActionsPaused",
			)
		})

		it("Should fail when PartyB not active", async function () {
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.others[0])).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"PartyBNotActive",
			)
		})

		it("Should fail when already bound", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)

			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB2)).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"BoundedToAnotherPartyB",
			)
		})

		it("Should bind successfully", async function () {
			expect(await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)).to.be.not.reverted

			expect(await context.viewFacet.getBoundPartyB(partyA1.getSigner)).to.be.equal(await context.signers.partyB1.getAddress())
		})
	})

	describe("initiateUnbindingFromPartyB", async function () {
		beforeEach(async () => {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})
		})

		it("Should fail when msgSender be PartyB", async function () {
			await expect(context.counterPartyRelation.connect(context.signers.partyB1).bindToPartyB(context.signers.partyB2)).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"PartyBUser",
			)
		})

		it("Should fail when Global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"GlobalPaused",
			)
		})

		it("Should fail when PartyA actions Paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await context.controlFacet.unpauseGlobal()
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"PartyAActionsPaused",
			)
		})

		it("Should fail when not bound to any partyB", async function () {
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).initiateUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"BoundedPartyBNotFound",
			)
		})

		it("Should fail when unbindingRequestTime not zero", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)
			await context.counterPartyRelation.connect(partyA1.getSigner).initiateUnbindingFromPartyB()

			await expect(context.counterPartyRelation.connect(partyA1.getSigner).initiateUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"UnbindingAlreadyInProgress",
			)
		})

		it("Should initiate Unbinding From PartyB successfully", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)
			expect(await context.counterPartyRelation.connect(partyA1.getSigner).initiateUnbindingFromPartyB()).to.be.not.reverted

			const latestBlock = await ethers.provider.getBlock("latest")
			expect(await context.viewFacet.getUnbindingRequestTime(partyA1.getSigner)).to.be.equal(latestBlock?.timestamp)
		})
	})

	describe("completeUnbindingFromPartyB", async function () {
		it("Should fail when msgSender be PartyB", async function () {
			await expect(context.counterPartyRelation.connect(context.signers.partyB1).completeUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"PartyBUser",
			)
		})

		it("Should fail when Global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).completeUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.accountFacet,
				"GlobalPaused",
			)
		})

		it("Should fail when PartyA actions Paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await context.controlFacet.unpauseGlobal()
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).completeUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.accountFacet,
				"PartyAActionsPaused",
			)
		})

		it("Should fail when not bound to any partyB", async function () {
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).completeUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"BoundedPartyBNotFound",
			)
		})

		it("Should fail when unbindingRequestTime be zero", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)
			await context.counterPartyRelation.connect(partyA1.getSigner).initiateUnbindingFromPartyB()
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).completeUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"CooldownNotOver",
			)
		})

		it("Should fail when Unbinding cooldown not reached", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).completeUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"UnbindingNotInitiated",
			)
		})

		it("Should complete Unbinding From PartyB successfully", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)
			await context.counterPartyRelation.connect(partyA1.getSigner).initiateUnbindingFromPartyB()
			const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 120
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			expect(await context.counterPartyRelation.connect(partyA1.getSigner).completeUnbindingFromPartyB()).to.be.not.reverted

			expect(await context.viewFacet.getBoundPartyB(partyA1.getSigner)).to.be.equal(ZeroAddress)
			expect(await context.viewFacet.getUnbindingRequestTime(partyA1.getSigner)).to.be.equal(0)
		})
	})

	describe("cancelUnbindingFromPartyB", async function () {
		beforeEach(async () => {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})

			await context.controlFacet.setUnbindingCooldown(120)
		})

		it("Should fail when Party B is the MSG Sender", async function () {
			await expect(context.counterPartyRelation.connect(context.signers.partyB1).completeUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.accountFacet,
				"PartyBUser",
			)
		})

		it("Should fail when Global Paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).completeUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.accountFacet,
				"GlobalPaused",
			)
		})

		it("Should fail when PartyA actions Paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await context.controlFacet.unpauseGlobal()
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).completeUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.accountFacet,
				"PartyAActionsPaused",
			)
		})

		it("Should fail when not bound to any partyB", async function () {
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).completeUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"BoundedPartyBNotFound",
			)
		})

		it("Should fail when no pending unbinding exist", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)
			await expect(context.counterPartyRelation.connect(partyA1.getSigner).cancelUnbindingFromPartyB()).to.be.revertedWithCustomError(
				context.counterPartyRelation,
				"UnbindingNotInitiated",
			)
		})

		it("Should cancel Unbinding From PartyB successfully", async function () {
			await context.counterPartyRelation.connect(partyA1.getSigner).bindToPartyB(context.signers.partyB1)
			await context.counterPartyRelation.connect(partyA1.getSigner).initiateUnbindingFromPartyB()
			const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 120
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			expect(await context.counterPartyRelation.connect(partyA1.getSigner).cancelUnbindingFromPartyB()).to.be.not.reverted

			expect(await context.viewFacet.getBoundPartyB(partyA1.getSigner)).to.be.equal(context.signers.partyB1)
			expect(await context.viewFacet.getUnbindingRequestTime(partyA1.getSigner)).to.be.equal(0)
		})
	})
}
