import { task } from "hardhat/config"
import { deployInstantLayer } from "./deploy-lib"

task("deploy:InstantLayer", "Deploys the InstantLayer contract")
	.addParam("symmioaddress", "The address of the Symmio contract")
	.addParam("admin", "The admin address")
	.setAction(async ({ symmioaddress, admin }, { ethers }) => deployInstantLayer(ethers, symmioaddress, admin))
