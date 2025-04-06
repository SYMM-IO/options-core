import { task } from "hardhat/config"

task("deploy:deploy", "Deploy, verify and setup facets").setAction(async (_, { run }) => {
	await run("deploy:diamond", true)
	
	await run("verify:deployment")
	await run("setup:deployment")
})
