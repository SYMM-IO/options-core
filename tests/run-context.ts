import { ethers } from "hardhat"

import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import {
	AccountFacet,
	BridgeFacet,
	ClearingHouseFacet,
	CloseIntentOpsMock,
	ControlFacet,
	DiamondCutFacet,
	DiamondLoupeFacet,
	FakeOracle,
	FakeStablecoin,
	ForceActionsFacet,
	InstantActionsCloseFacet,
	InstantActionsOpenFacet,
	InstantActionsPartyBOpenFacet,
	PartyACloseFacet,
	PartyAOpenFacet,
	PartyBCloseFacet,
	PartyBOpenFacet,
	SignatureVerifier,
	TradeSettlementFacet,
	ViewFacet,
} from "../types"

export class RunContext {
	accountFacet!: AccountFacet
	diamondCutFacet!: DiamondCutFacet
	diamondLoupeFacet!: DiamondLoupeFacet
	partyAOpenFacet!: PartyAOpenFacet
	partyACloseFacet!: PartyACloseFacet
	partyBCloseFacet!: PartyBCloseFacet
	partyBOpenFacet!: PartyBOpenFacet
	viewFacet!: ViewFacet
	tradeSettlementFacet!: TradeSettlementFacet
	controlFacet!: ControlFacet
	forceActionsFacet!: ForceActionsFacet
	instantActionOpenFacet!: InstantActionsOpenFacet
	instantActionCloseFacet!: InstantActionsCloseFacet
	InstantActionsPartyBOpenFacet!: InstantActionsPartyBOpenFacet
	clearingHouse!: ClearingHouseFacet
	bridgeFacet!: BridgeFacet

	signers!: {
		admin: SignerWithAddress
		partyA1: SignerWithAddress
		partyA2: SignerWithAddress
		feeCollector: SignerWithAddress
		partyB1: SignerWithAddress
		partyB2: SignerWithAddress
		oracle1: SignerWithAddress
		affiliate1: SignerWithAddress
		bridge1:SignerWithAddress,
		bridge2:SignerWithAddress,
		others: SignerWithAddress[]
	}
	collateral!: FakeStablecoin
	collateralNL!: FakeStablecoin
	oracle!: FakeOracle
	mocks!: {
		libCloseIntentMock: CloseIntentOpsMock
	}
	signatureVerifier!: SignatureVerifier
	common!: {
		chainId: number
		diamondAddress: string
	}
}

export async function createRunContext(
	diamond: string,
	collateral: string[],
	oracle: string,
	signatureVerifier: string,
	mocks?: Map<string, string>,
): Promise<RunContext> {
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
		others: [signers[10], signers[11]],
	}

	context.collateral = await ethers.getContractAt("FakeStablecoin", collateral[0])
	context.collateralNL = await ethers.getContractAt("FakeStablecoin", collateral[1])

	context.oracle = await ethers.getContractAt("FakeOracle", oracle)
	context.accountFacet = await ethers.getContractAt("AccountFacet", diamond)
	context.diamondCutFacet = await ethers.getContractAt("DiamondCutFacet", diamond)
	context.diamondLoupeFacet = await ethers.getContractAt("DiamondLoupeFacet", diamond)
	context.viewFacet = await ethers.getContractAt("ViewFacet", diamond)
	context.controlFacet = await ethers.getContractAt("ControlFacet", diamond)
	context.forceActionsFacet = await ethers.getContractAt("ForceActionsFacet", diamond)
	context.instantActionCloseFacet = await ethers.getContractAt("InstantActionsCloseFacet", diamond)
	context.instantActionOpenFacet = await ethers.getContractAt("InstantActionsOpenFacet", diamond)
	context.InstantActionsPartyBOpenFacet = await ethers.getContractAt("InstantActionsPartyBOpenFacet", diamond)
	context.signatureVerifier = await ethers.getContractAt("SignatureVerifier", signatureVerifier)
	context.clearingHouse = await ethers.getContractAt("ClearingHouseFacet", diamond)

	context.partyAOpenFacet = await ethers.getContractAt("PartyAOpenFacet", diamond)
	context.partyACloseFacet = await ethers.getContractAt("PartyACloseFacet", diamond)

	context.partyBCloseFacet = await ethers.getContractAt("PartyBCloseFacet", diamond)
	context.partyBOpenFacet = await ethers.getContractAt("PartyBOpenFacet", diamond)
	context.bridgeFacet = await ethers.getContractAt("BridgeFacet", diamond)

	context.tradeSettlementFacet = await ethers.getContractAt("TradeSettlementFacet", diamond)

	if (mocks) {
		context.mocks = {
			libCloseIntentMock: await ethers.getContractAt("CloseIntentOpsMock", mocks.get("CloseIntentOpsMock")!),
		}
	}

	context.common = {
		chainId: Number((await ethers.provider.getNetwork()).chainId),
		diamondAddress: diamond,
	}

	return context
}
