import { task } from "hardhat/config"
import { deployStablecoin } from "./deploy-lib"

task("deploy:stablecoin", "Deploys the FakeStablecoin")
	.addParam("name", "The token's name")
	.addParam("symbol", "The token's symbol")
	.setAction(async ({ name, symbol }, { ethers }) => deployStablecoin(ethers, name, symbol))
