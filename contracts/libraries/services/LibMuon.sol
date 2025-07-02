// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AppStorage } from "../../storages/AppStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";

import { SymbolStorage, Symbol, Oracle } from "../../storages/SymbolStorage.sol";

import { UpnlSig } from "../../types/WithdrawTypes.sol";
import { SettlementPriceSig } from "../../types/TradeTypes.sol";

import { IMuonOracle } from "../../interfaces/IMuonOracle.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";

library LibMuon {
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
			revert ValidationErrors.ExpiredSignature(
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

	function verifyUpnlSig(UpnlSig memory sig, address collateral, address party, address counterParty, uint256 oracleId) internal view {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();
		Oracle storage oracle = SymbolStorage.layout().oracles[oracleId];

		// == SignatureCheck( ==
		if (block.timestamp > sig.timestamp + appLayout.upnlSigValidTime)
			revert ValidationErrors.ExpiredSignature(
				block.timestamp,
				sig.timestamp,
				appLayout.upnlSigValidTime,
				sig.timestamp + appLayout.upnlSigValidTime
			);
		// == ) ==

		bytes32 hash = keccak256(
			abi.encodePacked(
				sig.reqId,
				address(this),
				"verifyUpnlSig",
				party,
				counterParty,
				sig.partyUpnl,
				sig.counterPartyUpnl,
				collateral,
				sig.collateralPrice,
				accountLayout.nonces[party][counterParty],
				sig.timestamp,
				getChainId()
			)
		);

		IMuonOracle(oracle.contractAddress).verifyTSSAndGW(hash, sig.reqId, sig.sigs, sig.gatewaySignature);
	}
}
