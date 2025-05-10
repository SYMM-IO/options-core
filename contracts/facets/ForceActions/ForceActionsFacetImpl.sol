// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { CommonErrors } from "../../libraries/CommonErrors.sol";
import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { LibCloseIntentOps } from "../../libraries/LibCloseIntent.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { CloseIntentStorage } from "../../storages/CloseIntentStorage.sol";

import { IntentStatus } from "../../types/IntentTypes.sol";
import { OpenIntent, CloseIntent } from "../../types/IntentTypes.sol";

library ForceActionsFacetImpl {
	using LibOpenIntentOps for OpenIntent;
	using LibCloseIntentOps for CloseIntent;

	function forceCancelOpenIntent(uint256 intentId) internal {
		OpenIntent storage intent = OpenIntentStorage.layout().openIntents[intentId];

		CommonErrors.requireStatus("IntentStatus", uint8(intent.status), uint8(IntentStatus.CANCEL_PENDING));

		if (block.timestamp <= intent.statusModifyTimestamp + AppStorage.layout().forceCancelOpenIntentTimeout)
			revert CommonErrors.CooldownNotOver(
				"forceCancelOpenIntentTimeout",
				block.timestamp,
				intent.statusModifyTimestamp + AppStorage.layout().forceCancelOpenIntentTimeout
			);

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		intent.handleFeesAndPremium(false);
		intent.remove(false);
	}

	function forceCancelCloseIntent(uint256 intentId) internal {
		CloseIntent storage intent = CloseIntentStorage.layout().closeIntents[intentId];

		CommonErrors.requireStatus("IntentStatus", uint8(intent.status), uint8(IntentStatus.CANCEL_PENDING));

		if (block.timestamp <= intent.statusModifyTimestamp + AppStorage.layout().forceCancelCloseIntentTimeout)
			revert CommonErrors.CooldownNotOver(
				"forceCancelCloseIntentTimeout",
				block.timestamp,
				intent.statusModifyTimestamp + AppStorage.layout().forceCancelCloseIntentTimeout
			);

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		intent.remove();
	}
}
