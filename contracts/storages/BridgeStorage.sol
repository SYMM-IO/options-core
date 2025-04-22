// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { BridgeTransaction } from "../types/BridgeTypes.sol";

library BridgeStorage {
	bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.storage.bridge");

	struct Layout {
		mapping(address => bool) bridges;
		mapping(uint256 => BridgeTransaction) bridgeTransactions;
		mapping(address => uint256[]) bridgeTransactionIds;
		uint256 lastBridgeId;
		address invalidBridgedAmountsPool;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
