// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import { IMuonOracle } from "../interfaces/IMuonOracle.sol";
import { SchnorrSECP256K1Verifier } from "./SchnorrSECP256K1Verifier.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MuonOracle is IMuonOracle, SchnorrSECP256K1Verifier, AccessControlEnumerable {
	using ECDSA for bytes32;

	bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

	MuonConfig public config;
	bool public checkGatewaySignature;

	constructor(MuonConfig memory _config, address admin) {
		validatePubKey(_config.muonPublicKey.x);
		config = _config;
		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		_grantRole(SETTER_ROLE, admin);
	}

	function verifyTSSAndGW(bytes32 _data, bytes calldata _reqId, SchnorrSign calldata _signature, bytes calldata _gatewaySignature) external view {
		bytes32 hash = keccak256(abi.encodePacked(config.muonAppId, _reqId, _data));
		require(
			verifySignature(config.muonPublicKey.x, config.muonPublicKey.parity, _signature.signature, uint256(hash), _signature.nonce),
			"Invalid signature"
		);

		hash = hash.toEthSignedMessageHash();
		address gatewaySignatureSigner = hash.recover(_gatewaySignature);
		require(gatewaySignatureSigner == config.validGateway, "Invalid gateway signature");
	}

	function setConfig(MuonConfig memory _config) external onlyRole(SETTER_ROLE) {
		validatePubKey(_config.muonPublicKey.x);
		config = _config;
		emit ConfigUpdated(_config);
	}
}
