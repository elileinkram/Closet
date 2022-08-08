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
    string public constant name = "Oath";

    string public constant symbol = "OATH";

    uint8 public constant decimals = 5;

    uint256 public constant totalSupply = 100000000000;

    mapping(address => uint256) balances;

    mapping(address => mapping(address => uint256)) allowed;

    struct Transaction {
        uint256 balance;
        uint256 timestamp;
    }

    mapping(address => Transaction[]) public transactionHistory;

    OathGov public oathGov;

    event Rebalanced(address indexed account, uint256 value);

    constructor(address _account) {
        balances[_account] = totalSupply;
        transactionHistory[_account].push(
            Transaction(totalSupply, block.timestamp)
        );
        oathGov = OathGov(msg.sender);
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
        transactionHistory[from].push(
            Transaction(balances[from], block.timestamp)
        );
        transactionHistory[to].push(Transaction(balances[to], block.timestamp));
        emit Transfer(from, to, amount);
        return true;
    }

    function rebalance(address _account, uint256 balance)
        public
        returns (bool)
    {
        require(msg.sender == address(oathGov));
        balances[_account] = balance;
        emit Rebalanced(_account, balance);
        return true;
    }

    function latestBalance(
        address _owner,
        uint256 _searchFrom,
        uint256 _deadline
    ) public view returns (uint256) {
        require(_searchFrom < transactionHistory[_owner].length);
        require(transactionHistory[_owner][_searchFrom].timestamp < _deadline);
        uint256 i = _searchFrom + 1;
        for (i; i < transactionHistory[_owner].length; i++) {
            if (
                transactionHistory[_owner][_searchFrom].timestamp >= _deadline
            ) {
                break;
            }
        }
        return transactionHistory[_owner][_searchFrom - 1].balance;
    }
}

