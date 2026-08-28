// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title DemoExitVault
/// @notice A minimal observable exit queue for the FairExit proof path.
/// @dev The vault deliberately permits its operator to process any outstanding request. FIFO is
///      an external bonded covenant, so a later OrderingCourt can prove a completed inversion from
///      authenticated `ExitRequested` and `ExitProcessed` transaction order. There is no cancel
///      path in the MVP, eliminating cancellation ambiguity from that predicate.
contract DemoExitVault {
    struct ExitRequest {
        address owner;
        uint128 shares;
        uint128 assets;
        bool processed;
    }

    address public operator;
    uint256 public nextRequestId = 1;

    mapping(uint256 requestId => ExitRequest request) private _requests;

    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
    event ExitRequested(uint256 indexed requestId, address indexed owner, uint256 shares);
    event ExitProcessed(uint256 indexed requestId, address indexed owner, uint256 assets);

    error NotOperator(address caller);
    error ZeroAddress();
    error ZeroShares();
    error UnknownRequest(uint256 requestId);
    error RequestAlreadyProcessed(uint256 requestId);

    constructor(address initialOperator) {
        if (initialOperator == address(0)) revert ZeroAddress();
        operator = initialOperator;
        emit OperatorTransferred(address(0), initialOperator);
    }

    modifier onlyOperator() {
        _checkOperator();
        _;
    }

    function _checkOperator() private view {
        if (msg.sender != operator) revert NotOperator(msg.sender);
    }

    function requestOf(uint256 requestId) external view returns (ExitRequest memory) {
        return _requests[requestId];
    }

    function transferOperator(address newOperator) external onlyOperator {
        if (newOperator == address(0)) revert ZeroAddress();
        address previous = operator;
        operator = newOperator;
        emit OperatorTransferred(previous, newOperator);
    }

    function requestExit(uint128 shares) external returns (uint256 requestId) {
        if (shares == 0) revert ZeroShares();
        requestId = nextRequestId++;
        _requests[requestId] = ExitRequest({ owner: msg.sender, shares: shares, assets: 0, processed: false });
        emit ExitRequested(requestId, msg.sender, shares);
    }

    /// @notice Processes any outstanding request; ordering remains observable in transaction order.
    function processExit(uint256 requestId, uint128 assets) external onlyOperator {
        ExitRequest storage request = _requests[requestId];
        if (request.owner == address(0)) revert UnknownRequest(requestId);
        if (request.processed) revert RequestAlreadyProcessed(requestId);

        request.processed = true;
        request.assets = assets;
        emit ExitProcessed(requestId, request.owner, assets);
    }
}
