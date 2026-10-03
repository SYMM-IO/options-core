import { task } from "hardhat/config"
import { deployFakeOracle } from "./deploy-lib"

task("deploy:oracle", "Deploys the FakeOracle").setAction(async (_, { ethers }) => deployFakeOracle(ethers))
