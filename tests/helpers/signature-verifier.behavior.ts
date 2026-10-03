import { ethers, networkHelpers } from "../connection.js"
import { expect } from "chai"
import { hashMessage } from "ethers"
import { initializeTestFixture } from "../initialize-test.fixture.js"
import { RunContext } from "../run-context.js"

export function shouldBehaveLikeSignatureVerifier(): void {
	let context: RunContext

	beforeEach(async function () {
		context = await networkHelpers.loadFixture(initializeTestFixture)
	})

	it("accepts an ECDSA signature from an EOA", async function () {
		const signer = context.signers.others[0]
		const message = "options-core signature check"
		const sig = await signer.signMessage(message)
		expect(await context.signatureVerifier.verifySignature(signer.address, hashMessage(message), sig)).to.equal(true)
	})

	it("accepts an ECDSA signature from an address that has code (EIP-7702-style)", async function () {
		const signer = context.signers.others[0]
		const message = "options-core signature check"
		const sig = await signer.signMessage(message)
		// EIP-7702 delegation designator pointing at address zero, so there is no ERC-1271 implementation behind it.
		await ethers.provider.send("hardhat_setCode", [signer.address, "0xef0100" + "00".repeat(20)])
		// OpenZeppelin 5's default SignatureChecker returns false here because it only tries ERC-1271 when the signer has code.
		expect(await context.signatureVerifier.verifySignature(signer.address, hashMessage(message), sig)).to.equal(true)
	})
}
