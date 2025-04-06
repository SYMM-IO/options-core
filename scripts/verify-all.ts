import { run } from "hardhat"

async function main() {
	let facets: { [x: string]: string } = {
		AccountFacet: "",
		DiamondLoupeFacet: "",
		ForceActionsFacet: "",
		ViewFacet: "",
		ControlFacet: "",
		BridgeFacet: "",
		ClearingHouseFacet: "",
		InstantActionsOpenFacet: "",
		InstantActionsCloseFacet: "",
		InterdealerFacet: "",
		PartyAOpenFacet: "",
		PartyACloseFacet: "",
		PartyBCloseFacet: "",
		PartyBOpenFacet: "",
		TradeSettlementFacet: "",
	}
	for (const facet in facets) {
		if (!facets.hasOwnProperty(facet)) continue
		const facetAddr = facets[facet]
		console.log(`Verifying ${facet} with impl in ${facetAddr}`)
		await run("verify:verify", {
			address: facetAddr,
			constructorArguments: [],
		})
	}
}

main().catch(error => {
	console.error(error)
	process.exitCode = 1
})
