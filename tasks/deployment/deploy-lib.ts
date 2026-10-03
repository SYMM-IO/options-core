import type { HardhatEthers } from "@nomicfoundation/hardhat-ethers/types"
import type { HardhatUpgrades } from "@openzeppelin/hardhat-upgrades"

import { DEPLOYMENT_LOG_FILE, FacetNames } from "../../common/constants.js"
import type {
	Diamond,
	FakeOracle,
	FakeStablecoin,
	InstantLayer,
	MockHookHandler,
	MultiAccount,
	SignatureVerifier,
	SymmioPartyB,
} from "../../types/index.js"
import { FacetCutAction, getSelectors } from "../utils/diamond-cut.js"
import { writeData } from "../utils/fs.js"

export type Ethers = HardhatEthers
export type Upgrades = HardhatUpgrades

export async function deployDiamond(ethers: Ethers, logData: boolean): Promise<Diamond> {
	const [owner] = await ethers.getSigners()

	const diamondCutFacet = await (await ethers.getContractFactory("DiamondCutFacet")).deploy()
	await diamondCutFacet.waitForDeployment()
	console.log("DiamondCutFacet deployed:", await diamondCutFacet.getAddress())

	const diamond = await (await ethers.getContractFactory("Diamond")).deploy(owner.address, await diamondCutFacet.getAddress())
	await diamond.waitForDeployment()
	console.log("Diamond deployed:", await diamond.getAddress())

	const diamondInit = await (await ethers.getContractFactory("DiamondInit")).deploy()
	await diamondInit.waitForDeployment()
	console.log("DiamondInit deployed:", await diamondInit.getAddress())

	const cut: Array<{ facetAddress: string; action: FacetCutAction; functionSelectors: string[] }> = []
	const deployedFacets: Array<{ name: string; address: string }> = []
	for (const facetName of FacetNames) {
		const facet = await (await ethers.getContractFactory(facetName)).deploy()
		await facet.waitForDeployment()
		console.log(`${facetName} deployed: ${await facet.getAddress()}`)
		cut.push({
			facetAddress: await facet.getAddress(),
			action: FacetCutAction.Add,
			functionSelectors: getSelectors(ethers, facet as any).selectors,
		})
		deployedFacets.push({ name: facetName, address: await facet.getAddress() })
	}

	const diamondCut = await ethers.getContractAt("IDiamondCut", await diamond.getAddress())
	const tx = await diamondCut.diamondCut(cut, await diamondInit.getAddress(), diamondInit.interface.encodeFunctionData("init"))
	const receipt = await tx.wait()
	if (!receipt?.status) throw Error(`Diamond upgrade failed: ${tx.hash}`)
	console.log("Completed Diamond Cut")

	if (logData) {
		writeData(DEPLOYMENT_LOG_FILE, [
			{ name: "DiamondCut", address: await diamondCutFacet.getAddress(), constructorArguments: [] },
			{ name: "Diamond", address: await diamond.getAddress(), constructorArguments: [owner.address, await diamondCutFacet.getAddress()] },
			...deployedFacets.map(facet => ({ name: facet.name, address: facet.address, constructorArguments: [] })),
		])
		console.log("Deployed addresses written to json file")
	}

	return diamond
}

export async function deployLibMocks(ethers: Ethers): Promise<Map<string, string>> {
	const mocks = new Map<string, string>()
	for (const name of ["CloseIntentOpsMock"]) {
		const mock = await (await ethers.getContractFactory(name)).deploy()
		await mock.waitForDeployment()
		mocks.set(name, await mock.getAddress())
		console.log(`${name} deployed: ${await mock.getAddress()}`)
	}
	return mocks
}

export async function deploySignatureVerifier(ethers: Ethers): Promise<SignatureVerifier> {
	const verifier = await (await ethers.getContractFactory("SignatureVerifier")).deploy()
	await verifier.waitForDeployment()
	return verifier
}

export async function deployFakeOracle(ethers: Ethers): Promise<FakeOracle> {
	const oracle = await (await ethers.getContractFactory("FakeOracle")).deploy()
	await oracle.waitForDeployment()
	console.log("FakeOracle deployed:", await oracle.getAddress())
	return oracle
}

export async function deployHookHandler(ethers: Ethers): Promise<MockHookHandler> {
	const hookHandler = await (await ethers.getContractFactory("MockHookHandler")).deploy()
	await hookHandler.waitForDeployment()
	console.log("HookHandler deployed:", await hookHandler.getAddress())
	return hookHandler
}

export async function deployStablecoin(ethers: Ethers, name: string, symbol: string): Promise<FakeStablecoin> {
	const stablecoin = await (await ethers.getContractFactory("FakeStablecoin")).deploy(name, symbol)
	await stablecoin.waitForDeployment()
	console.log("FakeStablecoin deployed:", await stablecoin.getAddress())
	return stablecoin
}

export async function deployInstantLayer(ethers: Ethers, symmio: string, admin: string): Promise<InstantLayer> {
	const instantLayer = await (await ethers.getContractFactory("InstantLayer")).deploy(symmio, admin)
	await instantLayer.waitForDeployment()
	console.log("InstantLayer deployed:", await instantLayer.getAddress())
	return instantLayer
}

export async function deployMultiAccount(ethers: Ethers, upgrades: Upgrades, symmio: string, admin: string, tradeNft: string): Promise<MultiAccount> {
	const partyA = await ethers.getContractFactory("SymmioPartyA")
	const factory = await ethers.getContractFactory("MultiAccount")
	const proxy = await upgrades.deployProxy(factory, [admin, symmio, partyA.bytecode, tradeNft], { initializer: "initialize" })
	await proxy.waitForDeployment()
	const address = await proxy.getAddress()
	console.log("MultiAccount deployed to", {
		proxy: address,
		admin: await upgrades.erc1967.getAdminAddress(address),
		implementation: await upgrades.erc1967.getImplementationAddress(address),
	})
	return ethers.getContractAt("MultiAccount", address)
}

export async function deploySymmioPartyB(ethers: Ethers, upgrades: Upgrades, symmio: string, admin: string): Promise<SymmioPartyB> {
	const factory = await ethers.getContractFactory("SymmioPartyB")
	const proxy = await upgrades.deployProxy(factory, [admin, symmio], { initializer: "initialize" })
	await proxy.waitForDeployment()
	const address = await proxy.getAddress()
	console.log("SymmioPartyB deployed to", {
		proxy: address,
		admin: await upgrades.erc1967.getAdminAddress(address),
		implementation: await upgrades.erc1967.getImplementationAddress(address),
	})
	return ethers.getContractAt("SymmioPartyB", address)
}
