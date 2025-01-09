// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/IntentStorage.sol";
import "../../interfaces/IPartiesEvents.sol";

interface IPartyAEvents is IPartiesEvents {
	event CancelOpenIntent(address partyA, address partyB, IntentStatus status, uint256 intentId);
	event SendCloseIntent(
		address partyA,
		address partyB,
		uint256 tradeId,
		uint256 closeIntentId,
		uint256 price,
		uint256 quantity,
		uint256 deadline,
		IntentStatus status
	);
	event CancelCloseIntent(address partyA, address partyB, uint256 intentId);
}
