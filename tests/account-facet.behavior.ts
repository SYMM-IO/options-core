import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { User } from "./models/user.model"
import { RunContext } from "./run-context"
import { ZeroAddress } from "ethers"

export function shouldBehaveLikeAccountFacet(): void {
	let context: RunContext, user: User, user2: User

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		user = new User(context, context.signers.user)
		await user.setBalances("500")
	})

	describe("Deposit", async function () {
		it("Should fail when depositing paused", async function () {
			await context.controlFacet.pauseDeposit()
			await expect(context.accountFacet.connect(user.getSigner()).deposit(await context.collateral.getAddress(), "100")).to.be.revertedWith(
				"Pausable: Depositing paused",
			)
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseDeposit()
			await expect(context.accountFacet.connect(user.getSigner()).deposit(await context.collateral.getAddress(), "100")).to.be.revertedWith(
				"Pausable: Global paused",
			)
		})

		it("Should fail when address suspended", async function () {
			await context.controlFacet.suspendAddress(user.getSigner(), true)
			await expect(context.accountFacet.connect(user.getSigner()).deposit(await context.collateral.getAddress(), "100")).to.be.revertedWith(
				"Accessibility: Sender is Suspended",
			)
		})

		it("Should fail when collateral not whitelisted", async function () {
			await expect(context.accountFacet.connect(user.getSigner()).deposit(await context.signers.user2.getAddress(), "100")).to.be.revertedWith(
				"AccountFacet: Collateral is not whitelisted",
			)
		})

		it("Should deposit successfully", async function () {
			expect(await context.accountFacet.connect(user.getSigner()).deposit(await context.collateral.getAddress(), "100")).to.be.not.reverted

			expect(await context.viewFacet.balanceOf(user.getSigner(), await context.collateral.getAddress())).to.be.equal("100")
			expect(await context.collateral.balanceOf(user.getSigner())).to.be.equal("400")
		})
	})

	describe("DepositFor", async function () {
		it("Should fail when depositing paused", async function () {
			await context.controlFacet.pauseDeposit()
			await expect(
				context.accountFacet
					.connect(user.getSigner())
					.depositFor(await context.collateral.getAddress(), await context.signers.user2.getAddress(), "100"),
			).to.be.revertedWith("Pausable: Depositing paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseDeposit()
			await expect(
				context.accountFacet
					.connect(user.getSigner())
					.depositFor(await context.collateral.getAddress(), await context.signers.user2.getAddress(), "100"),
			).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when msgSender address suspended", async function () {
			await context.controlFacet.suspendAddress(user.getSigner(), true)
			await expect(
				context.accountFacet
					.connect(user.getSigner())
					.depositFor(await context.collateral.getAddress(), await context.signers.user2.getAddress(), "100"),
			).to.be.revertedWith("Accessibility: Sender is Suspended")
		})

		it("Should fail when user address suspended", async function () {
			await context.controlFacet.suspendAddress(await context.signers.user2.getAddress(), true)
			await expect(
				context.accountFacet
					.connect(user.getSigner())
					.depositFor(await context.collateral.getAddress(), await context.signers.user2.getAddress(), "100"),
			).to.be.revertedWith("Accessibility: Sender is Suspended")
		})

		it("Should depositFor successfully", async function () {
			expect(
				await context.accountFacet
					.connect(user.getSigner())
					.depositFor(await context.collateral.getAddress(), await context.signers.user2.getAddress(), "100"),
			).to.be.not.reverted

			expect(await context.viewFacet.balanceOf(user.getSigner(), await context.collateral.getAddress())).to.be.equal("0")
			expect(await context.viewFacet.balanceOf(await context.signers.user2.getAddress(), await context.collateral.getAddress())).to.be.equal("100")
			expect(await context.collateral.balanceOf(user.getSigner())).to.be.equal("400")
		})
	})

	describe("InitiateWithdraw", async function () {
		beforeEach(async function () {
			await context.accountFacet.connect(user.getSigner()).deposit(await context.collateral.getAddress(), "100")
		})

		it("Should fail when withdrawing paused", async function () {
			await context.controlFacet.pauseWithdraw()
			await expect(
				context.accountFacet.connect(user.getSigner()).initiateWithdraw(await context.collateral.getAddress(), "100", user.getSigner()),
			).to.be.revertedWith("Pausable: Withdrawing paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseWithdraw()
			await expect(
				context.accountFacet.connect(user.getSigner()).initiateWithdraw(await context.collateral.getAddress(), "100", user.getSigner()),
			).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when msgSender address suspended", async function () {
			await context.controlFacet.suspendAddress(user.getSigner(), true)
			await expect(
				context.accountFacet
					.connect(user.getSigner())
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.user2.getAddress()),
			).to.be.revertedWith("Accessibility: Sender is Suspended")
		})

		it("Should fail when user address suspended", async function () {
			await context.controlFacet.suspendAddress(await context.signers.user2.getAddress(), true)
			await expect(
				context.accountFacet
					.connect(user.getSigner())
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.user2.getAddress()),
			).to.be.revertedWith("Accessibility: Sender is Suspended")
		})

		it("Should fail when collateral not whitelisted", async function () {
			await expect(
				context.accountFacet
					.connect(user.getSigner())
					.initiateWithdraw(await context.signers.user2.getAddress(), "100", await context.signers.user2.getAddress()),
			).to.be.revertedWith("AccountFacet: Collateral is not whitelisted")
		})

		it("Should fail when receiver address be zero address", async function () {
			await expect(
				context.accountFacet.connect(user.getSigner()).initiateWithdraw(await context.collateral.getAddress(), "100", ZeroAddress),
			).to.be.revertedWith("AccountFacet: Zero address")
		})

		it("Should fail when withdraw amount be more than balance", async function () {
			await expect(
				context.accountFacet
					.connect(user.getSigner())
					.initiateWithdraw(await context.collateral.getAddress(), "200", await context.signers.user2.getAddress()),
			).to.be.revertedWith("AccountFacet: Insufficient balance")
		})

		it("Should fail when instant actions mode id active for msgSender", async function () {
			await context.controlFacet.setInstantActionsMode(user.getSigner(), true)
			await expect(
				context.accountFacet
					.connect(user.getSigner())
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.user2.getAddress()),
			).to.be.revertedWith("AccountFacet: Instant action mode is activated")
		})

		it("Should initiate withdraw successfully", async function () {
			await expect(
				context.accountFacet
					.connect(user.getSigner())
					.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.user2.getAddress()),
			).to.be.not.reverted

			expect(await context.viewFacet.balanceOf(user.getSigner(), await context.collateral.getAddress())).to.be.equal("0")
			expect(await context.viewFacet.balanceOf(await context.signers.user2.getAddress(), await context.collateral.getAddress())).to.be.equal("0")
			expect(await context.collateral.balanceOf(user.getSigner())).to.be.equal("400")

			const withdraw = await context.viewFacet.getWithdraw(1)

			expect(withdraw.status).to.be.equal(0) // WithdrawStatus.INITIATED
			expect(withdraw.amount).to.be.equal("100")
			expect(withdraw.user).to.be.equal(user.getSigner())
			expect(withdraw.to).to.be.equal(await context.signers.user2.getAddress())
			expect(withdraw.collateral).to.be.equal(await context.collateral.getAddress())

			expect(await context.viewFacet.getLastWithdrawId()).to.equal(1)
		})
	})

	describe("CompleteWithdraw", async function () {
		beforeEach(async function () {
			await context.accountFacet.connect(user.getSigner()).deposit(await context.collateral.getAddress(), "100")
			await context.accountFacet
				.connect(user.getSigner())
				.initiateWithdraw(await context.collateral.getAddress(), "100", await context.signers.user2.getAddress())
		})

		it("Should fail when withdrawing paused", async function () {
			await context.controlFacet.pauseWithdraw()
			await expect(context.accountFacet.connect(user.getSigner()).completeWithdraw(1)).to.be.revertedWith("Pausable: Withdrawing paused")
		})

		it("Should fail when global paused", async function () {
			await context.controlFacet.pauseGlobal()
			await context.controlFacet.unpauseWithdraw()
			await expect(context.accountFacet.connect(user.getSigner()).completeWithdraw(1)).to.be.revertedWith("Pausable: Global paused")
		})

		it("Should fail when user address suspended", async function () {
			await context.controlFacet.suspendAddress(user.getSigner(), true)
			await expect(context.accountFacet.connect(user.getSigner()).completeWithdraw(1)).to.be.revertedWith("Accessibility: User is Suspended")
		})

		it("Should fail when to address suspended", async function () {
			await context.controlFacet.suspendAddress(await context.signers.user2.getAddress(), true)
			await expect(context.accountFacet.connect(user.getSigner()).completeWithdraw(1)).to.be.revertedWith("Accessibility: Receiver is Suspended")
		})

		it("Should fail when withdrawal id suspended", async function () {
			await context.controlFacet.suspendWithdrawal(1, true)
			await expect(context.accountFacet.connect(user.getSigner()).completeWithdraw(1)).to.be.revertedWith("Accessibility: Withdrawal is Suspended")
		})

		it("Should fail when withdrawal id be wrong", async function () {
			await expect(context.accountFacet.connect(user.getSigner()).completeWithdraw(2)).to.be.revertedWith("AccountFacet: Invalid id")
		})

		it("Should fail when withdrawal id be wrong", async function () {
			await expect(context.accountFacet.connect(user.getSigner()).completeWithdraw(2)).to.be.revertedWith("AccountFacet: Invalid id")
		})

		it("Should fail when withdrawal status be wrong", async function () {
			// TODO ::: change HardhatRunTime timestamp to pass coolDowns
			await context.accountFacet.connect(user.getSigner()).completeWithdraw(1)
			await expect(context.accountFacet.connect(user.getSigner()).completeWithdraw(1)).to.be.revertedWith("AccountFacet: Invalid state")
		})

		it("Should fail when withdrawal status be wrong", async function () {
			// TODO ::: change HardhatRunTime timestamp to pass coolDowns
			await context.accountFacet.connect(user.getSigner()).completeWithdraw(1)
			await expect(context.accountFacet.connect(user.getSigner()).completeWithdraw(1)).to.be.revertedWith("AccountFacet: Invalid state")
		})

		it("Should withdraw successdully", async function () {
			// TODO ::: change HardhatRunTime timestamp to pass coolDowns
			expect(await context.accountFacet.connect(user.getSigner()).completeWithdraw(1)).to.be.not.reverted

			const withdraw = await context.viewFacet.getWithdraw(1)

			expect(withdraw.status).to.be.equal(2) // WithdrawStatus.COMPLETED
			expect(await context.collateral.balanceOf(context.signers.user2)).to.be.equal("100")

		})
	})
}
