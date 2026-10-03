import { task, types } from "hardhat/config"
import { deployDiamond } from "./deploy-lib"

task("deploy:diamond", "Deploys the Diamond contract")
	.addParam("logData", "Write the deployed addresses to a data file", true, types.boolean)
	.setAction(async ({ logData }, { ethers }) => deployDiamond(ethers, logData))
