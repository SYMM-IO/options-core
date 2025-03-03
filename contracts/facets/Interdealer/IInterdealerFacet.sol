// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./IInterdealerEvents.sol";
import "../../storages/AppStorage.sol";

interface IInterdealerFacet is IInterdealerEvents {
	function interdealerIntent(uint256 tradeId, address[] memory partyBWhitelist) external;

	function cancelInterdealerIntent(uint256 intentId) external;

	function lockInterdealerIntent(uint256 intentId, uint256 tradeQuantity) external;

	function unlockInterdealerIntent(uint256 intentId) external;

	function acceptCancelInterdealerIntent(uint256 intentId) external;

	function fillInterdealerIntent(uint256 intentId, uint256 price) external;
}
