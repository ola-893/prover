// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title PromiseSourceRegistry
/// @notice Governance registry for source contracts whose terminal-event policy has been reviewed.
/// @dev An approval is exact to kind, source chain, emitter and immutable policy version. Every
///      status change increments the revision so a revoke/reapprove cycle cannot resurrect a draft.
contract PromiseSourceRegistry {
    bytes32 private constant SOURCE_KEY_DOMAIN = keccak256("PROVER_SOURCE_ADAPTER_KEY_V1");

    struct Approval {
        uint64 revision;
        bool approved;
    }

    address public governor;
    address public pendingGovernor;

    mapping(bytes32 sourceKey => Approval approval) private _approvals;

    event SourceApprovalUpdated(
        bytes32 indexed sourceKey,
        uint8 indexed kind,
        uint64 indexed sourceChainKey,
        address sourceContract,
        bytes32 policyId,
        uint64 revision,
        bool approved
    );
    event GovernanceTransferStarted(address indexed governor, address indexed pendingGovernor);
    event GovernanceTransferred(address indexed previousGovernor, address indexed newGovernor);

    error ZeroAddress();
    error ZeroPolicyId();
    error NotGovernor(address caller);
    error NotPendingGovernor(address caller);
    error SourceApprovalUnchanged(bytes32 sourceKey, bool approved);
    error RevisionOverflow(bytes32 sourceKey);

    constructor(address initialGovernor) {
        if (initialGovernor == address(0)) revert ZeroAddress();
        governor = initialGovernor;
        emit GovernanceTransferred(address(0), initialGovernor);
    }

    function sourceKey(uint8 kind, uint64 sourceChainKey, address sourceContract, bytes32 policyId)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(SOURCE_KEY_DOMAIN, kind, sourceChainKey, sourceContract, policyId));
    }

    function approvalOf(uint8 kind, uint64 sourceChainKey, address sourceContract, bytes32 policyId)
        external
        view
        returns (bytes32 key, Approval memory approval)
    {
        key = sourceKey(kind, sourceChainKey, sourceContract, policyId);
        approval = _approvals[key];
    }

    function setSourceApproval(
        uint8 kind,
        uint64 sourceChainKey,
        address sourceContract,
        bytes32 policyId,
        bool approved
    ) external {
        if (msg.sender != governor) revert NotGovernor(msg.sender);
        if (sourceContract == address(0)) revert ZeroAddress();
        if (policyId == bytes32(0)) revert ZeroPolicyId();

        bytes32 key = sourceKey(kind, sourceChainKey, sourceContract, policyId);
        Approval storage current = _approvals[key];
        if (current.approved == approved) revert SourceApprovalUnchanged(key, approved);
        if (current.revision == type(uint64).max) revert RevisionOverflow(key);

        ++current.revision;
        current.approved = approved;
        emit SourceApprovalUpdated(key, kind, sourceChainKey, sourceContract, policyId, current.revision, approved);
    }

    function beginGovernanceTransfer(address newPendingGovernor) external {
        if (msg.sender != governor) revert NotGovernor(msg.sender);
        if (newPendingGovernor == address(0)) revert ZeroAddress();
        pendingGovernor = newPendingGovernor;
        emit GovernanceTransferStarted(msg.sender, newPendingGovernor);
    }

    function acceptGovernance() external {
        if (msg.sender != pendingGovernor) revert NotPendingGovernor(msg.sender);
        address previous = governor;
        governor = msg.sender;
        pendingGovernor = address(0);
        emit GovernanceTransferred(previous, msg.sender);
    }
}
