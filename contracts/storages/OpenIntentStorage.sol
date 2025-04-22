// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { OpenIntent } from "../types/IntentTypes.sol";

library OpenIntentStorage {
	bytes32 internal constant SYMBOL_STORAGE_SLOT = keccak256("diamond.standard.storage.openIntent");

	struct Layout {
		mapping(uint256 => OpenIntent) openIntents;
		mapping(address => uint256[]) openIntentsOf;
		mapping(address => uint256[]) activeOpenIntentsOf;
		mapping(address => uint256) activeOpenIntentsCount;
		mapping(uint256 => uint256) partyAOpenIntentsIndex;
		mapping(uint256 => uint256) partyBOpenIntentsIndex;
		uint256 lastOpenIntentId;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = SYMBOL_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
