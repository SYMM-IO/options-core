import { TestModeEnum } from "../common/test-mode.enum"
import { name, version } from "../package.json"
import { shouldBehaveLikeAccountFacet } from "./account-facet.behavior"
import { shouldBehaveLikePartyAFacet } from "./partyA-facet.behavior"
import { shouldBehaveLikePartyBFacet } from "./partyB-facet.behavior"

describe(`${name}-v${version}`, () => {
	if (process.env.TEST_MODE === TestModeEnum.UNIT_TEST) {
		describe("Facets_Accounts", async function () {
			shouldBehaveLikeAccountFacet()
		})

		describe("Facets_PartyA", async function () {
			shouldBehaveLikePartyAFacet()
		})

		describe("Facets_PartyB", async function () {
			shouldBehaveLikePartyBFacet()
		})
	} else {
		throw new Error(`Invalid TEST_MODE property. Should be one of: ${Object.keys(TestModeEnum).join(", ")}`)
	}
})
