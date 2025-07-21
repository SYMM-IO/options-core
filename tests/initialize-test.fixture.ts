import { ethers, run } from "hardhat"
import { Diamond, FakeOracle, FakeStablecoin, InstantLayer, SignatureVerifier } from "../types"
import { createRunContext, RunContext } from "./run-context"
import { toUtf8Bytes, ZeroAddress } from "ethers"
import { e } from "../utils/e"
import { OptionType } from "./option-enums"
import { MultiAccount, SymmioPartyB } from "../types/contracts/helpers"
import { grantingRoles } from "./granting-roles"
import { diamondInitialize } from "./diamond-init"

export async function initializeTestFixture(): Promise<RunContext> {
	const mocks: Map<string, string> = await run("deploy:mocks")
	const verifier: SignatureVerifier = await run("deploy:SignatureVerifier")
	const oracle: FakeOracle = await run("deploy:oracle")

	const stableCoin: FakeStablecoin = await run("deploy:stablecoin", {
		name: "MyFakeStablecoin",
		symbol: "FUSD",
	})
	const stableCoinNL: FakeStablecoin = await run("deploy:stablecoin", {
		name: "StablecoinNotListed",
		symbol: "NLUSD",
	})

	const diamond: Diamond = await run("deploy:diamond", true)

	let context = await createRunContext(
		await diamond.getAddress(),
		[await stableCoin.getAddress(), await stableCoinNL.getAddress()],
		await oracle.getAddress(),
		await verifier.getAddress(),
		mocks,
	)
	context = await grantingRoles(context)
	context = await diamondInitialize(context)

	await context.controlFacet.addOracle("test oracle", context.oracle)
	await context.controlFacet.setPriceOracleAddress(context.oracle)

	await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
		isActive: true,
		lossCoverage: 0,
		oracleId: 1,
	})

	await context.controlFacet.setPartyBConfig(context.signers.partyB2, {
		isActive: true,
		lossCoverage: 0,
		oracleId: 1,
	})
	await context.controlFacet.addSymbol("BTC_PUT", OptionType.PUT, 1, context.collateral.getAddress(), { openFee: e(1), closeFee: e(1) }, 0)
	await context.controlFacet.addSymbol("BTC_CALL", OptionType.CALL, 1, context.collateral.getAddress(), { openFee: e(1), closeFee: e(1) }, 0)
	await context.controlFacet.addSymbol("USDT", OptionType.PUT, 1, context.collateralNL.getAddress(), { openFee: e(1), closeFee: e(1) }, 0)
	await context.controlFacet.addSymbol("USDT", OptionType.CALL, 1, context.collateralNL.getAddress(), { openFee: e(1), closeFee: e(1) }, 0)

	await context.controlFacet.setPartyBSupportedSymbolTypes(context.signers.partyB1, [0], [true])
	await context.controlFacet.setPartyBSupportedSymbolTypes(context.signers.partyB2, [0], [true])

	await context.controlFacet.connect(context.signers.admin).whiteListCollateral(await context.collateral.getAddress())
	await context.controlFacet.connect(context.signers.admin).whiteListCollateral(await context.collateralNL.getAddress())

	await context.controlFacet.setAffiliateStatus(context.signers.affiliate1, true)
	await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [{ openFee: e(0.01), closeFee: e(0.02) }])

	await context.controlFacet.setSymbolsTradingFees(
		[1, 2, 3, 4],
		[
			{ openFee: e(0.01), closeFee: e(0.02) },
			{ openFee: e(0.01), closeFee: e(0.02) },
			{ openFee: e(0.01), closeFee: e(0.02) },
			{ openFee: e(0.01), closeFee: e(0.02) },
		],
	)

	await context.controlFacet.setSignatureVerifier(context.signatureVerifier)
	return context
}
