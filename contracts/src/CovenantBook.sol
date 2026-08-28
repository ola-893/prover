// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Exact subset of Creditcoin's ChainInfo precompile used by CovenantBook.
/// @dev Production deployments inject 0x0000000000000000000000000000000000000fD3.
///      Tests inject a deterministic mock with the same ABI.
interface IAttestedHeightSource {
    struct HeightHashResult {
        uint64 height;
        bytes32 hash;
        bool isAttestation;
        bool exists;
    }

    // Exact snake-case ABI shipped by the ChainInfo precompile.
    // forge-lint: disable-next-line(mixed-case-function)
    function get_latest_attestation_height_and_hash(uint64 chainKey)
        external
        view
        returns (HeightHashResult memory result);
}

/// @title CovenantBook
/// @notice Immutable, native-CTC bonds behind typed source-chain performance promises.
/// @dev Covenant terms cannot be edited, cancelled, shortened or retroactively activated. A bond
///      can leave the book only through a court ruling or after the source-chain coverage and a
///      fixed source-block claim window have both passed. All transfers use pull payouts.
contract CovenantBook {
    /// @notice Seven days at Ethereum's 12-second block cadence. The MVP supports Ethereum and Sepolia.
    uint64 public constant CLAIM_WINDOW_BLOCKS = 50_400;

    enum CovenantType {
        NO_SANDWICH,
        FIFO
    }

    struct Covenant {
        address operator;
        address sourceContract;
        bytes32 policyHash;
        CovenantType covenantType;
        uint64 chainKey;
        uint64 validFromHeight;
        uint64 validUntilHeight;
        uint64 claimDeadlineHeight;
        uint32 breachCount;
        uint256 fixedPenalty;
        uint256 initialBond;
        uint256 remainingBond;
        uint256 totalPaid;
        uint256 totalShortfall;
        bool bondReleased;
    }

    IAttestedHeightSource public immutable CHAIN_INFO;
    address public immutable NO_SANDWICH_COURT;
    address public immutable FIFO_COURT;

    mapping(address operator => uint64 nonce) public nextNonce;
    mapping(bytes32 covenantId => Covenant covenant) private _covenants;
    mapping(bytes32 claimKey => bool settled) public settledClaims;
    mapping(address beneficiary => uint256 amount) public claimable;

    uint256 private _entered;

    event CovenantOpened(
        bytes32 indexed covenantId,
        CovenantType indexed covenantType,
        address indexed operator,
        uint64 chainKey,
        address sourceContract,
        uint64 validFromHeight,
        uint64 validUntilHeight,
        uint64 claimDeadlineHeight,
        bytes32 policyHash,
        uint256 fixedPenalty,
        uint256 initialBond
    );
    event BreachSettled(
        bytes32 indexed covenantId,
        bytes32 indexed claimKey,
        bytes32 indexed evidenceId,
        address beneficiary,
        uint64 breachHeight,
        uint256 fixedPenalty,
        uint256 paid,
        uint256 shortfall,
        uint256 remainingBond
    );
    event BondReleased(bytes32 indexed covenantId, address indexed operator, uint256 amount);
    event PayoutWithdrawn(address indexed beneficiary, address indexed recipient, uint256 amount);

    error ZeroAddress();
    error ZeroPolicyHash();
    error ZeroPenalty();
    error InsufficientInitialBond(uint256 supplied, uint256 minimum);
    error SourceChainNotAttested(uint64 chainKey);
    error HeightOverflow();
    error CoverageEndsBeforeActivation(uint64 validFromHeight, uint64 validUntilHeight);
    error CovenantNotFound(bytes32 covenantId);
    error WrongCourt(address caller, address expected);
    error ZeroEvidenceId();
    error ClaimAlreadySettled(bytes32 claimKey);
    error BreachOutsideCoverage(uint64 breachHeight, uint64 validFromHeight, uint64 validUntilHeight);
    error BreachHeightNotAttested(uint64 breachHeight, uint64 latestAttestedHeight);
    error ClaimWindowClosed(uint64 latestAttestedHeight, uint64 claimDeadlineHeight);
    error ClaimWindowStillOpen(uint64 latestAttestedHeight, uint64 claimDeadlineHeight);
    error NotCovenantOperator(address caller, address operator);
    error BondAlreadyReleased(bytes32 covenantId);
    error NothingToWithdraw();
    error TransferFailed();
    error Reentrancy();
    error DirectTransferDisabled();

    constructor(address chainInfo, address noSandwichCourt, address fifoCourt) {
        if (chainInfo == address(0) || noSandwichCourt == address(0) || fifoCourt == address(0)) {
            revert ZeroAddress();
        }
        CHAIN_INFO = IAttestedHeightSource(chainInfo);
        NO_SANDWICH_COURT = noSandwichCourt;
        FIFO_COURT = fifoCourt;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        if (_entered != 0) revert Reentrancy();
        _entered = 1;
    }

    function _nonReentrantAfter() private {
        _entered = 0;
    }

    function covenantOf(bytes32 covenantId) external view returns (Covenant memory) {
        return _covenants[covenantId];
    }

    function claimKeyFor(bytes32 covenantId, bytes32 evidenceId) public pure returns (bytes32 claimKey) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, covenantId)
            mstore(add(ptr, 0x20), evidenceId)
            claimKey := keccak256(ptr, 0x40)
        }
    }

    /// @notice Posts an immutable no-sandwich promise starting after the current attested tip.
    function openNoSandwich(
        uint64 chainKey,
        address sourceContract,
        uint64 validUntilHeight,
        bytes32 policyHash,
        uint256 fixedPenalty
    ) external payable returns (bytes32 covenantId) {
        return _open(CovenantType.NO_SANDWICH, chainKey, sourceContract, validUntilHeight, policyHash, fixedPenalty);
    }

    /// @notice Posts an immutable FIFO promise starting after the current attested tip.
    function openFifo(
        uint64 chainKey,
        address sourceContract,
        uint64 validUntilHeight,
        bytes32 policyHash,
        uint256 fixedPenalty
    ) external payable returns (bytes32 covenantId) {
        return _open(CovenantType.FIFO, chainKey, sourceContract, validUntilHeight, policyHash, fixedPenalty);
    }

    /// @notice Settles a proof-derived violation and credits a pull payout.
    /// @dev Only the court assigned to this covenant type may call. `evidenceId` is derived by that
    ///      court from the authenticated source transactions; replay is scoped to this covenant.
    function settleBreach(bytes32 covenantId, bytes32 evidenceId, uint64 breachHeight, address beneficiary)
        external
        returns (uint256 paid, uint256 shortfall)
    {
        Covenant storage covenant = _covenants[covenantId];
        if (covenant.operator == address(0)) revert CovenantNotFound(covenantId);

        address expectedCourt = covenant.covenantType == CovenantType.NO_SANDWICH ? NO_SANDWICH_COURT : FIFO_COURT;
        if (msg.sender != expectedCourt) revert WrongCourt(msg.sender, expectedCourt);
        if (evidenceId == bytes32(0)) revert ZeroEvidenceId();
        if (beneficiary == address(0)) revert ZeroAddress();
        if (covenant.bondReleased) revert BondAlreadyReleased(covenantId);
        if (breachHeight < covenant.validFromHeight || breachHeight > covenant.validUntilHeight) {
            revert BreachOutsideCoverage(breachHeight, covenant.validFromHeight, covenant.validUntilHeight);
        }

        bytes32 claimKey = claimKeyFor(covenantId, evidenceId);
        if (settledClaims[claimKey]) revert ClaimAlreadySettled(claimKey);

        IAttestedHeightSource.HeightHashResult memory tip = _latestAttested(covenant.chainKey);
        if (breachHeight > tip.height) revert BreachHeightNotAttested(breachHeight, tip.height);
        if (tip.height > covenant.claimDeadlineHeight) {
            revert ClaimWindowClosed(tip.height, covenant.claimDeadlineHeight);
        }

        settledClaims[claimKey] = true;
        paid = covenant.remainingBond < covenant.fixedPenalty ? covenant.remainingBond : covenant.fixedPenalty;
        shortfall = covenant.fixedPenalty - paid;
        covenant.remainingBond -= paid;
        covenant.totalPaid += paid;
        covenant.totalShortfall += shortfall;
        ++covenant.breachCount;
        claimable[beneficiary] += paid;

        emit BreachSettled(
            covenantId,
            claimKey,
            evidenceId,
            beneficiary,
            breachHeight,
            covenant.fixedPenalty,
            paid,
            shortfall,
            covenant.remainingBond
        );
    }

    /// @notice Releases unused bond only after both coverage and the source-height claim window.
    /// @dev There is intentionally no early cancel, deactivate or unbond function.
    function releaseMaturedBond(bytes32 covenantId) external {
        Covenant storage covenant = _covenants[covenantId];
        if (covenant.operator == address(0)) revert CovenantNotFound(covenantId);
        if (msg.sender != covenant.operator) revert NotCovenantOperator(msg.sender, covenant.operator);
        if (covenant.bondReleased) revert BondAlreadyReleased(covenantId);

        IAttestedHeightSource.HeightHashResult memory tip = _latestAttested(covenant.chainKey);
        if (tip.height <= covenant.claimDeadlineHeight) {
            revert ClaimWindowStillOpen(tip.height, covenant.claimDeadlineHeight);
        }

        covenant.bondReleased = true;
        uint256 amount = covenant.remainingBond;
        covenant.remainingBond = 0;
        claimable[covenant.operator] += amount;
        emit BondReleased(covenantId, covenant.operator, amount);
    }

    /// @notice Withdraws the caller's accumulated court awards or matured bond release.
    function withdrawPayout(address payable recipient) external nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 amount = claimable[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        claimable[msg.sender] = 0;

        (bool sent,) = recipient.call{ value: amount }("");
        if (!sent) revert TransferFailed();
        emit PayoutWithdrawn(msg.sender, recipient, amount);
    }

    function _open(
        CovenantType covenantType,
        uint64 chainKey,
        address sourceContract,
        uint64 validUntilHeight,
        bytes32 policyHash,
        uint256 fixedPenalty
    ) private returns (bytes32 covenantId) {
        if (sourceContract == address(0)) revert ZeroAddress();
        if (policyHash == bytes32(0)) revert ZeroPolicyHash();
        if (fixedPenalty == 0) revert ZeroPenalty();
        if (msg.value < fixedPenalty) revert InsufficientInitialBond(msg.value, fixedPenalty);

        IAttestedHeightSource.HeightHashResult memory tip = _latestAttested(chainKey);
        if (tip.height == type(uint64).max || validUntilHeight > type(uint64).max - CLAIM_WINDOW_BLOCKS) {
            revert HeightOverflow();
        }

        uint64 validFromHeight = tip.height + 1;
        if (validUntilHeight < validFromHeight) {
            revert CoverageEndsBeforeActivation(validFromHeight, validUntilHeight);
        }
        uint64 claimDeadlineHeight = validUntilHeight + CLAIM_WINDOW_BLOCKS;
        uint64 nonce = nextNonce[msg.sender]++;

        covenantId = keccak256(
            abi.encode(
                block.chainid,
                address(this),
                msg.sender,
                nonce,
                covenantType,
                chainKey,
                sourceContract,
                validFromHeight,
                validUntilHeight,
                policyHash,
                fixedPenalty,
                msg.value
            )
        );

        _covenants[covenantId] = Covenant({
            operator: msg.sender,
            sourceContract: sourceContract,
            policyHash: policyHash,
            covenantType: covenantType,
            chainKey: chainKey,
            validFromHeight: validFromHeight,
            validUntilHeight: validUntilHeight,
            claimDeadlineHeight: claimDeadlineHeight,
            breachCount: 0,
            fixedPenalty: fixedPenalty,
            initialBond: msg.value,
            remainingBond: msg.value,
            totalPaid: 0,
            totalShortfall: 0,
            bondReleased: false
        });

        emit CovenantOpened(
            covenantId,
            covenantType,
            msg.sender,
            chainKey,
            sourceContract,
            validFromHeight,
            validUntilHeight,
            claimDeadlineHeight,
            policyHash,
            fixedPenalty,
            msg.value
        );
    }

    function _latestAttested(uint64 chainKey) private view returns (IAttestedHeightSource.HeightHashResult memory tip) {
        tip = CHAIN_INFO.get_latest_attestation_height_and_hash(chainKey);
        if (!tip.exists) revert SourceChainNotAttested(chainKey);
    }

    receive() external payable {
        revert DirectTransferDisabled();
    }
}
