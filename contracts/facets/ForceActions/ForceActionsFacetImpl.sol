// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibCloseIntentOps } from "../../libraries/LibCloseIntent.sol";
import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { AppStorage } from "../../storages/AppStorage.sol";
import { OpenIntent, CloseIntent, IntentStorage, IntentStatus } from "../../storages/IntentStorage.sol";

library ForceActionsFacetImpl {
	using LibOpenIntentOps for OpenIntent;
	using LibCloseIntentOps for CloseIntent;

	function forceCancelOpenIntent(uint256 intentId) internal {
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
		require(intent.status == IntentStatus.CANCEL_PENDING, "PartyAFacet: Invalid state");
		require(
			block.timestamp > intent.statusModifyTimestamp + AppStorage.layout().forceCancelOpenIntentTimeout,
			"PartyAFacet: Cooldown not reached"
		);

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		intent.returnFeesAndPremium();
		intent.remove(false);
	}

	function forceCancelCloseIntent(uint256 intentId) internal {
		CloseIntent storage intent = IntentStorage.layout().closeIntents[intentId];
		require(intent.status == IntentStatus.CANCEL_PENDING, "PartyAFacet: Invalid state");
		require(
			block.timestamp > intent.statusModifyTimestamp + AppStorage.layout().forceCancelCloseIntentTimeout,
			"PartyAFacet: Cooldown not reached"
		);

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		intent.remove();
	}
}
