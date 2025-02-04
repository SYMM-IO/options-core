// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMuonOracle {
	struct PublicKey {
		uint256 x;
		uint8 parity;
	}

	struct MuonConfig {
		uint256 muonAppId;
		PublicKey muonPublicKey;
		address validGateway;
	}

	struct SchnorrSign {
		uint256 signature;
		address owner;
		address nonce;
	}

	event ConfigUpdated(MuonConfig newConfig);
	event CheckGatewaySignatureUpdated(bool newValue);

	function verifyTSSAndGW(bytes32 _data, bytes calldata _reqId, SchnorrSign calldata _signature, bytes calldata _gatewaySignature) external view;

	function setConfig(MuonConfig memory _config) external;
}
