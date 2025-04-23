import { task } from "hardhat/config"
import { Diamond } from "../../types"

task("deploy:deploy", "Deploy, verify and setup facets").setAction(async (_, { run }) => {
	const diamond = await run("deploy:diamond", true) as Diamond
	await run("verify:deployment")
	await run("setup:deployment", { optionAddress: await diamond.getAddress() })
})
