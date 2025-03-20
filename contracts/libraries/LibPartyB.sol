// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AppStorage, LiquidationStatus } from "../storages/AppStorage.sol";

library LibPartyB {
	function requireNotLiquidatedPartyB(address partyB, address collateral) internal view {
		require(
			AppStorage.layout().liquidationDetails[partyB][collateral].status == LiquidationStatus.SOLVENT,
			"Accessibility: PartyB is in the liquidation process"
		);
	}
}
