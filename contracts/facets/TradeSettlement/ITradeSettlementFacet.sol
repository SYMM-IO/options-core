// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { SettlementPriceSig } from "../../storages/AppStorage.sol";
import { ITradeSettlementEvents } from "./ITradeSettlementEvents.sol";

interface ITradeSettlementFacet is ITradeSettlementEvents {
	function executeTrade(uint256 tradeId, SettlementPriceSig memory settlementPriceSig) external;
}