contract OathGov {
    event DelegateElected(
        address indexed owner,
        address indexed account,
        uint256 value
    );

    event DelegateRecalled(
        address indexed owner,
        address indexed account,
        uint256 value
    );

    event Appointed(
        address indexed owner,
        address indexed account,
        bytes32 indexed id,
        uint256 index
    );

    enum Update {
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

    OathToken public oathToken;

    OathFactory public oathFactory;

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
        oathToken = new OathToken(msg.sender);
        oathFactory = new OathFactory();
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

    function elect(address _delegate, uint256 _amount) public returns (bool) {
        require(_amount != 0 && _delegate != address(0));
        delegateVotes[msg.sender][_delegate] = _amount;
        emit DelegateElected(msg.sender, _delegate, _amount);
        return true;
    }

    function recall(address _delegate, uint256 _amount) public returns (bool) {
        require(
            _amount != 0 &&
                _delegate != address(0) &&
                _amount <= delegateVotes[msg.sender][_delegate]
        );
        delegateVotes[msg.sender][_delegate] -= _amount;
        emit DelegateRecalled(msg.sender, _delegate, _amount);
        return true;
    }

    function appointManager(
        bytes32 _id,
        uint256 _index,
        address _manager
    ) public returns (bool) {
        require(votingPools[_id].providers[_index].account == msg.sender);
        votingPools[_id].providers[_index].manager = _manager;
        emit Appointed(msg.sender, _manager, _id, _index);
        return true;
    }

    function _stamp(
        address _from,
        bytes32 _id,
        uint256 _amount
    ) private {
        require(
            _amount >= minProvision && oathToken.balanceOf(_from) >= _amount
        );
        if (_from != msg.sender) {
            require(delegateVotes[_from][msg.sender] >= _amount);
            delegateVotes[_from][msg.sender] -= _amount;
        }
        oathToken.rebalance(_from, oathToken.balanceOf(_from) - _amount);
        votingPools[_id].liquidity += _amount;
    }

    function upvote(
        address _from,
        bytes32 _id,
        uint256 _index,
        uint256 _amount
    ) public returns (bool) {
        _stamp(_from, _id, _amount);
        require(
            _index < votingPools[_id].providers.length &&
                (votingPools[_id].providers[_index].account == msg.sender ||
                    votingPools[_id].providers[_index].manager == msg.sender)
        );
        votingPools[_id].providers[_index].amount += _amount;
        return true;
    }

    function castVote(
        address _from,
        bytes32 _id,
        uint256 _amount
    ) public returns (bool) {
        _stamp(_from, _id, _amount);
        uint256 length = votingPools[_id].lanes.length;
        if (length == 0) {
            votingPools[_id].providers.push(
                Provider(_from, msg.sender, _amount)
            );
        } else {
            votingPools[_id].providers[votingPools[_id].lanes[0]] = Provider(
                _from,
                msg.sender,
                _amount
            );
            votingPools[_id].lanes[0] = votingPools[_id].lanes[length - 1];
            votingPools[_id].lanes.pop();
        }
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
        if (msg.sender != provider.account) {
            require(msg.sender == provider.manager);
            delegateVotes[provider.account][msg.sender] += _amount;
        }
        oathToken.rebalance(
            provider.account,
            oathToken.balanceOf(provider.account) + _amount
        );
        provider.amount -= _amount;
        votingPools[_id].liquidity -= _amount;
        if (provider.amount == 0) {
            delete votingPools[_id].providers[_index];
            votingPools[_id].lanes.push(_index);
        }
        return true;
    }

    function proposeBoundaryUpdate(
        uint256 _num1,
        uint256 _num2,
        Update _update
    ) public returns (bool) {
        bytes32 newId;
        bytes32 oldId;
        if (_update == Update.Rates) {
            oldId = keccak256(abi.encode("rts", rates));
            rates = Rates(uint16(_num1), uint16(_num2));
            require(_isValidRates(rates));
            newId = keccak256(abi.encode("rts", rates));
        } else if (_update == Update.Provision) {
            oldId = keccak256(abi.encode("mpv", minProvision));
            minProvision = _num1;
            require(minProvision != 0);
            newId = keccak256(abi.encode("mpv", minProvision));
        } else if (_update == Update.PeriodConstraints) {
            oldId = keccak256(abi.encode("pcs", periodConstraints));
            periodConstraints = PeriodConstraints(_num1, _num2);
            require(_isValidPeriodConstraints(periodConstraints));
            newId = keccak256(abi.encode("pcs", periodConstraints));
        } else if (_update == Update.ByteConstraints) {
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
        return true;
    }

    function proposeTokenUpdate(
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
        return true;
    }

    function receiveDividend(
        address _owner,
        bytes32 _id,
        uint256 _searchFrom
    ) public returns (bool) {
        (
            uint256 serviceFee,
            uint256 deadline,
            address token,
            bool locked
        ) = oathFactory.findOath(_id);
        require(!locked && !received[_owner][_id]);
        received[_owner][_id] = true;
        uint256 balance = oathToken.latestBalance(
            _owner,
            _searchFrom,
            deadline
        );
        require(balance != 0, "No equity");
        uint256 payout = (serviceFee * balance) / oathToken.totalSupply();
        require(payout != 0, "No payout");
        require(IERC20(token).transfer(_owner, payout));
        return true;
    }
}

contract OathFactory {
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

    struct ByteConstraints {
        uint8 min;
        uint8 max;
    }

    OathGov public oathGov;

    mapping(bytes32 => Oath) public oaths;

    constructor() {
        oathGov = OathGov(msg.sender);
    }

    event Locked(
        address indexed _account,
        uint256 indexed _amount,
        bytes32 _hash
    );

    event Unlocked(address indexed _account, bytes32 indexed _hash);

    event Cracked(address indexed _account, bytes32 indexed _hash);

    function findOath(bytes32 _hash)
        public
        view
        returns (
            uint256,
            uint256,
            address,
            bool
        )
    {
        return (
            oaths[_hash].serviceFee,
            oaths[_hash].deadline,
            oaths[_hash].stake.token,
            oaths[_hash].stake.locked
        );
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
        uint256 minStake = oathGov.minStakeOf(_token);
        require(minStake != 0, "Token not found");
        require(_stake >= minStake);
        (uint256 payoutAmount, uint256 serviceFee) = _calculatePayout(_stake);
        require(serviceFee != 0 && payoutAmount > serviceFee);
        (uint8 min, uint8 max) = oathGov.byteConstraints();
        oaths[_hash] = Oath(
            serviceFee,
            _deadline,
            Stake(_token, msg.sender, _stake, true),
            Payout(address(0), payoutAmount),
            ByteConstraints(min, max)
        );
        return _lock(_hash, oaths[_hash]);
    }

    function _lock(bytes32 _hash, Oath storage _oath) private returns (bool) {
        uint256 duration = _oath.deadline - block.timestamp;
        (uint256 min, uint256 max) = oathGov.periodConstraints();
        require(
            _oath.deadline > block.timestamp &&
                duration >= min &&
                duration <= max,
            "Beyond time range"
        );
        require(_oath.stake.staker == address(0), "Oath taken");
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

    function _unlock(bytes32 _hash, Oath storage oath) private returns (bool) {
        require(oath.stake.staker == msg.sender, "Unauthorized");
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
