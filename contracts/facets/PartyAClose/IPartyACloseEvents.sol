// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { IntentStatus } from "../../storages/IntentStorage.sol";

interface IPartyACloseEvents is IPartiesEvents {
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
	event TransferTradeByPartyA(address sender, address receiver, uint256 tradeId);
	event MintMappingForTrade(uint256 tradeId, uint256 tokenId);
}
