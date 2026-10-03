import { ethers } from "../connection.js"
import { RunContext } from "../run-context.js"
import { grantingRoles } from "../granting-roles.js"
import { diamondInitialize } from "../diamond-init.js"
import { deployDiamond, deployFakeOracle, deploySignatureVerifier, deployStablecoin } from "../../tasks/deployment/deploy-lib.js"
import { e } from "../../utils/e.js"
import { OptionType } from "../option-enums.js"

// Deploy the production Diamond and facets. Native execution needs no account proxies,
// MultiAccount, SymmioPartyB, or InstantLayer contracts.
export async function initializeNativeBucketsFixture(): Promise<RunContext> {
	const diamond = await deployDiamond(ethers, false)
	const address = await diamond.getAddress()
	const signers = await ethers.getSigners()
	let context = new RunContext()
	context.signers = {
		admin: signers[0],
		partyA1: signers[1],
		partyA2: signers[2],
		feeCollector: signers[3],
		partyB1: signers[4],
		partyB2: signers[5],
		oracle1: signers[6],
		affiliate1: signers[7],
		bridge1: signers[8],
		bridge2: signers[9],
		clearingHouse: signers[10],
		others: [signers[11], signers[12]],
	}
	context.common = { diamondAddress: address, chainId: Number((await ethers.provider.getNetwork()).chainId) }
	context.collateral = await deployStablecoin(ethers, "Native bucket collateral", "NATIVE")
	context.collateralNL = await deployStablecoin(ethers, "Native bucket fee token", "FEE")
	context.oracle = await deployFakeOracle(ethers)
	context.signatureVerifier = await deploySignatureVerifier(ethers)
	context.accountFacet = await ethers.getContractAt("AccountFacet", address)
	context.controlFacet = await ethers.getContractAt("ControlFacet", address)
	context.viewFacet = await ethers.getContractAt("ViewFacet", address)
	context.partyAOpenFacet = await ethers.getContractAt("PartyAOpenFacet", address)
	context.partyBOpenFacet = await ethers.getContractAt("PartyBOpenFacet", address)
	context.partyACloseFacet = await ethers.getContractAt("PartyACloseFacet", address)
	context.partyBCloseFacet = await ethers.getContractAt("PartyBCloseFacet", address)
	context.tradeFacet = await ethers.getContractAt("TradeFacet", address)
	context.forceActionsFacet = await ethers.getContractAt("ForceActionsFacet", address)
	context.clearingHouse = await ethers.getContractAt("ClearingHouseFacet", address)
	context.counterPartyRelation = await ethers.getContractAt("CounterPartyRelationsFacet", address)
	context = await grantingRoles(context)
	context = await diamondInitialize(context)
	await context.controlFacet.addOracle("Native test oracle", await context.oracle.getAddress())
	await context.controlFacet.setPriceOracleAddress(await context.oracle.getAddress())
	await context.controlFacet.setUpnlSigValidTime(300)
	await context.controlFacet.setSettlementPriceSigValidTime(300)
	for (const signer of [context.signers.partyB1, context.signers.partyB2]) {
		await context.controlFacet.setPartyBConfig(signer.address, { isActive: true, lossCoverage: 0, oracleId: 1 })
		await context.controlFacet.setPartyBSupportedSymbolTypes(signer.address, [0], [true])
	}
	for (const token of [context.collateral, context.collateralNL]) await context.controlFacet.whiteListCollateral(await token.getAddress())
	await context.controlFacet.addSymbol(
		"NATIVE_PUT",
		OptionType.PUT,
		1,
		await context.collateral.getAddress(),
		{ openFee: e(0.01), closeFee: e(0.02) },
		0,
	)
	await context.controlFacet.addSymbol(
		"NATIVE_CALL",
		OptionType.CALL,
		1,
		await context.collateral.getAddress(),
		{ openFee: e(0.01), closeFee: e(0.02) },
		0,
	)
	await context.controlFacet.setAffiliateStatus(context.signers.affiliate1.address, true)
	await context.controlFacet.setAffiliateFees(
		context.signers.affiliate1.address,
		[1, 2],
		[
			{ openFee: e(0.01), closeFee: e(0.02) },
			{ openFee: e(0.01), closeFee: e(0.02) },
		],
	)
	await context.controlFacet.setSignatureVerifier(await context.signatureVerifier.getAddress())
	return context
}
