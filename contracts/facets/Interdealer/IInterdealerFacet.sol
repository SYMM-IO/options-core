// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IInterdealerEvents } from "./IInterdealerEvents.sol";

interface IInterdealerFacet is IInterdealerEvents {
	function sendTransferIntent(uint256 tradeId, address[] memory partyBWhitelist, uint256 proposedPrice, uint256 deadline) external;

	function cancelTransferIntent(uint256 intentId) external;

	function lockTransferIntent(uint256 intentId) external;

	function unlockTransferIntent(uint256 intentId) external;

	function acceptCancelTransferIntent(uint256 intentId) external;

	function finalizeTransferIntent(uint256 intentId, uint256 fillPrice, bytes calldata clearingHouseSignature) external;
}
