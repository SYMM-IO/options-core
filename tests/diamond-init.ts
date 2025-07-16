import { e } from "../utils/e"
import { RunContext } from "./run-context"

export async function diamondInitialize(context: RunContext): Promise<RunContext> {
	await context.controlFacet.connect(context.signers.admin).unpauseGlobal()

	await context.controlFacet.setDeactiveInstantActionModeCooldown(120)
	await context.controlFacet.setUnbindingCooldown(120)
	await context.controlFacet.setMaxConnectedCounterParties(10)
	await context.controlFacet.setMaxTradePerPartyA(10)
	await context.controlFacet.setBalanceLimitPerUser(context.collateral, e(1000000))
	await context.controlFacet.setBalanceLimitPerUser(context.collateralNL, e(1000000))
	await context.controlFacet.setDefaultFeeCollector(context.signers.feeCollector)
	await context.controlFacet.setMaxCloseOrdersLength(10)
	await context.controlFacet.setAffiliateFeesCollector(context.signers.affiliate1, context.signers.feeCollector)
	await context.controlFacet.setDefaultReleaseInterval(12)

	return context
}
