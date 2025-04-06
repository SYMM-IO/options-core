import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { ZeroAddress } from "ethers"
import { ethers, network } from "hardhat"

export function shouldBehaveLikeAccountFacet(): void {
	let context: RunContext, partyA1: PartyA

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		await partyA1.setBalances("500","100")
	})

	describe("Deposit", async function () {
		it("Should fail when depositing paused", async function () {
			await context.controlFacet.pauseDeposit()
			await expect(context.accountFacet.connect(partyA1.getSigner()).deposit(await context.collateral.getAddress(), "100")).to.be.revertedWith(
				"Pausable: Depositing paused",
			)
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseDeposit()
			await expect(context.accountFacet.connect(partyA1.getSigner()).deposit(await context.collateral.getAddress(), "100")).to.be.revertedWith(
				"Pausable: Global paused",
			)
		})

		it("Should fail when address suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.getSigner(), true)
			await expect(context.accountFacet.connect(partyA1.getSigner()).deposit(await context.collateral.getAddress(), "100")).to.be.revertedWith(
				"Accessibility: Sender is Suspended",
			)
		})

		it("Should fail when collateral not whitelisted", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner()).deposit(await context.signers.partyA2.getAddress(), "100")).to.be.revertedWith(
				"AccountFacet: Collateral is not whitelisted",
			)
		})

		it("Should deposit successfully", async function () {
			expect(await context.accountFacet.connect(partyA1.getSigner()).deposit(await context.collateral.getAddress(), "100")).to.be.not.reverted

			expect(await context.viewFacet.balanceOf(partyA1.getSigner(), await context.collateral.getAddress())).to.be.equal("200")
			expect(await context.collateral.balanceOf(partyA1.getSigner())).to.be.equal("300")
		})
	})

	describe("DepositFor", async function () {
		it("Should fail when depositing paused", async function () {
			await context.controlFacet.pauseDeposit()
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner())
					.depositFor(await context.collateral.getAddress(), await context.signers.partyA2.getAddress(), "100"),
			).to.be.revertedWith("Pausable: Depositing paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseDeposit()
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner())
					.depositFor(await context.collateral.getAddress(), await context.signers.partyA2.getAddress(), "100"),
			).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when msgSender address suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.getSigner(), true)
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner())
					.depositFor(await context.collateral.getAddress(), await context.signers.partyA2.getAddress(), "100"),
			).to.be.revertedWith("Accessibility: Sender is Suspended")
		})

		it("Should fail when user address suspended", async function () {
			await context.controlFacet.suspendAddress(await context.signers.partyA2.getAddress(), true)
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner())
					.depositFor(await context.collateral.getAddress(), await context.signers.partyA2.getAddress(), "100"),
			).to.be.revertedWith("Accessibility: Sender is Suspended")
		})

		it("Should depositFor successfully", async function () {
			expect(
				await context.accountFacet
					.connect(partyA1.getSigner())
					.depositFor(await context.collateral.getAddress(), await context.signers.partyA2.getAddress(), "100"),
			).to.be.not.reverted

			expect(await context.viewFacet.balanceOf(partyA1.getSigner(), await context.collateral.getAddress())).to.be.equal("100")
			expect(await context.viewFacet.balanceOf(await context.signers.partyA2.getAddress(), await context.collateral.getAddress())).to.be.equal("100")
			expect(await context.collateral.balanceOf(partyA1.getSigner())).to.be.equal("300")
		})
	})

	describe("InitiateWithdraw", async function () {
		it("Should fail when withdrawing paused", async function () {
			await context.controlFacet.pauseWithdraw()
			await expect(
				context.accountFacet.connect(partyA1.getSigner()).initiateWithdraw(await context.collateral.getAddress(), "100", partyA1.getSigner()),
			).to.be.revertedWith("Pausable: Withdrawing paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseWithdraw()
			await expect(
				context.accountFacet.connect(partyA1.getSigner()).initiateWithdraw(await context.collateral.getAddress(), "100", partyA1.getSigner()),
			).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when msgSender address suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.getSigner(), true)
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner())
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.partyA2.getAddress()),
			).to.be.revertedWith("Accessibility: Sender is Suspended")
		})

		it("Should fail when user address suspended", async function () {
			await context.controlFacet.suspendAddress(await context.signers.partyA2.getAddress(), true)
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner())
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.partyA2.getAddress()),
			).to.be.revertedWith("Accessibility: Sender is Suspended")
		})

		it("Should fail when collateral not whitelisted", async function () {
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner())
					.initiateWithdraw(await context.signers.partyA2.getAddress(), "100", await context.signers.partyA2.getAddress()),
			).to.be.revertedWith("AccountFacet: Collateral is not whitelisted")
		})

		it("Should fail when receiver address be zero address", async function () {
			await expect(
				context.accountFacet.connect(partyA1.getSigner()).initiateWithdraw(await context.collateral.getAddress(), "100", ZeroAddress),
			).to.be.revertedWith("AccountFacet: Zero address")
		})

		it("Should fail when withdraw amount be more than balance", async function () {
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner())
					.initiateWithdraw(await context.collateral.getAddress(), "200", await context.signers.partyA2.getAddress()),
			).to.be.revertedWith("AccountFacet: Insufficient balance")
		})

		it("Should fail when instant actions mode id active for msgSender", async function () {
			await context.controlFacet.setInstantActionsMode(partyA1.getSigner(), true)
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner())
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.partyA2.getAddress()),
			).to.be.revertedWith("AccountFacet: Instant action mode is activated")
		})

		it("Should initiate withdraw successfully", async function () {
			await expect(
				context.accountFacet
					.connect(partyA1.getSigner())
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.partyA2.getAddress()),
			).to.be.not.reverted

			expect(await context.viewFacet.balanceOf(partyA1.getSigner(), await context.collateral.getAddress())).to.be.equal("0")
			expect(await context.viewFacet.balanceOf(await context.signers.partyA2.getAddress(), await context.collateral.getAddress())).to.be.equal("0")
			expect(await context.collateral.balanceOf(partyA1.getSigner())).to.be.equal("400")

			const withdraw = await context.viewFacet.getWithdraw(1)

			expect(withdraw.status).to.be.equal(0) // WithdrawStatus.INITIATED
			expect(withdraw.amount).to.be.equal("100")
			expect(withdraw.user).to.be.equal(partyA1.getSigner())
			expect(withdraw.to).to.be.equal(await context.signers.partyA2.getAddress())
			expect(withdraw.collateral).to.be.equal(await context.collateral.getAddress())

			expect(await context.viewFacet.getLastWithdrawId()).to.equal(1)
		})
	})

	describe("CompleteWithdraw", async function () {
		beforeEach(async function () {
			await context.accountFacet
				.connect(partyA1.getSigner())
				.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.partyA2.getAddress())
		})

		it("Should fail when withdrawing paused", async function () {
			await context.controlFacet.pauseWithdraw()
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeWithdraw(1)).to.be.revertedWith("Pausable: Withdrawing paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseWithdraw()
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeWithdraw(1)).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when user address suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.getSigner(), true)
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeWithdraw(1)).to.be.revertedWith("Accessibility: User is Suspended")
		})

		it("Should fail when to address suspended", async function () {
			await context.controlFacet.suspendAddress(await context.signers.partyA2.getAddress(), true)
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeWithdraw(1)).to.be.revertedWith("Accessibility: Receiver is Suspended")
		})

		it("Should fail when withdrawal id suspended", async function () {
			await context.controlFacet.suspendWithdrawal(1, true)
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeWithdraw(1)).to.be.revertedWith("Accessibility: Withdrawal is Suspended")
		})

		it("Should fail when withdrawal id be wrong", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeWithdraw(2)).to.be.revertedWith("AccountFacet: Invalid Id")
		})

		it("Should fail when withdrawal status be wrong", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).completeWithdraw(1)
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeWithdraw(1)).to.be.revertedWith("AccountFacet: Invalid state")
		})

		it("Should withdraw successfully", async function () {
			expect(await context.accountFacet.connect(partyA1.getSigner()).completeWithdraw(1)).to.be.not.reverted

			const withdraw = await context.viewFacet.getWithdraw(1)

			expect(withdraw.status).to.be.equal(2) // WithdrawStatus.COMPLETED
			expect(await context.collateral.balanceOf(context.signers.partyA2)).to.be.equal("100")
		})
	})

	describe("CancelWithdraw", async function () {
		beforeEach(async function () {
			await context.accountFacet
				.connect(partyA1.getSigner())
				.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.partyA2.getAddress())
		})

		it("Should fail when withdrawing paused", async function () {
			await context.controlFacet.pauseWithdraw()
			await expect(context.accountFacet.connect(partyA1.getSigner()).cancelWithdraw(1)).to.be.revertedWith("Pausable: Withdrawing paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseWithdraw()
			await expect(context.accountFacet.connect(partyA1.getSigner()).cancelWithdraw(1)).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when user address suspended", async function () {
			await context.controlFacet.suspendAddress(partyA1.getSigner(), true)
			await expect(context.accountFacet.connect(partyA1.getSigner()).cancelWithdraw(1)).to.be.revertedWith("Accessibility: User is Suspended")
		})

		it("Should fail when to address suspended", async function () {
			await context.controlFacet.suspendAddress(await context.signers.partyA2.getAddress(), true)
			await expect(context.accountFacet.connect(partyA1.getSigner()).cancelWithdraw(1)).to.be.revertedWith("Accessibility: Receiver is Suspended")
		})

		it("Should fail when withdrawal id suspended", async function () {
			await context.controlFacet.suspendWithdrawal(1, true)
			await expect(context.accountFacet.connect(partyA1.getSigner()).cancelWithdraw(1)).to.be.revertedWith("Accessibility: Withdrawal is Suspended")
		})

		it("Should fail when withdrawal id be wrong", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner()).cancelWithdraw(2)).to.be.revertedWith("AccountFacet: Invalid Id")
		})

		it("Should fail when status is wrong", async function () {
			await context.accountFacet.completeWithdraw(1)
			await expect(context.accountFacet.connect(partyA1.getSigner()).cancelWithdraw(1)).to.be.revertedWith("AccountFacet: Invalid state")
		})

		it("Should cancel withdraw successfully", async function () {
			expect(await context.accountFacet.connect(partyA1.getSigner()).cancelWithdraw(1)).to.be.not.reverted

			const withdraw = await context.viewFacet.getWithdraw(1)

			expect(withdraw.status).to.be.equal(1) // WithdrawStatus.CANCELED
			expect(await context.viewFacet.balanceOf(partyA1.getSigner(), context.collateral)).to.be.equal(100)
		})
	})

	describe("activateInstantActionMode", async function () {
		it("Should fail when msgSender be PartyB", async function () {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 0,
				symbolType: 0,
			})

			await expect(context.accountFacet.connect(context.signers.partyB1).activateInstantActionMode()).to.be.revertedWith(
				"Accessibility: Shouldn't be partyB",
			)
		})

		it("Should fail when instance mode is active", async function () {
			context.accountFacet.connect(partyA1.getSigner()).activateInstantActionMode()
			await expect(context.accountFacet.connect(partyA1.getSigner()).activateInstantActionMode()).to.be.revertedWith(
				"AccountFacet: Instant actions mode is already activated",
			)
		})

		it("Should active instance mode successfully", async function () {
			expect(await context.accountFacet.connect(partyA1.getSigner()).activateInstantActionMode()).to.be.not.reverted
			expect(await context.viewFacet.getInstantActionsModeStatus(partyA1.getSigner())).to.be.equal(true)
		})
	})

	describe("proposeToDeactivateInstantActionMode", async function () {
		it("Should fail when msgSender be PartyB", async function () {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 0,
				symbolType: 0
			})

			await expect(context.accountFacet.connect(context.signers.partyB1).proposeToDeactivateInstantActionMode()).to.be.revertedWith(
				"Accessibility: Shouldn't be partyB",
			)
		})

		it("Should fail when instance mode is not active", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner()).proposeToDeactivateInstantActionMode()).to.be.revertedWith(
				"AccountFacet: Instant actions mode isn't activated",
			)
		})

		it("Should propose to deactivate instance mode successfully", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).activateInstantActionMode()

			expect(await context.accountFacet.connect(partyA1.getSigner()).proposeToDeactivateInstantActionMode()).to.be.not.reverted
			expect(await context.viewFacet.getInstantActionsModeStatus(partyA1.getSigner())).to.be.equal(true)

			const latestBlock = await ethers.provider.getBlock("latest")
			const time = (latestBlock?.timestamp ?? 0) + Number(await context.viewFacet.getDeactiveInstantActionModeCooldown())

			expect(await context.viewFacet.getInstantActionsModeDeactivateTime(partyA1.getSigner())).to.be.equal(time)
		})
	})

	describe("deactivateInstantActionMode", async function () {
		it("Should fail when msgSender be PartyB", async function () {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 0,
				symbolType: 0
			})

			await expect(context.accountFacet.connect(context.signers.partyB1).proposeToDeactivateInstantActionMode()).to.be.revertedWith(
				"Accessibility: Shouldn't be partyB",
			)
		})

		it("Should fail when instance mode is not active", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner()).proposeToDeactivateInstantActionMode()).to.be.revertedWith(
				"AccountFacet: Instant actions mode isn't activated",
			)
		})

		it("Should fail when deactivate instance mode cooldown not reached", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).activateInstantActionMode()
			await context.accountFacet.connect(partyA1.getSigner()).proposeToDeactivateInstantActionMode()
			await expect(context.accountFacet.connect(partyA1.getSigner()).deactivateInstantActionMode()).to.be.revertedWith(
				"AccountFacet: Cooldown is not over yet",
			)
		})

		it("Should fail when Deactivation is not proposed", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).activateInstantActionMode()
			await expect(context.accountFacet.connect(partyA1.getSigner()).deactivateInstantActionMode()).to.be.revertedWith(
				"AccountFacet: Deactivation is not proposed",
			)
		})

		it("Should propose to deactivate instance mode successfully", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).activateInstantActionMode()

			expect(await context.accountFacet.connect(partyA1.getSigner()).proposeToDeactivateInstantActionMode()).to.be.not.reverted
			expect(await context.viewFacet.getInstantActionsModeStatus(partyA1.getSigner())).to.be.equal(true)

			const latestBlock = await ethers.provider.getBlock("latest")
			const time = (latestBlock?.timestamp ?? 0) + Number(await context.viewFacet.getDeactiveInstantActionModeCooldown())

			expect(await context.viewFacet.getInstantActionsModeDeactivateTime(partyA1.getSigner())).to.be.equal(time)
		})
	})

	describe("bindToPartyB", async function () {
		beforeEach(async () => {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 0,
				symbolType: 0
			})
		})

		it("Should fail when msgSender be PartyB", async function () {
			await expect(context.accountFacet.connect(context.signers.partyB1).bindToPartyB(context.signers.partyB2)).to.be.revertedWith(
				"Accessibility: Shouldn't be partyB",
			)
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)).to.be.revertedWith(
				"Pausable: Global paused",
			)
		})

		it("Should fail when PartyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await context.controlFacet.unpauseGlobal()
			await expect(context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)).to.be.revertedWith(
				"Pausable: PartyA actions paused",
			)
		})

		it("Should fail when PartyB not active", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.others[0])).to.be.revertedWith(
				"ControlFacet: PartyB is not active",
			)
		})

		it("Should fail when already bound", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)

			await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 0,
				symbolType: 0
			})
			await expect(context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB2)).to.be.revertedWith(
				"ControlFacet: Already bound",
			)
		})

		it("Should bind successfully", async function () {
			expect(await context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)).to.be.not.reverted

			expect(await context.viewFacet.getBoundPartyB(partyA1.getSigner())).to.be.equal(await context.signers.partyB1.getAddress())
		})
	})

	describe("initiateUnbindingFromPartyB", async function () {
		beforeEach(async () => {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 0,
				symbolType: 0
			})
		})

		it("Should fail when msgSender be PartyB", async function () {
			await expect(context.accountFacet.connect(context.signers.partyB1).bindToPartyB(context.signers.partyB2)).to.be.revertedWith(
				"Accessibility: Shouldn't be partyB",
			)
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)).to.be.revertedWith(
				"Pausable: Global paused",
			)
		})

		it("Should fail when PartyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await context.controlFacet.unpauseGlobal()
			await expect(context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)).to.be.revertedWith(
				"Pausable: PartyA actions paused",
			)
		})

		it("Should fail when not bound to any partyB", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner()).initiateUnbindingFromPartyB()).to.be.revertedWith(
				"ControlFacet: Not bound to any PartyB",
			)
		})

		it("Should fail when unbindingRequestTime not zero", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)
			await context.accountFacet.connect(partyA1.getSigner()).initiateUnbindingFromPartyB()

			await expect(context.accountFacet.connect(partyA1.getSigner()).initiateUnbindingFromPartyB()).to.be.revertedWith(
				"ControlFacet: Unbinding already initiated",
			)
		})

		it("Should initiate Unbinding From PartyB successfully", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)
			expect(await context.accountFacet.connect(partyA1.getSigner()).initiateUnbindingFromPartyB()).to.be.not.reverted

			const latestBlock = await ethers.provider.getBlock("latest")
			expect(await context.viewFacet.getUnbindingRequestTime(partyA1.getSigner())).to.be.equal(latestBlock?.timestamp)
		})
	})

	describe("completeUnbindingFromPartyB", async function () {
		beforeEach(async () => {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 0,
				symbolType: 0
			})

			await context.controlFacet.setUnbindingCooldown(120)
		})

		it("Should fail when msgSender be PartyB", async function () {
			await expect(context.accountFacet.connect(context.signers.partyB1).completeUnbindingFromPartyB()).to.be.revertedWith(
				"Accessibility: Shouldn't be partyB",
			)
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeUnbindingFromPartyB()).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when PartyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await context.controlFacet.unpauseGlobal()
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeUnbindingFromPartyB()).to.be.revertedWith(
				"Pausable: PartyA actions paused",
			)
		})

		it("Should fail when not bound to any partyB", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeUnbindingFromPartyB()).to.be.revertedWith(
				"ControlFacet: Not bound to any PartyB",
			)
		})

		it("Should fail when unbindingRequestTime be zero", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)
			await context.accountFacet.connect(partyA1.getSigner()).initiateUnbindingFromPartyB()
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeUnbindingFromPartyB()).to.be.revertedWith(
				"ControlFacet: Unbinding cooldown not reached",
			)
		})

		it("Should fail when Unbinding cooldown not reached", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeUnbindingFromPartyB()).to.be.revertedWith(
				"ControlFacet: Unbinding not initiated",
			)
		})

		it("Should complete Unbinding From PartyB successfully", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)
			await context.accountFacet.connect(partyA1.getSigner()).initiateUnbindingFromPartyB()
			const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 120
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			expect(await context.accountFacet.connect(partyA1.getSigner()).completeUnbindingFromPartyB()).to.be.not.reverted

			expect(await context.viewFacet.getBoundPartyB(partyA1.getSigner())).to.be.equal(ZeroAddress)
			expect(await context.viewFacet.getUnbindingRequestTime(partyA1.getSigner())).to.be.equal(0)
		})
	})

	describe("cancelUnbindingFromPartyB", async function () {
		beforeEach(async () => {
			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 0,
				symbolType: 0
			})

			await context.controlFacet.setUnbindingCooldown(120)
		})

		it("Should fail when msgSender be PartyB", async function () {
			await expect(context.accountFacet.connect(context.signers.partyB1).completeUnbindingFromPartyB()).to.be.revertedWith(
				"Accessibility: Shouldn't be partyB",
			)
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeUnbindingFromPartyB()).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when PartyA actions paused", async function () {
			await context.controlFacet.pausePartyAActions()
			await context.controlFacet.unpauseGlobal()
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeUnbindingFromPartyB()).to.be.revertedWith(
				"Pausable: PartyA actions paused",
			)
		})

		it("Should fail when not bound to any partyB", async function () {
			await expect(context.accountFacet.connect(partyA1.getSigner()).completeUnbindingFromPartyB()).to.be.revertedWith(
				"ControlFacet: Not bound to any PartyB",
			)
		})

		it("Should fail when no pending unbinding exist", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)
			await expect(context.accountFacet.connect(partyA1.getSigner()).cancelUnbindingFromPartyB()).to.be.revertedWith(
				"ControlFacet: No pending unbinding",
			)
		})

		it("Should cancel Unbinding From PartyB successfully", async function () {
			await context.accountFacet.connect(partyA1.getSigner()).bindToPartyB(context.signers.partyB1)
			await context.accountFacet.connect(partyA1.getSigner()).initiateUnbindingFromPartyB()
			const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 120
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			expect(await context.accountFacet.connect(partyA1.getSigner()).cancelUnbindingFromPartyB()).to.be.not.reverted

			expect(await context.viewFacet.getBoundPartyB(partyA1.getSigner())).to.be.equal(context.signers.partyB1)
			expect(await context.viewFacet.getUnbindingRequestTime(partyA1.getSigner())).to.be.equal(0)
		})
	})
}
