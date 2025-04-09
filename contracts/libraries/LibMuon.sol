// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IMuonOracle } from "../interfaces/IMuonOracle.sol";
import { SettlementPriceSig, AppStorage, LiquidationSig } from "../storages/AppStorage.sol";
import { SymbolStorage, Symbol, Oracle } from "../storages/SymbolStorage.sol";
import { CommonErrors } from "./CommonErrors.sol";

library LibMuon {
	// Custom errors
	error ExpiredSignature(uint256 currentTime, uint256 sigTimestamp, uint256 validTime, uint256 expiryTime);

	function getChainId() internal view returns (uint256 id) {
		assembly {
			id := chainid()
		}
	}

	function verifySettlementPriceSig(SettlementPriceSig memory sig) internal view {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();

		// == SignatureCheck( ==
		if (block.timestamp > sig.timestamp + appLayout.settlementPriceSigValidTime)
			revert ExpiredSignature(
				block.timestamp,
				sig.timestamp,
				appLayout.settlementPriceSigValidTime,
				sig.timestamp + appLayout.settlementPriceSigValidTime
			);
		// == ) ==

		Symbol storage symbol = symbolLayout.symbols[sig.symbolId];
		Oracle storage oracle = symbolLayout.oracles[symbol.oracleId];

		bytes32 hash = keccak256(
			abi.encodePacked(sig.reqId, address(this), sig.timestamp, sig.symbolId, sig.settlementPrice, sig.settlementTimestamp, sig.collateralPrice, getChainId())
		);

		IMuonOracle(oracle.contractAddress).verifyTSSAndGW(hash, sig.reqId, sig.sigs, sig.gatewaySignature);
	}

	function verifyLiquidationSig(LiquidationSig memory liquidationSig, address partyB) internal view {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		Oracle storage oracle = SymbolStorage.layout().oracles[appLayout.partyBConfigs[partyB].oracleId];

		bytes32 hash = keccak256(
			abi.encodePacked(
				liquidationSig.reqId,
				liquidationSig.liquidationId,
				address(this),
				"verifyLiquidationSig",
				partyB,
				liquidationSig.collateral,
				liquidationSig.collateralPrice,
				liquidationSig.upnl,
				liquidationSig.symbolIds,
				liquidationSig.prices,
				liquidationSig.timestamp,
				getChainId()
			)
		);

		IMuonOracle(oracle.contractAddress).verifyTSSAndGW(hash, liquidationSig.reqId, liquidationSig.sigs, liquidationSig.gatewaySignature);
	}
}
