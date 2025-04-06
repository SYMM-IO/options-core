import { ethers } from "hardhat"

import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import { AccountFacet, ControlFacet, DiamondCutFacet, DiamondLoupeFacet, FakeOracle, FakeStablecoin, ForceActionsFacet, PartyACloseFacet, PartyAFacet, PartyAOpenFacet, PartyBCloseFacet, PartyBFacet, PartyBOpenFacet, TradeSettlementFacet, ViewFacet } from "../types"

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
	signers!: {
		admin: SignerWithAddress
		partyA1: SignerWithAddress
		partyA2: SignerWithAddress
		feeCollector: SignerWithAddress
		partyB1: SignerWithAddress
		partyB2: SignerWithAddress
		oracle1: SignerWithAddress
		affiliate1: SignerWithAddress
		others: SignerWithAddress[]
	}
	diamond!: string
	collateral!: FakeStablecoin
	oracle!:FakeOracle
}

export async function createRunContext(diamond: string, collateral: string, oracle: string): Promise<RunContext> {
	let context = new RunContext()

	const signers: SignerWithAddress[] = await ethers.getSigners()
	context.signers = {
		admin: signers[0],
		partyA1: signers[1],
		partyA2: signers[2],
		feeCollector: signers[3],
		partyB1: signers[4],
		partyB2: signers[5],
		oracle1:signers[6],
		affiliate1:signers[7],
		others: [signers[8], signers[9]],
	}

	context.diamond = diamond
	context.collateral = await ethers.getContractAt("FakeStablecoin", collateral)
	context.oracle = await ethers.getContractAt("FakeOracle", oracle)
	context.accountFacet = await ethers.getContractAt("AccountFacet", diamond)
	context.diamondCutFacet = await ethers.getContractAt("DiamondCutFacet", diamond)
	context.diamondLoupeFacet = await ethers.getContractAt("DiamondLoupeFacet", diamond)
	context.viewFacet = await ethers.getContractAt("ViewFacet", diamond)
	context.controlFacet = await ethers.getContractAt("ControlFacet", diamond)
	context.forceActionsFacet = await ethers.getContractAt("ForceActionsFacet", diamond)

	context.partyAOpenFacet = await ethers.getContractAt("PartyAOpenFacet", diamond)
	context.partyACloseFacet = await ethers.getContractAt("PartyACloseFacet", diamond)

	context.partyBCloseFacet = await ethers.getContractAt("PartyBCloseFacet", diamond)
	context.partyBOpenFacet = await ethers.getContractAt("PartyBOpenFacet", diamond)

	context.tradeSettlementFacet = await ethers.getContractAt("TradeSettlementFacet", diamond)

	return context
}