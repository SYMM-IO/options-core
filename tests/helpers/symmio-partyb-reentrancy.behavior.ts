import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { ethers } from "hardhat"
import { initializeTestFixture } from "../initialize-test.fixture"
import { RunContext } from "../run-context"

export function shouldGuardSymmioPartyBAgainstReentrancy(): void {
	let context: RunContext
	let calleeAddress: string
	let pingCallData: string

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		const { admin } = context.signers
		const callee = await (await ethers.getContractFactory("MockReentrantCallee")).deploy()
		await callee.waitForDeployment()
		calleeAddress = await callee.getAddress()
		pingCallData = callee.interface.encodeFunctionData("ping")

		const partyB = context.symmioPartyB.connect(admin)
		await partyB.grantRole(await partyB.TRUSTED_ROLE(), admin.address)
		await partyB.setMulticastWhitelist(calleeAddress, true)
	})

	it("executes a whitelisted multicast that does not re-enter", async function () {
		const callee = await ethers.getContractAt("MockReentrantCallee", calleeAddress)
		await expect(context.symmioPartyB.connect(context.signers.admin)._multicastCall([calleeAddress], [pingCallData])).not.to.be.reverted
		expect(await callee.hits()).to.equal(1n)
	})

	it("rejects a callee that re-enters _call during _multicastCall", async function () {
		const callee = await ethers.getContractAt("MockReentrantCallee", calleeAddress)
		await callee.setReenter(true)
		await expect(context.symmioPartyB.connect(context.signers.admin)._multicastCall([calleeAddress], [pingCallData])).to.be.revertedWith(
			"ReentrancyGuard: reentrant call",
		)
	})
}
