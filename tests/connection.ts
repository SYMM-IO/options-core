import { upgrades } from "@openzeppelin/hardhat-upgrades"
import hre, { network } from "hardhat"

// The one connection every test file, fixture and helper shares. getOrCreate() (not create()) is what lets
// tasks invoked from tests via hre.tasks.getTask(...).run() land on this same chain.
export const connection = await network.getOrCreate()
export const { ethers, networkHelpers } = connection
export const upgradesApi = await upgrades(hre, connection)
