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
    struct Proposal {
        address author;
        ByteConstraints byteConstraints;
        PeriodConstraints periodConstraints;
        VotingConstraints votingConstraints;
        Rates rates;
        Token[] approvedTokens;
    }

    struct Token {
        address address_;
        uint256 minStake;
    }

    struct VotingConstraints {
        PeriodConstraints periodConstraints;
        uint32 minStake;
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

    OathFactory oathFactory;

    ByteConstraints public byteConstraints;

    PeriodConstraints public periodConstraints;

    Rates public rates;

    Token[] public approvedTokens;

    VotingConstraints public votingConstraints;

    ERC20Token public oathToken;

    constructor(
        ByteConstraints memory _byteConstraints,
        PeriodConstraints memory _periodConstraints,
        VotingConstraints memory _votingConstraints,
        Rates memory _rates,
        address[] memory _tokenAddresses,
        uint256[] memory _tokenStakes
    )
        checkConstraints(
            _byteConstraints,
            _periodConstraints,
            _votingConstraints
        )
        checkRates(_rates)
        onlyPositive(
            _byteConstraints.min,
            _periodConstraints.min,
            _votingConstraints.periodConstraints.min,
            _rates.take,
            _rates.burn,
            _votingConstraints.minStake
        )
    {
        _approveTokens(_tokenAddresses, _tokenStakes);
        byteConstraints = _byteConstraints;
        periodConstraints = _periodConstraints;
        votingConstraints = _votingConstraints;
        rates = _rates;
        oathFactory = new OathFactory(Governance(this));
        oathToken = new ERC20Token(msg.sender);
    }

    function _approveTokens(
        address[] memory _tokenAddresses,
        uint256[] memory _tokenStakes
    ) private {
        require(_tokenAddresses.length == _tokenStakes.length);
        require(
            _tokenAddresses.length <= type(uint16).max,
            "Token limit exceeded"
        );
        for (uint16 i = 0; i < _tokenAddresses.length; i++) {
            require(_tokenAddresses[i] != address(0) && _tokenStakes[i] != 0);
            approvedTokens.push(Token(_tokenAddresses[i], _tokenStakes[i]));
            for (uint16 j = i + 1; j < _tokenAddresses.length; j++) {
                require(
                    _tokenAddresses[i] != _tokenAddresses[j],
                    "Duplicate token address"
                );
            }
        }
    }

    modifier checkConstraints(
        ByteConstraints memory _byteConstraints,
        PeriodConstraints memory _periodConstraints,
        VotingConstraints memory _votingConstraints
    ) {
        require(
            _byteConstraints.max > _byteConstraints.min &&
                _periodConstraints.max > _periodConstraints.min &&
                _votingConstraints.periodConstraints.max >
                _votingConstraints.periodConstraints.min,
            "Invalid constraints"
        );
        _;
    }

    modifier checkRates(Rates memory _rates) {
        require(_rates.take + _rates.burn < type(uint16).max, "Invalid rates");
        _;
    }

    modifier onlyPositive(
        uint8 _minBytes,
        uint256 _minLockupPeriod,
        uint256 _minVotingPeriod,
        uint16 _takeRate,
        uint16 _burnRate,
        uint32 _minProposalStake
    ) {
        require(
            _minBytes != 0 &&
                _minLockupPeriod != 0 &&
                _takeRate != 0 &&
                _burnRate != 0 &&
                _minVotingPeriod != 0 &&
                _minProposalStake != 0,
            "Invalid input parameters"
        );
        _;
    }

    function getMinTokenStake(address _tokenAddress)
        public
        view
        returns (uint256)
    {
        Token memory token;
        for (uint16 i = 0; i < approvedTokens.length; i++) {
            if (approvedTokens[i].address_ == _tokenAddress) {
                token = approvedTokens[i];
            }
        }
        return token.minStake;
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
        uint256 tax;
    }

    struct Oath {
        uint256 deadline;
        Stake stake;
        Payout payout;
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
            _stake - (_stake * (burn / type(uint16).max)),
            _stake * (take / type(uint16).max)
        );
    }

    function stake(
        bytes32 _hash,
        uint256 _stake,
        uint256 _deadline,
        address _token
    ) public returns (bool) {
        require(_token != address(0));
        uint256 minStake = oathGov.getMinTokenStake(_token);
        require(minStake != 0, "Token not found");
        require(_stake >= minStake);
        (uint256 amount, uint256 tax) = _calculatePayout(_stake);
        Oath memory oath = Oath(
            _deadline,
            Stake(_token, msg.sender, _stake, true),
            Payout(address(0), amount, tax)
        );
        return _lock(_hash, oath);
    }

    function _lock(bytes32 _hash, Oath memory _oath) private returns (bool) {
        require(_oath.deadline > block.timestamp);
        uint256 duration = _oath.deadline - block.timestamp;
        (uint256 min, uint256 max) = oathGov.periodConstraints();
        require(duration >= min && duration <= max);
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
                oath.payout.amount - oath.payout.tax
            )
        );
        require(
            IERC20(oath.stake.token).transfer(address(oathGov), oath.payout.tax)
        );
        return true;
    }

    function unstake(string memory _secret, bytes32 _hash)
        public
        returns (bool)
    {
        uint256 byteSize = bytes(_secret).length;
        (uint8 min, uint8 max) = oathGov.byteConstraints();
        require(byteSize >= min && byteSize <= max, "Beyond byte range");
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        require(hash == _hash, "Invalid secret or hash");
        Oath storage oath = oaths[_hash];
        return _unlock(_hash, oath);
    }

    function _unlock(bytes32 _hash, Oath storage oath)
        private
        onlyOwner(oath.stake.staker)
        returns (bool)
    {
        require(oath.payout.recipient == address(0), "Secret was cracked");
        require(block.timestamp >= oath.deadline);
        require(oath.stake.locked);
        oath.stake.locked = false;
        emit Unlocked(oath.stake.staker, _hash);
        require(
            IERC20(oath.stake.token).transfer(
                oath.stake.staker,
                oath.stake.amount
            )
        );
        return true;
    }
}
