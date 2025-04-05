import { readFileSync } from "fs"
import { task } from "hardhat/config"
import { ControlFacet, ViewFacet } from "../../types"

task("setup:deployment", "Setup Deployed Facets").setAction(async ({}, { ethers, run }) => {
	console.info("Running deploy:oracle")

	const configFile = "config/setup.json"
	const symmioAddress = ""

	if (!configFile || !symmioAddress) {
		console.error("Error: Configuration file or Symmio contract address is inaccessible.")
		process.exit(1)
	}

	const config = JSON.parse(readFileSync(configFile, "utf8"))

	const controlFacetFactory = await ethers.getContractFactory("ControlFacet")
	const controlFacet: ControlFacet = controlFacetFactory.attach(symmioAddress) as any

	const owner = (await ethers.getSigners())[0]

	const viewFacetFactory = await ethers.getContractFactory("ViewFacet")
	const viewFacet: ViewFacet = viewFacetFactory.attach(symmioAddress) as any

	if (config.admin) {
		await controlFacet.connect(owner).setAdmin(config.admin)
		console.log(`Admin configuration completed. Assigned admin: ${config.admin}`)
	}

	if (config.grantRoles) {
		for (const { roleUser, role } of config.grantRoles) {
			if (roleUser && role) {
				await controlFacet.connect(owner).grantRole(roleUser, role)
				console.log(`Role granted successfully. User: ${roleUser}, Role: ${role}`)
			}
		}
	}

	if (config.revokeRoles) {
		for (const { roleUser, role } of config.revokeRoles) {
			if (roleUser && role) {
				await controlFacet.connect(owner).revokeRole(roleUser, role)
				console.log(`Role revoked successfully. User: ${roleUser}, Role: ${role}`)
			}
		}
	}

	if (config.affiliates) {
		for (const { affiliate, feeCollector } of config.affiliates) {
			if (affiliate) {
				if ((await viewFacet.connect(owner).affiliateStatus(affiliate)) == false) {
					await controlFacet.connect(owner).setAffiliateStatus(affiliate, true)
					console.log(`Affiliate registered successfully. Address: ${affiliate}`)
				}
			}
		}
	}

	if (config.defaultFeeCollector) {
		await controlFacet.connect(owner).setDefaultFeeCollector(config.defaultFeeCollector)
		console.log(`Default fee collector set. Address: ${config.defaultFeeCollector}`)
	}

    console.log("Initialization process completed successfully.")
})
