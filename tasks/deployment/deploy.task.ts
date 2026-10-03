import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"

export default async function (_: Record<string, unknown>, hre: HardhatRuntimeEnvironment) {
	await hre.tasks.getTask("deploy:diamond").run({})
	await hre.tasks.getTask("verify:deployment").run({})
}
