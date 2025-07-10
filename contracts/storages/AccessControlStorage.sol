// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

library AccessControlStorage {
	bytes32 internal constant ACCESS_CONTROL_STORAGE_SLOT = keccak256("diamond.standard.storage.accessControl");

	struct Layout {
		mapping(address => mapping(bytes32 => bool)) hasRole;
		mapping(bytes32 => EnumerableSet.AddressSet) roleMembers;
		uint8 reentrancyGuardStatus;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = ACCESS_CONTROL_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
