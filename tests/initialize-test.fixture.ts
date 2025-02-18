import { run } from "hardhat"
import { Diamond, FakeStablecoin } from "../types"
import { createRunContext, RunContext } from "./run-context"
import { ethers, toUtf8Bytes } from "ethers"

export async function initializeTestFixture(): Promise<RunContext> {
	const diamond: Diamond = await run("deploy:diamond")
	const stableCoin: FakeStablecoin = await run("deploy:stablecoin")

	let context = await createRunContext(await diamond.getAddress(), await stableCoin.getAddress())

	await context.controlFacet.connect(context.signers.admin).setAdmin(context.signers.admin.getAddress())
	await context.controlFacet
		.connect(context.signers.admin)
		.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("PAUSER_ROLE")))

		await context.controlFacet
		.connect(context.signers.admin)
		.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("SETTER_ROLE")))

		await context.controlFacet
		.connect(context.signers.admin)
		.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("UNPAUSER_ROLE")))

	await context.controlFacet.connect(context.signers.admin).whiteListCollateral(await context.collateral.getAddress())
	await context.controlFacet.connect(context.signers.admin).unpauseGlobal()

	return context
}
