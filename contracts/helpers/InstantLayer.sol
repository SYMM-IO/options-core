// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
pragma solidity >=0.8.19;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

interface IMultiAccount {
	function _call(address account, bytes[] memory _callDatas) external;
	function owners(address account) external view returns (address);
}

interface ISymmioPartyB {
	function _call(bytes[] calldata _callDatas) external;
}

interface ISymmio {
	function setCallFromInstantLayer(bool _callFromInstantLayer) external;
}	

contract InstantLayer is AccessControlEnumerable, ReentrancyGuard {
	bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
	bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

	IMultiAccount public immutable multiAccount;
	ISymmioPartyB public immutable symmioPartyB;
	ISymmio public immutable symmio;

	mapping(address => uint256) public nonces;
	mapping(uint256 => Template) public templates;
	mapping(bytes32 => bool) public usedSignatures;
	mapping(address => bool) public registeredPartyBs;
	uint256 public nextTemplateId;

	struct Operation {
		address account; // For PartyA operations - which account to use
		bytes callData; // The actual calldata with placeholders
		uint256[] insertionPoints; // Where to insert return values
		uint256[] sourceIndices; // Which operation's return value to use
		address signer; // Expected signer for this operation
	}

	struct Template {
		string name;
		Operation[] operations;
		bool active;
	}

	struct SignedOperation {
		address account; // The account to use (for PartyA operations)
		address signer; // The signer
		bytes callData; // The actual Symmio core call
		uint256 nonce;
		uint256 deadline;
		bytes signature;
	}

	event TemplateAdded(uint256 indexed templateId, string name);
	event TemplateUpdated(uint256 indexed templateId, bool active);
	event OperationsExecuted(uint256 indexed templateId, address indexed executor);
	event BatchExecuted(address indexed executor, uint256 operationCount);
	event NonceIncremented(address indexed user, uint256 newNonce);
	event PartyBRegistered(address indexed partyB);
	event PartyBUnregistered(address indexed partyB);

	error InvalidSignature(address signer);
	error DeadlineExpired(uint256 deadline);
	error InvalidNonce(address user, uint256 expected, uint256 provided);
	error TemplateNotActive(uint256 templateId);
	error InvalidTemplate(uint256 templateId);
	error OperationFailed(uint256 operationIndex);
	error ArrayLengthMismatch();
	error InvalidAccount(address account);
	error SignatureAlreadyUsed(bytes32 hash);
	error InvalidSigner(address expected, address provided);

	constructor(address _multiAccount, address _symmioPartyB, address _symmio, address _admin) {
		multiAccount = IMultiAccount(_multiAccount);
		symmioPartyB = ISymmioPartyB(_symmioPartyB);
		symmio = ISymmio(_symmio);

		_grantRole(DEFAULT_ADMIN_ROLE, _admin);
		_grantRole(ADMIN_ROLE, _admin);
		_grantRole(OPERATOR_ROLE, _admin);
	}

	/**
	 * @notice Register a PartyB signer
	 * @param partyB Address to register as PartyB
	 */
	function registerPartyB(address partyB) external onlyRole(ADMIN_ROLE) {
		registeredPartyBs[partyB] = true;
		emit PartyBRegistered(partyB);
	}

	/**
	 * @notice Unregister a PartyB signer
	 * @param partyB Address to unregister
	 */
	function unregisterPartyB(address partyB) external onlyRole(ADMIN_ROLE) {
		registeredPartyBs[partyB] = false;
		emit PartyBUnregistered(partyB);
	}

	/**
	 * @notice Check if an address is a registered PartyB
	 * @param addr Address to check
	 * @return Whether the address is a registered PartyB
	 */
	function isPartyB(address addr) public view returns (bool) {
		return registeredPartyBs[addr];
	}

	/**
	 * @notice Add a new template
	 * @param name Template name
	 * @param operations Array of operations in the template
	 */
	function addTemplate(string calldata name, Operation[] calldata operations) external onlyRole(ADMIN_ROLE) {
		uint256 templateId = nextTemplateId++;
		Template storage template = templates[templateId];
		template.name = name;
		template.active = true;

		for (uint256 i = 0; i < operations.length; i++) {
			template.operations.push(operations[i]);
		}

		emit TemplateAdded(templateId, name);
	}

	/**
	 * @notice Toggle template active status
	 * @param templateId Template to update
	 * @param active New status
	 */
	function setTemplateActive(uint256 templateId, bool active) external onlyRole(ADMIN_ROLE) {
		if (templateId >= nextTemplateId) revert InvalidTemplate(templateId);
		templates[templateId].active = active;
		emit TemplateUpdated(templateId, active);
	}

	/**
	 * @notice Execute operations based on a template
	 * @param templateId Template to use
	 * @param signedOps Array of signed operations matching the template
	 */
	function executeTemplate(uint256 templateId, SignedOperation[] calldata signedOps) external nonReentrant {
		if (templateId >= nextTemplateId) revert InvalidTemplate(templateId);

		Template storage template = templates[templateId];
		if (!template.active) revert TemplateNotActive(templateId);
		if (signedOps.length != template.operations.length) revert ArrayLengthMismatch();

		// Set instant mode active
		symmio.setCallFromInstantLayer(true);

		bytes[] memory results = new bytes[](signedOps.length);

		bool success = true;
		for (uint256 i = 0; i < signedOps.length && success; i++) {
			Operation memory op = template.operations[i];
			SignedOperation calldata signedOp = signedOps[i];

			// Verify signature and nonce
			_verifyOperation(op, signedOp);

			// Prepare calldata with insertions from previous results
			bytes memory finalCallData = _insertResults(signedOp.callData, op.insertionPoints, op.sourceIndices, results);

			// Update operation with account from signed op
			op.account = signedOp.account;

			// Execute operation
			(success, results[i]) = _executeOperationSafe(op, signedOp, finalCallData);
			if (!success) {
				symmio.setCallFromInstantLayer(false);
				revert OperationFailed(i);
			}
		}

		// Reset instant mode
		symmio.setCallFromInstantLayer(false);
		emit OperationsExecuted(templateId, msg.sender);
	}

	/**
	 * @notice Execute a batch of operations without template
	 * @param signedOps Array of signed operations
	 */
	function executeBatch(SignedOperation[] calldata signedOps) external nonReentrant {
		symmio.setCallFromInstantLayer(true);

		bool success = true;
		for (uint256 i = 0; i < signedOps.length && success; i++) {
			Operation memory op = Operation({
				account: signedOps[i].account,
				callData: "",
				insertionPoints: new uint256[](0),
				sourceIndices: new uint256[](0),
				signer: signedOps[i].signer
			});

			// Verify signature and nonce
			_verifyOperation(op, signedOps[i]);

			(success, ) = _executeOperationSafe(op, signedOps[i], signedOps[i].callData);
			if (!success) {
				symmio.setCallFromInstantLayer(false);
				revert OperationFailed(i);
			}
		}

		symmio.setCallFromInstantLayer(false);
		emit BatchExecuted(msg.sender, signedOps.length);
	}

	/**
	 * @notice Verify signature for an operation
	 * @param op The operation details
	 * @param signedOp The signed operation
	 */
	function _verifyOperation(Operation memory op, SignedOperation calldata signedOp) private {
		if (signedOp.deadline < block.timestamp) revert DeadlineExpired(signedOp.deadline);

		bytes32 hash = _getOperationHash(signedOp);

		// Check if signature was already used
		if (usedSignatures[hash]) revert SignatureAlreadyUsed(hash);

		address expectedSigner;

		// Determine if this is a PartyB operation based on signer
		if (isPartyB(signedOp.signer)) {
			// PartyB operation
			expectedSigner = signedOp.signer;
		} else {
			// PartyA operation - verify the account owner's signature
			if (signedOp.account == address(0)) revert InvalidAccount(signedOp.account);
			address owner = multiAccount.owners(signedOp.account);
			if (owner == address(0)) revert InvalidAccount(signedOp.account);
			expectedSigner = owner;
		}

		if (op.signer != address(0) && op.signer != expectedSigner) {
			revert InvalidSigner(op.signer, expectedSigner);
		}

		// Verify signature using OpenZeppelin's SignatureChecker
		if (!SignatureChecker.isValidSignatureNow(expectedSigner, hash, signedOp.signature)) {
			revert InvalidSignature(expectedSigner);
		}

		// Verify and increment nonce
		uint256 expectedNonce = nonces[expectedSigner];
		if (signedOp.nonce != expectedNonce) {
			revert InvalidNonce(expectedSigner, expectedNonce, signedOp.nonce);
		}

		nonces[expectedSigner]++;
		usedSignatures[hash] = true;
		emit NonceIncremented(expectedSigner, nonces[expectedSigner]);
	}

	/**
	 * @notice Execute operation safely
	 * @param op Operation details
	 * @param signedOp Signed operation details
	 * @param callData The calldata to execute
	 * @return success Whether the operation succeeded
	 * @return result The return data
	 */
	function _executeOperationSafe(
		Operation memory op,
		SignedOperation calldata signedOp,
		bytes memory callData
	) private returns (bool success, bytes memory result) {
		// Determine target based on signer type
		bool isPartyBOperation = isPartyB(signedOp.signer);
		address target = isPartyBOperation ? address(symmioPartyB) : address(multiAccount);

		bytes[] memory callDatas = new bytes[](1);
		callDatas[0] = callData;
		if (!isPartyBOperation) {
			(success, result) = target.call(abi.encodeWithSelector(IMultiAccount._call.selector, op.account, callDatas));
		} else {
			(success, result) = target.call(abi.encodeWithSelector(ISymmioPartyB._call.selector, callDatas));
		}
	}

	function _insertResults(
		bytes memory callData,
		uint256[] memory insertionPoints,
		uint256[] memory sourceIndices,
		bytes[] memory results
	) private pure returns (bytes memory) {
		if (insertionPoints.length == 0) return callData;

		// Calculate new size
		uint256 additionalSize = 0;
		for (uint256 i = 0; i < insertionPoints.length; i++) {
			if (sourceIndices[i] < results.length && results[sourceIndices[i]].length > 0) {
				// Decode the return value to get the actual data
				bytes memory decodedResult = abi.decode(results[sourceIndices[i]], (bytes));
				additionalSize += decodedResult.length;
			}
		}

		bytes memory newCallData = new bytes(callData.length + additionalSize);
		uint256 currentPos = 0;
		uint256 newPos = 0;

		// Sort insertion points (bubble sort for simplicity)
		uint256[] memory sortedInsertionPoints = new uint256[](insertionPoints.length);
		uint256[] memory sortedSourceIndices = new uint256[](sourceIndices.length);

		// Copy arrays
		for (uint256 i = 0; i < insertionPoints.length; i++) {
			sortedInsertionPoints[i] = insertionPoints[i];
			sortedSourceIndices[i] = sourceIndices[i];
		}

		// Sort
		for (uint256 i = 0; i < sortedInsertionPoints.length; i++) {
			for (uint256 j = i + 1; j < sortedInsertionPoints.length; j++) {
				if (sortedInsertionPoints[i] > sortedInsertionPoints[j]) {
					// Swap
					(sortedInsertionPoints[i], sortedInsertionPoints[j]) = (sortedInsertionPoints[j], sortedInsertionPoints[i]);
					(sortedSourceIndices[i], sortedSourceIndices[j]) = (sortedSourceIndices[j], sortedSourceIndices[i]);
				}
			}
		}

		// Insert results at specified points
		for (uint256 i = 0; i < sortedInsertionPoints.length; i++) {
			uint256 insertPoint = sortedInsertionPoints[i];

			// Copy data up to insertion point
			for (uint256 j = currentPos; j < insertPoint && j < callData.length; j++) {
				newCallData[newPos++] = callData[j];
			}

			// Insert result if available
			if (sortedSourceIndices[i] < results.length && results[sortedSourceIndices[i]].length > 0) {
				bytes memory decodedResult = abi.decode(results[sortedSourceIndices[i]], (bytes));
				for (uint256 j = 0; j < decodedResult.length; j++) {
					newCallData[newPos++] = decodedResult[j];
				}
			}

			currentPos = insertPoint;
		}

		// Copy remaining data
		for (uint256 i = currentPos; i < callData.length; i++) {
			newCallData[newPos++] = callData[i];
		}

		// Resize array to actual size
		assembly {
			mstore(newCallData, newPos)
		}

		return newCallData;
	}

	function _getOperationHash(SignedOperation calldata op) private pure returns (bytes32) {
		return keccak256(abi.encodePacked(op.account, op.signer, op.callData, op.nonce, op.deadline));
	}

	// View functions
	function getTemplate(uint256 templateId) external view returns (Template memory) {
		return templates[templateId];
	}

	function getTemplateOperations(uint256 templateId) external view returns (Operation[] memory) {
		return templates[templateId].operations;
	}

	/**
	 * @notice Verify a signature externally (useful for testing)
	 * @param signer Expected signer address
	 * @param hash Message hash
	 * @param signature Signature bytes
	 * @return Whether the signature is valid
	 */
	function verifySignature(address signer, bytes32 hash, bytes calldata signature) external view returns (bool) {
		return SignatureChecker.isValidSignatureNow(signer, hash, signature);
	}
}
