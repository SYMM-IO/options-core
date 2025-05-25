import { run } from "hardhat"
import { Diamond, FakeStablecoin, SignatureVerifier } from "../types"
import { createRunContext, RunContext } from "./run-context"
import { ethers, toUtf8Bytes } from "ethers"
import { e } from "../utils/e"
import { OptionType } from "./option-enums"

export async function initializeTestFixture(): Promise<RunContext> {
	const diamond: Diamond = await run("deploy:diamond")
	const mocks: Map<string, string> = await run("deploy:mocks")
	const verifier: SignatureVerifier = await run("deploy:SignatureVerifier")
	const stableCoin: FakeStablecoin = await run("deploy:stablecoin", {
		name: "MyFakeStablecoin",
		symbol: "FUSD",
	})
	const stableCoinNL: FakeStablecoin = await run("deploy:stablecoin", {
		name: "StablecoinNotListed",
		symbol: "NLUSD",
	})
	const oracle: FakeStablecoin = await run("deploy:oracle")

	let context = await createRunContext(
		await diamond.getAddress(),
		[await stableCoin.getAddress(), await stableCoinNL.getAddress()],
		await oracle.getAddress(),
		await verifier.getAddress(),
		mocks,
	)

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

	await context.controlFacet.connect(context.signers.admin).unpauseGlobal()

	await context.controlFacet.setDeactiveInstantActionModeCooldown(120)
	await context.controlFacet.setUnbindingCooldown(120)
	await context.controlFacet.setMaxConnectedCounterParties(2)
	await context.controlFacet.setMaxTradePerPartyA(3)
	await context.controlFacet.setBalanceLimitPerUser(context.collateral, e(1000000))
	await context.controlFacet.setBalanceLimitPerUser(context.collateralNL, e(1000000))
	await context.controlFacet.setDefaultFeeCollector(context.signers.feeCollector)
	await context.controlFacet.setMaxCloseOrdersLength(1)
	await context.controlFacet.setAffiliateFeesCollector(context.signers.affiliate1,context.signers.feeCollector)
	await context.controlFacet.setDefaultReleaseInterval(12)

	
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

	await context.controlFacet.setAffiliateStatus(context.signers.affiliate1, true)
	await context.controlFacet.setAffiliateFees(context.signers.affiliate1, 1, 500)

	await context.controlFacet.addOracle("test oracle", context.signers.oracle1)
	await context.controlFacet.setPriceOracleAddress(context.oracle)

	await context.controlFacet.addSymbol("BTC_PUT", OptionType.PUT, 1, context.collateral.getAddress(), 0, 0)
	await context.controlFacet.addSymbol("BTC_CALL", OptionType.CALL, 1, context.collateral.getAddress(), 0, 0)
	await context.controlFacet.addSymbol("USDT", 0, 1, context.collateralNL.getAddress(), 0, 0)
	await context.controlFacet.connect(context.signers.admin).whiteListCollateral(await context.collateral.getAddress())
	await context.controlFacet.connect(context.signers.admin).whiteListCollateral(await context.collateralNL.getAddress())

	await context.controlFacet.setSignatureVerifier(context.signatureVerifier)
	return context
}
