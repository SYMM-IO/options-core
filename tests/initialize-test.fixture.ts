import { run } from "hardhat"
import { Diamond, FakeStablecoin } from "../types"
import { createRunContext, RunContext } from "./run-context"
import { ethers, toUtf8Bytes } from "ethers"

export async function initializeTestFixture(): Promise<RunContext> {
	const diamond: Diamond = await run("deploy:diamond")
	const stableCoin: FakeStablecoin = await run("deploy:stablecoin")
	const oracle: FakeStablecoin = await run("deploy:oracle")

	let context = await createRunContext(await diamond.getAddress(), await stableCoin.getAddress(), await oracle.getAddress())

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

	await context.controlFacet.setDeactiveInstantActionModeCooldown(120)
	await context.controlFacet.setUnbindingCooldown(120)
	await context.controlFacet.setMaxConnectedPartyBs(1)

	await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
		isActive: true,
		lossCoverage: 0,
		oracleId: 1,
		symbolType: 0,
	})

	await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
		isActive: true,
		lossCoverage: 0,
		oracleId: 1,
		symbolType: 0,
	})

	await context.controlFacet.addOracle("test oracel", context.signers.oracle1)
	await context.controlFacet.setPriceOracleAddress(context.oracle)
	await context.controlFacet.addSymbol("BTC", 0, 1, context.collateral, true, 0, 0)
	await context.controlFacet.setAffiliateStatus(context.signers.affiliate1, true)

	return context
}
