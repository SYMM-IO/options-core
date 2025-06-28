import { TestModeEnum } from "../common/test-mode.enum"
import { name, version } from "../package.json"
import { shouldBehaveLikeAccountFacet } from "./account-facet.behavior"
import { shouldBehaveLikeForceActionFacet } from "./force-action.behavior"
import { shouldBehaveLikeInstantActionOpenFacet } from "./instant-action-open.behavior"
import { shouldBehaveLikeLibCloseIntent } from "./lib-closeIntent.behavior"
import { shouldBehaveLikePartyACloseFacet } from "./partyA-close-facet.behavior"
import { shouldBehaveLikePartyAOpenFacet } from "./partyA-open-facet.behavior"
import { shouldBehaveLikePartyBCloseFacet } from "./partyB-close-facet.behavior"
import { shouldBehaveLikePartyBOpenFacet } from "./partyB-open-facet.behavior"
import { shouldBehaveLikeSettlementFacet } from "./trade-settlement"
import { shouldBehaveLikeInstantActionCloseFacet } from "./instant-action-close.behavior"
import { shouldBehaveLikeInstantActionsPartyBOpenFacet } from "./instant-actions-partyb-open-facet.behavior"
import { shouldBehaveLikeBridgeFacet } from "./bridge-facet.behavior"

describe(`${name}-v${version}`, () => {
	if (process.env.TEST_MODE === TestModeEnum.UNIT_TEST) {
		// describe("Facets_Accounts", async function () {
		// 	shouldBehaveLikeAccountFacet()
		// })

		// describe("Facets_PartyAOpenFacet", async function () {
		// 	shouldBehaveLikePartyAOpenFacet()
		// })

		// describe("Facets_PartyBOpenFacet", async function () {
		// 	shouldBehaveLikePartyBOpenFacet()
		// })

		describe("Facets_PartyACloseFacet", async function () {
			shouldBehaveLikePartyACloseFacet()
		})

		describe("Libraries_LibCloseIntent", async function () {
			shouldBehaveLikeLibCloseIntent()
		})

		// describe("Facets_InstantActionOpenFacet", async function () {
		// 	shouldBehaveLikeInstantActionOpenFacet()
		// })

		// describe("Facets_InstantActionCloseFacet", async function () {
		// 	shouldBehaveLikeInstantActionCloseFacet()
		// })

		// describe("shouldBehaveLikeInstantActionsPartyBOpenFacet", async function () {
		// 	shouldBehaveLikeInstantActionsPartyBOpenFacet()
		// })

		describe("Facets_PartyBCloseFacet", async function () {
			shouldBehaveLikePartyBCloseFacet()
		})

		describe("Facets_Settlement", async function () {
			shouldBehaveLikeSettlementFacet()
		})

		describe("Facets_ForceActions", async function () {
			shouldBehaveLikeForceActionFacet()
		})

		describe("Facet_BridgeFacet", async function () {
			shouldBehaveLikeBridgeFacet()
		})
	} else {
		throw new Error(`Invalid TEST_MODE property. Should be one of: ${Object.keys(TestModeEnum).join(", ")}`)
	}
})
