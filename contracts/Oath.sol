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

contract OathToken is IERC20 {
    event Rebalanced(address indexed account, uint256 value);

    event GatedEntry(address indexed account, uint256 value);

    string public constant name = "Oath";

    string public constant symbol = "OATH";

    uint8 public constant decimals = 5;

    uint256 public constant totalSupply = 100000000000;

    mapping(address => uint256) private balances;

    mapping(address => mapping(address => uint256)) private allowed;

    mapping(address => uint256) public minEntryAmount;

    struct Transaction {
        uint256 balance;
        uint256 timestamp;
    }

    mapping(address => Transaction[]) public transactionHistory;

    constructor() {
        balances[msg.sender] = totalSupply;
        transactionHistory[msg.sender].push(
            Transaction(totalSupply, block.timestamp)
        );
    }

    function balanceOf(address account) public view override returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        require(amount >= minEntryAmount[to]);
        require(amount <= balances[msg.sender]);
        balances[msg.sender] -= amount;
        balances[to] += amount;
        transactionHistory[msg.sender].push(
            Transaction(balances[msg.sender], block.timestamp)
        );
        transactionHistory[to].push(Transaction(balances[to], block.timestamp));
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

    function setEntryMinimum(uint256 amount) public {
        minEntryAmount[msg.sender] = amount;
        emit GatedEntry(msg.sender, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        require(amount >= minEntryAmount[to]);
        require(amount <= balances[from]);
        require(amount <= allowed[from][msg.sender]);
        balances[from] -= amount;
        allowed[from][msg.sender] -= amount;
        balances[to] += amount;
        transactionHistory[from].push(
            Transaction(balances[from], block.timestamp)
        );
        transactionHistory[to].push(Transaction(balances[to], block.timestamp));
        emit Transfer(from, to, amount);
        return true;
    }

    function rebalance(address _account, uint256 balance) internal {
        balances[_account] = balance;
        emit Rebalanced(_account, balance);
    }

    function latestBalance(
        address _owner,
        uint256 _searchFrom,
        uint256 _until
    ) public view returns (uint256) {
        require(_searchFrom < transactionHistory[_owner].length);
        require(transactionHistory[_owner][_searchFrom].timestamp < _until);
        uint256 i = _searchFrom + 1;
        for (i; i < transactionHistory[_owner].length; i++) {
            if (transactionHistory[_owner][i].timestamp >= _until) {
                break;
            }
        }
        return transactionHistory[_owner][i - 1].balance;
    }
}

contract OathGov is OathToken {
    event Voted(
        address indexed owner,
        address indexed delegate,
        bytes32 indexed id,
        uint256 i,
        uint256 amount
    );

    event Delegated(
        address indexed owner,
        address indexed account,
        uint256 value
    );

    event Appointed(
        address indexed owner,
        address indexed account,
        bytes32 indexed id,
        uint256 i
    );

    event StateChanged(
        State indexed state,
        bytes32 indexed oldId,
        bytes32 indexed newId
    );

    event Rewarded(address indexed owner, bytes32 indexed id, uint256 amount);

    enum State {
        Token,
        Provision,
        ByteConstraints,
        PeriodConstraints,
        Rates
    }

    struct Provider {
        address account;
        address manager;
        uint256 amount;
    }

    struct Pool {
        uint256 liquidity;
        Provider[] providers;
        uint256[] lanes;
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
        uint16 take;
        uint16 burn;
    }

    mapping(address => mapping(address => uint256)) public delegateVotes;

    mapping(address => mapping(bytes32 => bool)) public received;

    mapping(bytes32 => Pool) public votingPools;

    ByteConstraints public byteConstraints;

    PeriodConstraints public periodConstraints;

    Rates public rates;

    Token[] public approvedTokens;

    uint256 public minProvision;

    constructor(
        ByteConstraints memory _byteConstraints,
        PeriodConstraints memory _periodConstraints,
        Rates memory _rates,
        address[] memory _tokens,
        uint256[] memory _stakes,
        uint256 _minProvision
    ) {
        require(_isValidByteConstraints(_byteConstraints));
        require(_isValidPeriodConstraints(_periodConstraints));
        require(_isValidRates(_rates));
        require(_minProvision != 0);
        require(_tokens.length == _stakes.length);
        byteConstraints = _byteConstraints;
        periodConstraints = _periodConstraints;
        rates = _rates;
        minProvision = _minProvision;
        for (uint256 i = 0; i < _tokens.length; i++) {
            approvedTokens.push(Token(_tokens[i], _stakes[i]));
            require(_isValidToken(approvedTokens[i], _tokens, i + 1));
        }
    }

    function minStakeOf(address _address)
        public
        view
        returns (uint256 minStake)
    {
        for (uint256 i = 0; i < approvedTokens.length; i++) {
            if (approvedTokens[i].address_ == _address) {
                minStake = approvedTokens[i].minStake;
                break;
            }
        }
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

    function _isValidToken(
        Token memory _token,
        address[] memory _checkAgainst,
        uint256 _i
    ) private pure returns (bool) {
        for (uint256 i = _i; i < _checkAgainst.length; i++) {
            if (_token.address_ == _checkAgainst[i]) return false;
        }
        return _token.address_ != address(0) && _token.minStake != 0;
    }

    function delegateTo(address _delegate, uint256 _amount)
        public
        returns (bool)
    {
        require(_amount != 0 && _delegate != address(0));
        delegateVotes[msg.sender][_delegate] += _amount;
        emit Delegated(
            msg.sender,
            _delegate,
            delegateVotes[msg.sender][_delegate]
        );
        return true;
    }

    function releaseFrom(address _delegate, uint256 _amount)
        public
        returns (bool)
    {
        require(
            _amount != 0 &&
                _delegate != address(0) &&
                _amount <= delegateVotes[msg.sender][_delegate]
        );
        delegateVotes[msg.sender][_delegate] -= _amount;
        emit Delegated(
            msg.sender,
            _delegate,
            delegateVotes[msg.sender][_delegate]
        );
        return true;
    }

    function appoint(
        bytes32 _id,
        uint256 _index,
        address _manager
    ) public returns (bool) {
        require(votingPools[_id].providers[_index].account == msg.sender);
        require(_manager != address(0));
        votingPools[_id].providers[_index].manager = _manager;
        emit Appointed(msg.sender, _manager, _id, _index);
        return true;
    }

    function _approveVote(
        address _from,
        bytes32 _id,
        uint256 _amount
    ) private {
        require(_amount >= minProvision && balanceOf(_from) >= _amount);
        if (_from != msg.sender) {
            require(delegateVotes[_from][msg.sender] >= _amount);
            delegateVotes[_from][msg.sender] -= _amount;
        }
        rebalance(_from, balanceOf(_from) - _amount);
        votingPools[_id].liquidity += _amount;
    }

    function upgradeVote(
        address _from,
        bytes32 _id,
        uint256 _index,
        uint256 _amount
    ) public returns (bool) {
        _approveVote(_from, _id, _amount);
        require(
            _index < votingPools[_id].providers.length &&
                (votingPools[_id].providers[_index].account == msg.sender ||
                    votingPools[_id].providers[_index].manager == msg.sender)
        );
        votingPools[_id].providers[_index].amount += _amount;
        emit Voted(
            _from,
            msg.sender,
            _id,
            _index,
            votingPools[_id].providers[_index].amount
        );
        return true;
    }

    function castVote(
        address _from,
        bytes32 _id,
        uint256 _amount
    ) public returns (bool) {
        _approveVote(_from, _id, _amount);
        uint256 length = votingPools[_id].lanes.length;
        uint256 index;
        if (length == 0) {
            index = votingPools[_id].providers.length;
            votingPools[_id].providers.push(
                Provider(_from, msg.sender, _amount)
            );
        } else {
            index = votingPools[_id].lanes[0];
            votingPools[_id].providers[votingPools[_id].lanes[0]] = Provider(
                _from,
                msg.sender,
                _amount
            );
            votingPools[_id].lanes[0] = votingPools[_id].lanes[length - 1];
            votingPools[_id].lanes.pop();
        }
        emit Voted(_from, msg.sender, _id, index, _amount);
        return true;
    }

    function unwindPosition(
        bytes32 _id,
        uint256 _amount,
        uint256 _index
    ) public returns (bool) {
        require(_amount != 0 && _index < votingPools[_id].providers.length);
        Provider storage provider = votingPools[_id].providers[_index];
        require(_amount <= provider.amount);
        provider.amount -= _amount;
        votingPools[_id].liquidity -= _amount;
        if (msg.sender != provider.account) {
            require(msg.sender == provider.manager);
            delegateVotes[provider.account][msg.sender] += _amount;
        }
        rebalance(provider.account, balanceOf(provider.account) + _amount);
        if (provider.amount == 0) {
            delete votingPools[_id].providers[_index];
            votingPools[_id].lanes.push(_index);
        }
        emit Voted(provider.account, msg.sender, _id, _index, provider.amount);
        return true;
    }

    function changeBoundaryState(
        uint256 _num1,
        uint256 _num2,
        State _state
    ) public returns (bool) {
        bytes32 oldId;
        bytes32 newId;
        if (_state == State.Rates) {
            oldId = keccak256(abi.encode("rts", rates));
            rates = Rates(uint16(_num1), uint16(_num2));
            require(_isValidRates(rates));
            newId = keccak256(abi.encode("rts", rates));
        } else if (_state == State.Provision) {
            oldId = keccak256(abi.encode("mpv", minProvision));
            minProvision = _num1;
            require(minProvision != 0);
            newId = keccak256(abi.encode("mpv", minProvision));
        } else if (_state == State.PeriodConstraints) {
            oldId = keccak256(abi.encode("pcs", periodConstraints));
            periodConstraints = PeriodConstraints(_num1, _num2);
            require(_isValidPeriodConstraints(periodConstraints));
            newId = keccak256(abi.encode("pcs", periodConstraints));
        } else if (_state == State.ByteConstraints) {
            oldId = keccak256(abi.encode("bcs", byteConstraints));
            byteConstraints = ByteConstraints(uint8(_num1), uint8(_num2));
            require(_isValidByteConstraints(byteConstraints));
            newId = keccak256(abi.encode("bcs", byteConstraints));
        }
        require(
            newId != "" &&
                votingPools[newId].liquidity > votingPools[oldId].liquidity,
            "Insufficient liquidity"
        );
        emit StateChanged(_state, oldId, newId);
        return true;
    }

    function proposeTokenState(
        address[] memory _tokens,
        uint256[] memory _stakes
    ) public returns (bool) {
        require(_tokens.length == _stakes.length);
        bytes32 oldId = keccak256(abi.encode(approvedTokens));
        uint256 i = 0;
        if (_tokens.length > approvedTokens.length) {
            for (i; i < approvedTokens.length; i++) {
                approvedTokens[i] = Token(_tokens[i], _stakes[i]);
                require(_isValidToken(approvedTokens[i], _tokens, i + 1));
            }
            for (i; i < _tokens.length; i++) {
                approvedTokens.push(Token(_tokens[i], _stakes[i]));
                require(_isValidToken(approvedTokens[i], _tokens, i + 1));
            }
        } else {
            for (i; i < _tokens.length; i++) {
                approvedTokens[i] = Token(_tokens[i], _stakes[i]);
                require(_isValidToken(approvedTokens[i], _tokens, i + 1));
            }
            for (i; i < approvedTokens.length; i++) {
                approvedTokens.pop();
            }
        }
        bytes32 newId = keccak256(abi.encode(approvedTokens));
        require(
            votingPools[newId].liquidity > votingPools[oldId].liquidity,
            "Insufficient liquidity"
        );
        emit StateChanged(State.Token, oldId, newId);
        return true;
    }
}

contract OathFactory is OathGov {
    event Locked(
        address indexed _account,
        bytes32 _hash,
        uint256 _stake,
        uint256 _serviceFee
    );

    event Unlocked(
        address indexed _account,
        bytes32 indexed _hash,
        string _secret,
        uint256 _stake,
        uint256 _serviceFee
    );

    event Cracked(
        address indexed _account,
        bytes32 indexed _hash,
        string _secret,
        uint256 _stake,
        uint256 _payout
    );

    struct Oath {
        uint256 serviceFee;
        uint256 deadline;
        Stake stake;
        Payout payout;
        ByteConstraints byteConstraints;
    }

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

    mapping(bytes32 => Oath) public oaths;

    constructor(
        ByteConstraints memory _byteConstraints,
        PeriodConstraints memory _periodConstraints,
        Rates memory _rates,
        address[] memory _tokens,
        uint256[] memory _stakes,
        uint256 _minProvision
    )
        OathGov(
            _byteConstraints,
            _periodConstraints,
            _rates,
            _tokens,
            _stakes,
            _minProvision
        )
    {}

    function _calculateOutflows(uint256 _stake)
        private
        view
        returns (uint256, uint256)
    {
        return (
            _stake - ((_stake * rates.burn) / type(uint16).max),
            ((_stake * rates.take) / type(uint16).max)
        );
    }

    function stake(
        bytes32 _hash,
        uint256 _stake,
        uint256 _deadline,
        address _token
    ) public returns (bool) {
        uint256 minStake = minStakeOf(_token);
        require(minStake != 0 && _stake >= minStake);
        uint256 duration = _deadline - block.timestamp;
        require(
            _deadline > block.timestamp &&
                duration >= periodConstraints.min &&
                duration <= periodConstraints.max
        );
        (uint256 payoutAmount, uint256 serviceFee) = _calculateOutflows(_stake);
        require(serviceFee != 0 && payoutAmount > serviceFee);
        require(oaths[_hash].stake.staker == address(0));
        oaths[_hash] = Oath(
            serviceFee,
            _deadline,
            Stake(_token, msg.sender, _stake, true),
            Payout(address(0), payoutAmount),
            byteConstraints
        );
        require(IERC20(_token).transferFrom(msg.sender, address(this), _stake));
        emit Locked(msg.sender, _hash, _stake, serviceFee);
        return true;
    }

    function crack(string memory _secret) public returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        Oath storage oath = oaths[hash];
        require(oath.deadline > block.timestamp);
        require(oath.payout.recipient == address(0), "Existing recipient");
        oath.payout.recipient = msg.sender;
        require(
            IERC20(oath.stake.token).transfer(msg.sender, oath.payout.amount)
        );
        emit Cracked(
            oath.payout.recipient,
            hash,
            _secret,
            oath.stake.amount,
            oath.payout.amount
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
            byteSize >= byteConstraints.min && byteSize <= byteConstraints.max
        );
        require(oath.stake.staker == msg.sender, "Unauthorized");
        require(oath.payout.recipient == address(0), "Secret was cracked");
        require(block.timestamp >= oath.deadline);
        require(oath.stake.locked);
        oath.stake.locked = false;
        require(
            IERC20(oath.stake.token).transfer(
                msg.sender,
                oath.stake.amount - oath.serviceFee
            )
        );
        require(
            IERC20(oath.stake.token).transfer(address(this), oath.serviceFee)
        );
        emit Unlocked(
            oath.stake.staker,
            _hash,
            _secret,
            oath.stake.amount,
            oath.serviceFee
        );
        return true;
    }

    function claimReward(
        address _awardee,
        bytes32 _hash,
        uint256 _searchFrom
    ) public returns (bool) {
        Oath storage oath = oaths[_hash];
        require(!oath.stake.locked && !received[_awardee][_hash]);
        received[_awardee][_hash] = true;
        uint256 balance = latestBalance(_awardee, _searchFrom, oath.deadline);
        uint256 reward = (oath.serviceFee * balance) / totalSupply;
        require(reward != 0);
        require(IERC20(oath.stake.token).transfer(_awardee, reward));
        emit Rewarded(_awardee, _hash, reward);
        return true;
    }
}
