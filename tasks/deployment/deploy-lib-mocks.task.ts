import { task } from "hardhat/config"
import { deployLibMocks } from "./deploy-lib"

task("deploy:mocks", "Deploys the Mock contract").setAction(async (_, { ethers }) => deployLibMocks(ethers))
