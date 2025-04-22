// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { TransferIntent } from "../types/TransferIntentTypes.sol";

library TransferIntentStorage {
	bytes32 internal constant SYMBOL_STORAGE_SLOT = keccak256("diamond.standard.storage.transferIntent");

	struct Layout {
		mapping(uint256 => TransferIntent) transferIntents;
		uint256 lastTransferIntentId;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = SYMBOL_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
