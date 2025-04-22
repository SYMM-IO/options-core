// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { CloseIntent } from "../types/IntentTypes.sol";

library CloseIntentStorage {
	bytes32 internal constant SYMBOL_STORAGE_SLOT = keccak256("diamond.standard.storage.closeIntent");

	struct Layout {
		mapping(uint256 => CloseIntent) closeIntents;
		mapping(uint256 => uint256[]) closeIntentIdsOf;
		uint256 lastCloseIntentId;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = SYMBOL_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
