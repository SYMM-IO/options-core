// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AppStorage, LiquidationStatus, LiquidationState, LiquidationDetail } from "../storages/AppStorage.sol";

library LibPartyB {
	function requireSolvent(address self, address collateral) internal view {
		require(isSolvent(self, collateral), "LibPartyB: PartyB is not solvent");
	}

	function requireInProgressLiquidation(address self, address collateral) internal view {
		require(
			AppStorage.layout().liquidationStates[self][collateral].status == LiquidationStatus.IN_PROGRESS,
			"LibPartyB: Invalid liquidation state"
		);
	}

	function isSolvent(address self, address collateral) internal view returns (bool) {
		return AppStorage.layout().liquidationStates[self][collateral].status == LiquidationStatus.SOLVENT;
	}

	function getLiquidationState(address self, address collateral) internal view returns (LiquidationState storage) {
		return AppStorage.layout().liquidationStates[self][collateral];
	}

	function getInProgressLiquidationDetail(address self, address collateral) internal view returns (LiquidationDetail storage) {
		return AppStorage.layout().liquidationDetails[getLiquidationState(self, collateral).inProgressLiquidationId];
	}
}
