import hre from "hardhat"
import verifyDeployment from "../tasks/verify/verify.js"

// Verify the recorded Diamond deployment, including each facet's linked library metadata.
verifyDeployment({}, hre).catch(error => {
	console.error(error)
	process.exitCode = 1
})
