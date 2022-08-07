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

contract Governance is IERC20 {
    struct Transaction {
        uint256 balance;
        uint256 timestamp;
    }

    event Elected(
        address indexed owner,
        address indexed account,
        uint256 value
    );

    event Recalled(
        address indexed owner,
        address indexed account,
        uint256 value
    );

    event Appointed(
        address indexed owner,
        address indexed account,
        bytes32 id,
        uint256 index
    );

    string public constant name = "Oath";

    string public constant symbol = "OATH";

    uint8 public constant decimals = 3;

    uint256 public constant totalSupply = 1000000000;

    mapping(address => uint256) balances;

    mapping(address => mapping(address => uint256)) allowed;

    mapping(address => mapping(address => uint256)) public delegateVotes;

    mapping(address => Transaction[]) public transactionHistory;

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

    mapping(bytes32 => Pool) public votingPools;

    ByteConstraints public byteConstraints;

    PeriodConstraints public periodConstraints;

    Rates public rates;

    Token[] public approvedTokens;

    uint256 public minProvision;

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
        balances[msg.sender] = totalSupply;
        transactionHistory[msg.sender].push(
            Transaction(totalSupply, block.timestamp)
        );
        byteConstraints = _byteConstraints;
        periodConstraints = _periodConstraints;
        rates = _rates;
        minProvision = _minProvision;
        for (uint256 i = 0; i < _tokens.length; i++) {
            approvedTokens.push(Token(_tokens[i], _stakes[i]));
            require(_isValidToken(approvedTokens[i], _tokens, i + 1));
        }
        oathFactory = new OathFactory(Governance(this));
    }

    function findToken(address _address)
        public
        view
        returns (
            uint256,
            address,
            uint256
        )
    {
        for (uint256 i = 0; i < approvedTokens.length; i++) {
            if (approvedTokens[i].address_ == _address) {
                return (
                    i,
                    approvedTokens[i].address_,
                    approvedTokens[i].minStake
                );
            }
        }
        return (0, address(0), 0);
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

    function elect(address _delegate, uint256 amount) public returns (bool) {
        require(amount != 0);
        delegateVotes[msg.sender][_delegate] = amount;
        emit Elected(msg.sender, _delegate, amount);
        return true;
    }

    function recall(address _delegate, uint256 amount) public returns (bool) {
        require(amount <= delegateVotes[msg.sender][_delegate]);
        delegateVotes[msg.sender][_delegate] -= amount;
        emit Recalled(msg.sender, _delegate, amount);
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

    function castVote(
        address _from,
        bytes32 _id,
        uint256 _amount,
        uint256 _index
    ) public returns (bool) {
        require(_amount >= minProvision && balances[_from] >= _amount);
        if (_from != msg.sender) {
            require(delegateVotes[_from][msg.sender] >= _amount);
            delegateVotes[_from][msg.sender] -= _amount;
        }
        balances[_from] -= _amount;
        votingPools[_id].liquidity += _amount;
        if (_index != 0) {
            require(
                _index <= votingPools[_id].providers.length &&
                    votingPools[_id].providers[_index - 1].account == _from
            );
            votingPools[_id].providers[_index - 1].amount += _amount;
        } else {
            uint256 length = votingPools[_id].lanes.length;
            if (length == 0) {
                votingPools[_id].providers.push(
                    Provider(_from, msg.sender, _amount)
                );
            } else {
                votingPools[_id].providers[
                    votingPools[_id].lanes[0]
                ] = Provider(_from, msg.sender, _amount);
                votingPools[_id].lanes[0] = votingPools[_id].lanes[length - 1];
                votingPools[_id].lanes.pop();
            }
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
        provider.amount -= _amount;
        votingPools[_id].liquidity -= _amount;
        balances[provider.account] += _amount;
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
            rates = Rates(uint8(_num1), uint8(_num2));
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
        (, , uint256 minStake) = oathGov.findToken(_token);
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
