import { task } from "hardhat/config"
import { deployHookHandler } from "./deploy-lib"

task("deploy:hookHandler", "Deploys the Hook Handler").setAction(async (_, { ethers }) => deployHookHandler(ethers))
