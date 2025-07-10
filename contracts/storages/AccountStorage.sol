// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { Withdraw, ExpressWithdrawProviderConfig } from "../types/WithdrawTypes.sol";
import { ScheduledReleaseBalance } from "../types/BalanceTypes.sol";

library AccountStorage {
	bytes32 internal constant ACCOUNT_STORAGE_SLOT = keccak256("diamond.standard.storage.account");

	struct Layout {
		mapping(address => mapping(address => ScheduledReleaseBalance)) balances; // user => collateral => balance
		mapping(address => bool) hasConfiguredInterval;
		mapping(address => uint256) releaseIntervals;
		uint256 defaultReleaseInterval;
		uint256 maxConnectedCounterParties;
		mapping(address => bool) manualSync; // allows unlimited counter parties but require user to manual sync their balances (should be set to true for partyBs)
		mapping(address => mapping(address => uint256)) nonces;
		/////////////////////////////////////////////////////////
		mapping(uint256 => Withdraw) withdrawals;
		uint256 lastWithdrawId;
		address invalidWithdrawalsAmountsPool;
		mapping(address => mapping(address => ExpressWithdrawProviderConfig)) expressWithdrawProviderConfigs; // provider => collateral => config
		/////////////////////////////////////////////////////////
		mapping(address => mapping(address => bool)) externalTransferTargets; // target => collateral => isValid
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = ACCOUNT_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
