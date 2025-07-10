// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

interface ITradeEvents {
	event TransferTradeByPartyA(address indexed sender, address indexed receiver, uint256 tradeId);
	event ExecuteTrades(address operator, uint256[] tradeIds, bool[] exercised, bool[] expired, uint256 settlementPrice, uint256 collateralPrice);
}
