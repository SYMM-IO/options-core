import { task } from "hardhat/config"
import { ArgumentType } from "hardhat/types/arguments"

// Generic over the name so each option keeps its literal key in the task's argument type.
function option<NameT extends string>(name: NameT, description: string, defaultValue = "") {
	return { name, description, type: ArgumentType.STRING as const, defaultValue }
}

export const tasks = [
	task("deploy:diamond", "Deploys the Diamond contract")
		.addFlag({ name: "skipLog", description: "Do not write the deployed addresses to tasks/data/deployed.json" })
		.setAction(() => import("./deployment/diamond-deploy.task.js"))
		.build(),
	task("deploy:mocks", "Deploys the Mock contract").setAction(() => import("./deployment/deploy-lib-mocks.task.js")).build(),
	task("deploy:SignatureVerifier", "Deploys the SignatureVerifier contract")
		.setAction(() => import("./deployment/deploy-signature-verifier.task.js"))
		.build(),
	task("deploy:oracle", "Deploys the FakeOracle").setAction(() => import("./deployment/oracle.task.js")).build(),
	task("deploy:hookHandler", "Deploys the Hook Handler").setAction(() => import("./deployment/hook-handler.task.js")).build(),
	task("deploy:stablecoin", "Deploys the FakeStablecoin")
		.addOption(option("name", "The token's name"))
		.addOption(option("symbol", "The token's symbol"))
		.setAction(() => import("./deployment/stable-coin.task.js"))
		.build(),
	task("deploy:InstantLayer", "Deploys the InstantLayer contract")
		.addOption(option("symmioaddress", "The address of the Symmio contract"))
		.addOption(option("admin", "The admin address"))
		.setAction(() => import("./deployment/instantLayer.js"))
		.build(),
	task("deploy:multiAccount", "Deploys the MultiAccount")
		.addOption(option("symmioaddress", "The address of the Symmio contract"))
		.addOption(option("admin", "The admin address"))
		.addOption(option("tradenftaddress", "The trade NFT address"))
		.setAction(() => import("./deployment/multiAccount.js"))
		.build(),
	task("deploy:symmioPartyB", "Deploys the SymmioPartyB")
		.addOption(option("symmioaddress", "The address of the Symmio contract"))
		.addOption(option("admin", "The admin address"))
		.setAction(() => import("./deployment/partyB.js"))
		.build(),
	task("deploy:deploy", "Deploy and verify the diamond and its facets").setAction(() => import("./deployment/deploy.task.js")).build(),
	task("verify:deployment", "Verifies the deployed contracts").setAction(() => import("./verify/verify.js")).build(),
	task("send-open-intent", "Calls sendOpenIntent on the contract")
		.addOption(option("symbolid", "ID of the symbol"))
		.addOption(option("price", "Price of the trade"))
		.addOption(option("quantity", "Quantity of the trade"))
		.addOption(option("strikeprice", "Strike price"))
		.addOption(option("expiration", "Expiration timestamp"))
		.addOption(option("mm", "Minimum margin"))
		.addOption(option("tradeside", "Trade side (0=Buy, 1=Sell)"))
		.addOption(option("margintype", "Margin type (0=Isolated, 1=Cross)"))
		.addOption(option("exercisefeerate", "Basis points of exercise fee (e.g. 500 = 5%)"))
		.addOption(option("exercisefeecap", "Cap of exercise fee"))
		.addOption(option("solverfeeopen", "Solver open fee", "0"))
		.addOption(option("solverfeeclose", "Solver close fee", "0"))
		.addOption(option("deadline", "Deadline timestamp"))
		.addOption(option("feetoken", "Address of the token used to pay fees"))
		.addOption(option("affiliate", "Address of the affiliate"))
		.addOption(option("userdata", "User-specific data in hex"))
		.addOption(option("whitelist", "Comma-separated partyB addresses"))
		.setAction(() => import("./helper/send_open_intent.js"))
		.build(),
	task("lock-open-intent", "Calls lockOpenIntent on the contract")
		.addOption(option("intentid", "ID of the intent"))
		.setAction(() => import("./helper/lock_open_intent.js"))
		.build(),
	task("fill-open-intent", "Calls fillOpenIntent on the contract")
		.addOption(option("intentid", "ID of the intent"))
		.addOption(option("quantity", "Quantity to fill"))
		.addOption(option("price", "Fill price"))
		.setAction(() => import("./helper/fill_open_intent.js"))
		.build(),
	task("send-close-intent", "Calls sendCloseIntent on the contract")
		.addOption(option("tradeid", "ID of the trade"))
		.addOption(option("quantity", "Quantity to close"))
		.addOption(option("price", "Close price"))
		.addOption(option("deadline", "Deadline timestamp"))
		.setAction(() => import("./helper/send_close_intent.js"))
		.build(),
	task("fill-close-intent", "Calls fillCloseIntent on the contract")
		.addOption(option("intentid", "ID of the close intent"))
		.addOption(option("quantity", "Quantity to fill"))
		.addOption(option("price", "Fill price"))
		.setAction(() => import("./helper/fill_close_intent.js"))
		.build(),
]
