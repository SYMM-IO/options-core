// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library CounterPartyRelationsStorage {
	bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.storage.counterPartyRelations");

	struct Layout {
		mapping(address => address) boundPartyB; // partyA => Address of partyB
		mapping(address => uint256) unbindingRequestTime; // partyA => time when unbinding was requested
		uint256 unbindingCooldown;
		/////////////////////////////////////////////////////////
		mapping(address => bool) instantActionsMode;
		mapping(address => uint256) instantActionsModeDeactivateTime;
		uint256 deactiveInstantActionModeCooldown;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
