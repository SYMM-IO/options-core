import { task } from "hardhat/config"
import { deploySymmioPartyB } from "./deploy-lib"

task("deploy:symmioPartyB", "Deploys the SymmioPartyB")
	.addParam("symmioaddress", "The address of the Symmio contract")
	.addParam("admin", "The admin address")
	.setAction(async ({ symmioaddress, admin }, { ethers, upgrades }) => deploySymmioPartyB(ethers, upgrades, symmioaddress, admin))
