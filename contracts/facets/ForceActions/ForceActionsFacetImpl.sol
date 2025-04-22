// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibCloseIntentOps } from "../../libraries/LibCloseIntent.sol";
import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";
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

		if (intent.status != IntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(IntentStatus.CANCEL_PENDING);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

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

		if (intent.status != IntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(IntentStatus.CANCEL_PENDING);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

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
