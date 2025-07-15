import { ethers, run } from "hardhat"
import { Diamond, FakeOracle, FakeStablecoin, InstantLayer, SignatureVerifier } from "../types"
import { createRunContext, RunContext } from "./run-context"
import { toUtf8Bytes, ZeroAddress } from "ethers"
import { e } from "../utils/e"
import { OptionType } from "./option-enums"
import { MultiAccount } from "../types/contracts/helpers"
import { grantingRoles } from "./granting-roles"

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

	const instantLayer: InstantLayer = await run("deploy:InstantLayer", {
		symmioaddress: context.common.diamondAddress,
		admin: context.signers.admin.address,
	})
	const multiAccount: MultiAccount = await run("deploy:multiAccount", {
		symmioaddress: context.common.diamondAddress,
		admin: context.signers.admin.address,
		tradeNFTAddress: ZeroAddress,
	})
	context.multiAccount = await ethers.getContractAt("MultiAccount", await multiAccount.getAddress())
	context.instantLayer = await ethers.getContractAt("InstantLayer", await instantLayer.getAddress())

	await context.controlFacet.connect(context.signers.admin).unpauseGlobal()

	await context.controlFacet.setDeactiveInstantActionModeCooldown(120)
	await context.controlFacet.setUnbindingCooldown(120)
	await context.controlFacet.setMaxConnectedCounterParties(2)
	await context.controlFacet.setMaxTradePerPartyA(3)
	await context.controlFacet.setBalanceLimitPerUser(context.collateral, e(1000000))
	await context.controlFacet.setBalanceLimitPerUser(context.collateralNL, e(1000000))
	await context.controlFacet.setDefaultFeeCollector(context.signers.feeCollector)
	await context.controlFacet.setMaxCloseOrdersLength(1)
	await context.controlFacet.setAffiliateFeesCollector(context.signers.affiliate1, context.signers.feeCollector)
	await context.controlFacet.setDefaultReleaseInterval(12)

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
	await context.controlFacet.addSymbol("BTC_PUT", OptionType.PUT, 1, context.collateral.getAddress(), 0, 0)
	await context.controlFacet.addSymbol("BTC_CALL", OptionType.CALL, 1, context.collateral.getAddress(), 0, 0)
	await context.controlFacet.addSymbol("USDT", OptionType.PUT, 1, context.collateralNL.getAddress(), 0, 0)
	await context.controlFacet.addSymbol("USDT", OptionType.CALL, 1, context.collateralNL.getAddress(), 0, 0)

	await context.controlFacet.setPartyBSupportedSymbolTypes(context.signers.partyB1, [0], [true])
	await context.controlFacet.setPartyBSupportedSymbolTypes(context.signers.partyB2, [0], [true])

	await context.controlFacet.connect(context.signers.admin).whiteListCollateral(await context.collateral.getAddress())
	await context.controlFacet.connect(context.signers.admin).whiteListCollateral(await context.collateralNL.getAddress())

	await context.controlFacet.setAffiliateStatus(context.signers.affiliate1, true)
	await context.controlFacet.setAffiliateFees(context.signers.affiliate1, [1], [e(50)])
	await context.controlFacet.setSymbolsTradingFees([1, 2, 3, 4], [e(1), e(1), e(1), e(1)])

	await context.controlFacet.setSignatureVerifier(context.signatureVerifier)
	return context
}
