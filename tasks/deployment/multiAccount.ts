import { task } from "hardhat/config"
import { deployMultiAccount } from "./deploy-lib"

task("deploy:multiAccount", "Deploys the MultiAccount")
	.addParam("symmioaddress", "The address of the Symmio contract")
	.addParam("admin", "The admin address")
	.addParam("tradenftaddress", "The trade NFT address")
	.setAction(async ({ symmioaddress, admin, tradenftaddress }, { ethers, upgrades }) =>
		deployMultiAccount(ethers, upgrades, symmioaddress, admin, tradenftaddress),
	)
