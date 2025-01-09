// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./LibMuonV04ClientBase.sol";
import "../storages/SymbolStorage.sol";
import "../storages/AppStorage.sol";

library LibMuon {
	using ECDSA for bytes32;

	function getChainId() internal view returns (uint256 id) {
		assembly {
			id := chainid()
		}
	}

	// CONTEXT for commented out lines
	// We're utilizing muon signatures for asset pricing and user uPNLs calculations.
	// Even though these signatures are necessary for full testing of the system, particularly when invoking various methods.
	// The process of creating automated functional signature for tests has proven to be either impractical or excessively time-consuming. therefore, we've established commenting out the necessary code as a workaround specifically for testing.
	// Essentially, during testing, we temporarily disable the code sections responsible for validating these signatures. The sections I'm referring to are located within the LibMuon file. Specifically, the body of the 'verifyTSSAndGateway' method is a prime candidate for temporary disablement. In addition, several 'require' statements within other functions of this file, which examine the signatures' expiration status, also need to be temporarily disabled.
	// However, it is crucial to note that these lines should not be disabled in the production deployed version.
	// We emphasize this because they are only disabled for testing purposes.
	function verifyTSSAndGateway(
		bytes32 hash,
		SchnorrSign memory sign,
		bytes memory gatewaySignature,
		PublicKey memory publicKey,
		address validGateway
	) internal pure {
		// == SignatureCheck( ==
		bool verified = LibMuonV04ClientBase.muonVerify(uint256(hash), sign, publicKey);
		require(verified, "LibMuon: TSS not verified");

		hash = hash.toEthSignedMessageHash();
		address gatewaySignatureSigner = hash.recover(gatewaySignature);

		require(gatewaySignatureSigner == validGateway, "LibMuon: Gateway is not valid");
		// == ) ==
	}

	function verifySettlementPriceSig(SettlementPriceSig memory sig) internal view {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();
		// == SignatureCheck( ==
		require(block.timestamp <= sig.timestamp + appLayout.settlementPriceSigValidTime, "LibMuon: Expired signature");
		// == ) ==
		Symbol storage symbol = symbolLayout.symbols[sig.symbolId];
		Oracle storage oracle = symbolLayout.oracles[symbol.oracleId];

		bytes32 hash = keccak256(
			abi.encodePacked(
				oracle.muonConfig.muonAppId,
				sig.reqId,
				address(this),
				sig.timestamp,
				sig.symbolId,
				sig.settlementPrice,
				sig.settlementTimestamp,
				getChainId()
			)
		);
		verifyTSSAndGateway(hash, sig.sigs, sig.gatewaySignature, oracle.muonConfig.muonPublicKey, oracle.muonConfig.validGateway);
	}

	function verifyLiquidationSig(LiquidationSig memory liquidationSig, address partyB, address collateral) internal view {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		Oracle storage oracle = SymbolStorage.layout().oracles[appLayout.partyBConfigs[partyB].oracleId];
		require(liquidationSig.prices.length == liquidationSig.symbolIds.length, "LibMuon: Invalid length");
		bytes32 hash = keccak256(
			abi.encodePacked(
				oracle.muonConfig.muonAppId,
				liquidationSig.reqId,
				liquidationSig.liquidationId,
				address(this),
				"verifyLiquidationSig",
				partyB,
				collateral,
				liquidationSig.upnl,
				liquidationSig.symbolIds,
				liquidationSig.prices,
				liquidationSig.timestamp,
				getChainId()
			)
		);
		LibMuon.verifyTSSAndGateway(
			hash,
			liquidationSig.sigs,
			liquidationSig.gatewaySignature,
			oracle.muonConfig.muonPublicKey,
			oracle.muonConfig.validGateway
		);
	}
}
