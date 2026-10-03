import { ethers, upgrades } from "hardhat"

import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import {
	AccountFacet,
	ClearingHouseFacet,
	CloseIntentOpsMock,
	ControlFacet,
	CounterPartyRelationsFacet,
	DiamondCutFacet,
	DiamondLoupeFacet,
	FakeOracle,
	FakeStablecoin,
	ForceActionsFacet,
	InstantLayer,
	MockHookHandler,
	MultiAccount,
	PartyACloseFacet,
	PartyAOpenFacet,
	PartyBCloseFacet,
	PartyBOpenFacet,
	SignatureVerifier,
	SymmioPartyB,
	TradeFacet,
	ViewFacet,
} from "../types"
import { ZeroAddress } from "ethers"
import {
	deployFakeOracle,
	deployHookHandler,
	deployInstantLayer,
	deployLibMocks,
	deployMultiAccount,
	deploySignatureVerifier,
	deployStablecoin,
	deploySymmioPartyB,
} from "../tasks/deployment/deploy-lib"

export class RunContext {
	accountFacet!: AccountFacet
	diamondCutFacet!: DiamondCutFacet
	diamondLoupeFacet!: DiamondLoupeFacet
	partyAOpenFacet!: PartyAOpenFacet
	partyACloseFacet!: PartyACloseFacet
	partyBCloseFacet!: PartyBCloseFacet
	partyBOpenFacet!: PartyBOpenFacet
	viewFacet!: ViewFacet
	controlFacet!: ControlFacet
	forceActionsFacet!: ForceActionsFacet
	tradeFacet!: TradeFacet
	clearingHouse!: ClearingHouseFacet
	counterPartyRelation!: CounterPartyRelationsFacet
	instantLayer!: InstantLayer
	multiAccount!: MultiAccount
	symmioPartyB!: SymmioPartyB

	signers!: {
		admin: SignerWithAddress
		partyA1: SignerWithAddress
		partyA2: SignerWithAddress
		feeCollector: SignerWithAddress
		partyB1: SignerWithAddress
		partyB2: SignerWithAddress
		oracle1: SignerWithAddress
		affiliate1: SignerWithAddress
		bridge1: SignerWithAddress
		bridge2: SignerWithAddress
		clearingHouse: SignerWithAddress
		others: SignerWithAddress[]
	}
	collateral!: FakeStablecoin
	collateralNL!: FakeStablecoin
	oracle!: FakeOracle
	hookHandler!: MockHookHandler
	mocks!: {
		libCloseIntentMock: CloseIntentOpsMock
	}
	signatureVerifier!: SignatureVerifier
	common!: {
		chainId: number
		diamondAddress: string
	}
}

export async function createRunContext(diamond: string): Promise<RunContext> {
	let context = new RunContext()

	const signers: SignerWithAddress[] = await ethers.getSigners()
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

	const mocks = await deployLibMocks(ethers)
	const verifier = await deploySignatureVerifier(ethers)
	const oracle = await deployFakeOracle(ethers)
	const hookHandler = await deployHookHandler(ethers)

	const stableCoin = await deployStablecoin(ethers, "MyFakeStablecoin", "FUSD")
	const stableCoinNL = await deployStablecoin(ethers, "StablecoinNotListed", "NLUSD")

	context.collateral = stableCoin
	context.collateralNL = stableCoinNL
	context.hookHandler = hookHandler
	context.oracle = oracle
	context.signatureVerifier = verifier
	context.accountFacet = await ethers.getContractAt("AccountFacet", diamond)
	context.diamondCutFacet = await ethers.getContractAt("DiamondCutFacet", diamond)
	context.diamondLoupeFacet = await ethers.getContractAt("DiamondLoupeFacet", diamond)
	context.viewFacet = await ethers.getContractAt("ViewFacet", diamond)
	context.controlFacet = await ethers.getContractAt("ControlFacet", diamond)
	context.forceActionsFacet = await ethers.getContractAt("ForceActionsFacet", diamond)
	context.clearingHouse = await ethers.getContractAt("ClearingHouseFacet", diamond)

	context.partyAOpenFacet = await ethers.getContractAt("PartyAOpenFacet", diamond)
	context.partyACloseFacet = await ethers.getContractAt("PartyACloseFacet", diamond)

	context.partyBCloseFacet = await ethers.getContractAt("PartyBCloseFacet", diamond)
	context.partyBOpenFacet = await ethers.getContractAt("PartyBOpenFacet", diamond)
	context.counterPartyRelation = await ethers.getContractAt("CounterPartyRelationsFacet", diamond)
	context.tradeFacet = await ethers.getContractAt("TradeFacet", diamond)
	if (mocks) {
		context.mocks = {
			libCloseIntentMock: await ethers.getContractAt("CloseIntentOpsMock", mocks.get("CloseIntentOpsMock")!),
		}
	}

	context.common = {
		chainId: Number((await ethers.provider.getNetwork()).chainId),
		diamondAddress: diamond,
	}

	const admin = context.signers.admin.address
	const instantLayer = await deployInstantLayer(ethers, context.common.diamondAddress, admin)
	const multiAccount = await deployMultiAccount(ethers, upgrades, context.common.diamondAddress, admin, ZeroAddress)
	const symmioPartyB = await deploySymmioPartyB(ethers, upgrades, context.common.diamondAddress, admin)
	context.multiAccount = multiAccount
	context.instantLayer = instantLayer
	context.symmioPartyB = symmioPartyB

	return context
}
