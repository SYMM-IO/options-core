import { TestModeEnum } from "../common/test-mode.enum"
import { name, version } from "../package.json"
import { shouldBehaveLikeAccountFacet } from "./account-facet.behavior"

describe(`${name}-v${version}`, () => {
	if (process.env.TEST_MODE === TestModeEnum.UNIT_TEST) {
		describe("Facets_Accounts", async function () {
			shouldBehaveLikeAccountFacet()
		})
	} else {
		throw new Error(`Invalid TEST_MODE property. Should be one of: ${Object.keys(TestModeEnum).join(", ")}`)
	}
})
