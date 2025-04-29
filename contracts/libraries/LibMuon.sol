// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AppStorage } from "../storages/AppStorage.sol";
import { AccountStorage } from "../storages/AccountStorage.sol";

import { SymbolStorage, Symbol, Oracle } from "../storages/SymbolStorage.sol";

import { LiquidationSig } from "../types/LiquidationTypes.sol";
import { UpnlSig } from "../types/WithdrawTypes.sol";
import { SettlementPriceSig } from "../types/SettlementTypes.sol";

import { IMuonOracle } from "../interfaces/IMuonOracle.sol";

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
			abi.encodePacked(
				sig.reqId,
				address(this),
				sig.timestamp,
				sig.symbolId,
				sig.settlementPrice,
				sig.settlementTimestamp,
				sig.collateralPrice,
				getChainId()
			)
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

	function verifyUpnlSig(UpnlSig memory upnlSig, address collateral, address partyA, address partyB) internal view {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Oracle storage oracle = SymbolStorage.layout().oracles[appLayout.partyBConfigs[partyB].oracleId];

		bytes32 hash = keccak256(
			abi.encodePacked(
				upnlSig.reqId,
				address(this),
				"verifyUpnlSig",
				partyA,
				partyB,
				upnlSig.partyAUpnl,
				upnlSig.partyBUpnl,
				collateral,
				upnlSig.collateralPrice,
				accountLayout.nonces[partyA][partyB],
				accountLayout.nonces[partyB][partyA],
				upnlSig.timestamp,
				getChainId()
			)
		);

		IMuonOracle(oracle.contractAddress).verifyTSSAndGW(hash, upnlSig.reqId, upnlSig.sigs, upnlSig.gatewaySignature);
	}
}
