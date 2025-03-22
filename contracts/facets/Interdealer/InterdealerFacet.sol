// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { IInterdealerEvents } from "./IInterdealerEvents.sol";
import { IInterdealerFacet } from "./IInterdealerFacet.sol";
import { InterdealerFacetImpl } from "./InterdealerFacetImpl.sol";

contract InterdealerFacet is Accessibility, Pausable, IInterdealerFacet {
	function sendTransferIntent(uint256 tradeId, address[] memory partyBWhitelist, uint256 proposedPrice, uint256 deadline) external {
		InterdealerFacetImpl.sendTransferIntent(tradeId, partyBWhitelist, proposedPrice, deadline);
		emit SendTransferIntent(tradeId, msg.sender, partyBWhitelist, proposedPrice, deadline);
	}

	function cancelTransferIntent(uint256 intentId) external {
		InterdealerFacetImpl.cancelTransferIntent(intentId);
		emit CancelTransferIntent(intentId);
	}

	function lockTransferIntent(uint256 intentId) external {
		InterdealerFacetImpl.lockTransferIntent(intentId);
		emit LockTransferIntent(intentId, msg.sender);
	}

	function unlockTransferIntent(uint256 intentId) external {
		InterdealerFacetImpl.unlockTransferIntent(intentId);
		emit UnlockTransferIntent(intentId, msg.sender);
	}

	function acceptCancelTransferIntent(uint256 intentId) external {
		InterdealerFacetImpl.acceptCancelTransferIntent(intentId);
		emit AcceptCancelTransferIntent(intentId, msg.sender);
	}

	function finalizeTransferIntent(uint256 intentId, uint256 fillPrice, bytes calldata clearingHouseSignature) external {
		InterdealerFacetImpl.finalizeTransferIntent(intentId, fillPrice, clearingHouseSignature);
		emit FinalizeTransferIntent(intentId, fillPrice, msg.sender, clearingHouseSignature);
	}
}
