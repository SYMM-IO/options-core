import { expect } from "chai"
import hre from "hardhat"
import { ethers } from "../connection.js"

export function shouldShareOneChainWithTasks(): void {
	it("runs Hardhat tasks on the same chain as the tests", async function () {
		// Reading name() catches the deterministic-address trap: on a different chain, this address is
		// empty or holds some other contract, so the call either fails or returns another name.
		const token = (await hre.tasks.getTask("deploy:stablecoin").run({ name: "ChainProbe", symbol: "PRB" })) as {
			getAddress(): Promise<string>
		}
		const probe = await ethers.getContractAt("FakeStablecoin", await token.getAddress())
		expect(await probe.name()).to.equal("ChainProbe")
	})
}
