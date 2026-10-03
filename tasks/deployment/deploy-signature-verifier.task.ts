import { task } from "hardhat/config"
import { deploySignatureVerifier } from "./deploy-lib"

task("deploy:SignatureVerifier", "Deploys the SignatureVerifier contract").setAction(async (_, { ethers }) => deploySignatureVerifier(ethers))
