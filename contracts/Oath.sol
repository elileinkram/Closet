// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract ERC20Token is IERC20 {
    struct Transaction {
        address buyer;
        address seller;
        uint256 amount;
        uint256 timestamp;
    }

    string public constant name = "Oath";

    string public constant symbol = "OATH";

    uint8 public constant decimals = 3;

    uint256 public constant totalSupply = 1000000000;

    mapping(address => uint256) balances;

    mapping(address => mapping(address => uint256)) allowed;

    constructor(address account) {
        balances[account] = totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        require(amount <= balances[msg.sender]);
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address _delegate, uint256 amount)
        public
        override
        returns (bool)
    {
        allowed[msg.sender][_delegate] = amount;
        emit Approval(msg.sender, _delegate, amount);
        return true;
    }

    function allowance(address _owner, address _delegate)
        public
        view
        override
        returns (uint256)
    {
        return allowed[_owner][_delegate];
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        require(amount <= balances[from]);
        require(amount <= allowed[from][msg.sender]);
        balances[from] -= amount;
        allowed[from][msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract Governance {
    enum ProposalType {
        PopToken,
        Token,
        ByteConstraints,
        PeriodConstraints,
        Rates,
        PropsalConstraints
    }

    struct StaleProposal {
        ProposalType proposalType;
        uint256 id;
    }

    struct ProposalConstraints {
        uint16 nayMultiplier;
        uint16 yayMultiplier;
        uint16 minParticipationRate;
        uint256 minStake;
        uint256 minVotingPeriod;
        uint256 maxVotingPeriod;
    }

    struct Ballot {
        uint256 yays;
        uint256 nays;
        uint16 yayMultiplier;
        uint16 nayMultiplier;
        uint16 minParticipationRate;
    }

    struct Proposal {
        address author;
        ProposalType proposalType;
        uint256 id;
        uint256 deadline;
        Ballot ballot;
    }

    struct PopToken {
        address address_;
        uint256 index;
    }

    struct Token {
        address address_;
        uint256 minStake;
    }

    struct ByteConstraints {
        uint8 min;
        uint8 max;
    }

    struct PeriodConstraints {
        uint256 min;
        uint256 max;
    }

    struct Rates {
        uint16 burn;
        uint16 take;
    }

    StaleProposal[] staleProposals;

    ProposalConstraints public proposalConstraints;

    OathFactory public oathFactory;

    ByteConstraints public byteConstraints;

    PeriodConstraints public periodConstraints;

    Rates public rates;

    Token[] public approvedTokens;

    ERC20Token public oathToken;

    Proposal[] public proposals;

    PopToken[] public popTokenProps;

    Token[] public tokenProps;

    Rates[] public rateProps;

    ProposalConstraints[] public proposalConstraintsProps;

    ByteConstraints[] public byteConstraintsProps;

    PeriodConstraints[] public periodConstraintsProps;

    constructor(
        ByteConstraints memory _byteConstraints,
        PeriodConstraints memory _periodConstraints,
        Rates memory _rates,
        Token memory _token,
        ProposalConstraints memory _proposalConstraints
    ) {
        require(_isValidByteConstraints(_byteConstraints));
        require(_isValidPeriodConstraints(_periodConstraints));
        require(_isValidRates(_rates));
        require(_isValidToken(_token));
        require(_isValidProposalConstraints(_proposalConstraints));
        byteConstraints = _byteConstraints;
        periodConstraints = _periodConstraints;
        rates = _rates;
        approvedTokens.push(_token);
        proposalConstraints = _proposalConstraints;
        oathFactory = new OathFactory(Governance(this));
        oathToken = new ERC20Token(msg.sender);
    }

    function getMinTokenStake(address _tokenAddress)
        public
        view
        returns (uint256 minStake)
    {
        for (uint16 i = 0; i < approvedTokens.length; i++) {
            if (approvedTokens[i].address_ == _tokenAddress) {
                minStake = approvedTokens[i].minStake;
                break;
            }
        }
    }

    function _isValidProposalConstraints(
        ProposalConstraints memory _proposalConstraints
    ) private pure returns (bool) {
        return
            _proposalConstraints.maxVotingPeriod >
            _proposalConstraints.minVotingPeriod;
    }

    function _isValidByteConstraints(ByteConstraints memory _byteConstraints)
        private
        pure
        returns (bool)
    {
        return
            _byteConstraints.max > _byteConstraints.min &&
            _byteConstraints.min != 0;
    }

    function _isValidPeriodConstraints(
        PeriodConstraints memory _periodConstraints
    ) private pure returns (bool) {
        return
            _periodConstraints.max > _periodConstraints.min &&
            _periodConstraints.min != 0;
    }

    function _isValidRates(Rates memory _rates) private pure returns (bool) {
        return
            (_rates.take + _rates.burn < type(uint16).max) &&
            _rates.take != 0 &&
            _rates.burn != 0;
    }

    function _isValidToken(Token memory _token) private pure returns (bool) {
        return _token.address_ != address(0) && _token.minStake != 0;
    }

    function _generateId(ProposalType _proposalType, uint256 _defaultId)
        private
        returns (uint256 newId)
    {
        for (uint256 i = 0; i < staleProposals.length; i++) {
            if (proposals[i].proposalType == _proposalType) {
                newId = staleProposals[i].id;
                staleProposals[i] = staleProposals[staleProposals.length - 1];
                staleProposals.pop();
                break;
            }
        }
        newId = _defaultId;
    }

    function proposePopToken(
        PopToken memory _popToken,
        uint256 _stake,
        uint256 _deadline
    ) public returns (bool) {
        require(approvedTokens[_popToken.index].address_ == _popToken.address_);
        uint256 newId = _generateId(
            ProposalType.PopToken,
            popTokenProps.length
        );
        if (newId == popTokenProps.length) {
            popTokenProps.push(_popToken);
        } else {
            popTokenProps[newId] = _popToken;
        }
        return _submitProposal(ProposalType.PopToken, newId, _stake, _deadline);
    }

    function _submitProposal(
        ProposalType _proposalType,
        uint256 _id,
        uint256 _stake,
        uint256 _deadline
    ) private returns (bool) {
        require(_stake >= proposalConstraints.minStake, "Insufficient stake");
        uint256 duration = _deadline - block.timestamp;
        require(
            _deadline > block.timestamp &&
                duration > proposalConstraints.minVotingPeriod &&
                duration < proposalConstraints.maxVotingPeriod,
            "Invalid voting period"
        );
        require(oathToken.transferFrom(msg.sender, address(this), _stake));
        proposals.push(
            Proposal(
                msg.sender,
                _proposalType,
                _id,
                _deadline,
                Ballot(
                    _stake,
                    0,
                    proposalConstraints.nayMultiplier,
                    proposalConstraints.nayMultiplier,
                    proposalConstraints.minParticipationRate
                )
            )
        );
        return true;
    }
}

contract OathFactory {
    struct Stake {
        address token;
        address staker;
        uint256 amount;
        bool locked;
    }

    struct Payout {
        address recipient;
        uint256 amount;
    }

    struct ByteConstraints {
        uint8 min;
        uint8 max;
    }

    struct Oath {
        uint256 serviceFee;
        uint256 deadline;
        Stake stake;
        Payout payout;
        ByteConstraints byteConstraints;
    }

    Governance public oathGov;

    mapping(bytes32 => Oath) public oaths;

    constructor(Governance _oathGov) {
        oathGov = _oathGov;
    }

    event Locked(
        address indexed _account,
        uint256 indexed _amount,
        bytes32 _hash
    );

    event Unlocked(address indexed _account, bytes32 indexed _hash);

    event Cracked(address indexed _account, bytes32 indexed _hash);

    modifier onlyOwner(address _account) {
        require(_account == msg.sender, "Unauthorized");
        _;
    }

    function _calculatePayout(uint256 _stake)
        private
        view
        returns (uint256, uint256)
    {
        (uint16 burn, uint16 take) = oathGov.rates();
        return (
            _stake - ((_stake * burn) / type(uint16).max),
            ((_stake * take) / type(uint16).max)
        );
    }

    function stake(
        bytes32 _hash,
        uint256 _stake,
        uint256 _deadline,
        address _token
    ) public returns (bool) {
        uint256 minStake = oathGov.getMinTokenStake(_token);
        require(minStake != 0, "Token not found");
        require(_stake >= minStake);
        (uint256 payoutAmount, uint256 serviceFee) = _calculatePayout(_stake);
        require(payoutAmount > serviceFee);
        (uint8 min, uint8 max) = oathGov.byteConstraints();
        Oath memory oath = Oath(
            serviceFee,
            _deadline,
            Stake(_token, msg.sender, _stake, true),
            Payout(address(0), payoutAmount),
            ByteConstraints(min, max)
        );
        return _lock(_hash, oath);
    }

    function _lock(bytes32 _hash, Oath memory _oath) private returns (bool) {
        uint256 duration = _oath.deadline - block.timestamp;
        (uint256 min, uint256 max) = oathGov.periodConstraints();
        require(
            _oath.deadline > block.timestamp &&
                duration >= min &&
                duration <= max,
            "Beyond time range"
        );
        require(_oath.stake.staker == address(0), "Oath taken");
        oaths[_hash] = _oath;
        emit Locked(_oath.stake.staker, _oath.stake.amount, _hash);
        require(
            IERC20(_oath.stake.token).transferFrom(
                _oath.stake.staker,
                address(this),
                _oath.stake.amount
            )
        );
        return true;
    }

    function crack(string memory _secret) public returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        Oath storage oath = oaths[hash];
        require(oath.deadline > block.timestamp);
        require(oath.payout.recipient == address(0), "Existing recipient");
        oath.payout.recipient = msg.sender;
        emit Cracked(oath.payout.recipient, hash);
        require(
            IERC20(oath.stake.token).transfer(
                oath.payout.recipient,
                oath.payout.amount
            )
        );
        return true;
    }

    function unstake(string memory _secret, bytes32 _hash)
        public
        returns (bool)
    {
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        require(hash == _hash, "Invalid secret or hash");
        Oath storage oath = oaths[_hash];
        uint256 byteSize = bytes(_secret).length;
        ByteConstraints storage byteConstraints = oath.byteConstraints;
        require(
            byteSize >= byteConstraints.min && byteSize <= byteConstraints.max,
            "Beyond byte range"
        );
        return _unlock(_hash, oath);
    }

    function _unlock(bytes32 _hash, Oath storage oath)
        private
        onlyOwner(oath.stake.staker)
        returns (bool)
    {
        require(oath.payout.recipient == address(0), "Secret was cracked");
        require(block.timestamp >= oath.deadline && oath.stake.locked);
        oath.stake.locked = false;
        emit Unlocked(oath.stake.staker, _hash);
        require(
            IERC20(oath.stake.token).transfer(
                oath.stake.staker,
                oath.stake.amount - oath.serviceFee
            )
        );
        require(
            IERC20(oath.stake.token).transfer(address(oathGov), oath.serviceFee)
        );
        return true;
    }
}
