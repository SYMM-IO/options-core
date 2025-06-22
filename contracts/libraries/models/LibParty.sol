// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AccountStorage } from "../../storages/AccountStorage.sol";
import { AppStorage } from "../../storages/AppStorage.sol";
import { LiquidationStorage } from "../../storages/LiquidationStorage.sol";

import { MarginType } from "../../types/BaseTypes.sol";
import { ScheduledReleaseBalance } from "../../types/BalanceTypes.sol";

import { BalanceErrors } from "../../errors/BalanceErrors.sol";

library LibParty {
	function requireSolvent(address self, address counterParty, address collateral, MarginType marginType) internal view {
		if (!isSolvent(self, counterParty, collateral, marginType)) revert BalanceErrors.NotSolvent(self, counterParty, collateral, marginType);
	}

	function isSolvent(address self, address counterParty, address collateral, MarginType marginType) internal view returns (bool) {
		if (isPartyB(self)) {
			return
				LiquidationStorage.layout().inProgressLiquidationIds[marginType == MarginType.ISOLATED ? address(0) : counterParty][self][
					collateral
				] == 0;
		} else {
			return marginType == MarginType.ISOLATED || LiquidationStorage.layout().inProgressLiquidationIds[self][counterParty][collateral] == 0;
		}
	}

	function isPartyB(address self) internal view returns (bool) {
		return AppStorage.layout().partyBConfigs[self].isActive;
	}

	function balanceOf(address self, address collateral) internal view returns (ScheduledReleaseBalance storage) {
		return AccountStorage.layout().balances[self][collateral];
	}

	function getReleaseInterval(address user) internal view returns (uint256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		return accountLayout.hasConfiguredInterval[user] ? accountLayout.releaseIntervals[user] : accountLayout.defaultReleaseInterval;
	}
}
