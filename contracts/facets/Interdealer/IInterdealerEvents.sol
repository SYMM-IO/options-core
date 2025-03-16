// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/IntentStorage.sol";

interface IInterdealerEvents {
	event SendTransferIntent(uint256 tradeId, address sender, address[] partyBWhitelist, uint256 price, uint256 deadline);
	event CancelTransferIntent(uint256 tradeId);
	event LockTransferIntent(uint256 tradeId, address counterParty);
	event UnlockTransferIntent(uint256 tradeId, address counterParty);
	event AcceptCancelTransferIntent(uint256 tradeId, address counterParty);
	event FinalizeTransferIntent(uint256 tradeId, uint256 fillPrice, address counterParty, bytes clearingHouseSignature);
}
