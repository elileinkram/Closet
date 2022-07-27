// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

contract Closet {
    struct Safe {
        bool mounted;
        uint256 amount;
        uint256 timelock;
        uint256 reward;
        address owner;
        address thief;
    }

    struct ByteConstraints {
        uint8 min;
        uint8 max;
    }

    struct LockConstraints {
        uint256 min;
        uint256 max;
    }

    struct Rates {
        uint16 take;
        uint16 burn;
    }

    uint64 minStake;

    ByteConstraints byteConstraints;

    LockConstraints lockConstraints;

    Rates rates;

    mapping(bytes32 => Safe) public safes;

    mapping(address => uint256) balances;

    constructor(
        uint8 _minBytes,
        uint8 _maxBytes,
        uint256 _minLockupPeriod,
        uint256 _maxLockupPeriod,
        uint16 _takeRate,
        uint16 _burnRate,
        uint64 _minStake
    )
        checkConstraints(
            _minBytes,
            _maxBytes,
            _minLockupPeriod,
            _maxLockupPeriod
        )
        checkRates(_takeRate, _burnRate)
        onlyPositive(
            _minBytes,
            _minLockupPeriod,
            _takeRate,
            _burnRate,
            _minStake
        )
    {
        byteConstraints = ByteConstraints(_minBytes, _maxBytes);
        lockConstraints = LockConstraints(_minLockupPeriod, _maxLockupPeriod);
        rates = Rates(_takeRate, _burnRate);
        minStake = _minStake;
    }

    event Mounted(address indexed _owner, bytes32 _hash);

    event Cracked(bytes32 indexed _hash, string _secret);

    event Unmounted(bytes32 indexed _hash);

    event Redeemed(address indexed _address, uint256 _amount);

    modifier onlyPositive(
        uint8 _minBytes,
        uint256 _minLockupPeriod,
        uint16 _takeRate,
        uint16 _burnRate,
        uint64 _minStake
    ) {
        require(
            _minBytes != 0 &&
                _minLockupPeriod != 0 &&
                _takeRate != 0 &&
                _burnRate != 0 &&
                _minStake != 0,
            "Invalid input parameters"
        );
        _;
    }

    modifier checkConstraints(
        uint8 _minBytes,
        uint8 _maxBytes,
        uint256 _minLockupPeriod,
        uint256 _maxLockupPeriod
    ) {
        require(
            _maxBytes > _minBytes && _maxLockupPeriod > _minLockupPeriod,
            "Invalid constraints"
        );
        _;
    }

    modifier checkRates(uint16 _takeRate, uint16 _burnRate) {
        require(_takeRate + _burnRate < type(uint16).max, "Invalid rates");
        _;
    }

    modifier fundingSecured(uint256 _amount) {
        require(
            _amount >= minStake && msg.value >= _amount,
            "Insufficient funds"
        );
        _;
    }

    modifier isLocked(uint256 _timelock) {
        require(_timelock > block.timestamp, "Unlocked safe");
        _;
    }

    modifier isUnlocked(uint256 _timelock) {
        require(block.timestamp >= _timelock, "Locked safe");
        _;
    }

    modifier isVacant(bytes32 _hash) {
        require(safes[_hash].reward == 0, "Safe taken");
        _;
    }

    modifier isMounted(Safe memory _safe) {
        require(_safe.mounted, "Unmounted safe");
        _;
    }

    modifier onlyOwner(address _owner) {
        require(_owner == msg.sender, "Unauthorized");
        _;
    }

    modifier inByteRange(string memory _secret) {
        uint256 byteSize = bytes(_secret).length;
        require(
            byteSize >= byteConstraints.min && byteSize <= byteConstraints.max,
            "Outside byte range"
        );
        _;
    }

    modifier inTimezone(uint256 _timelock) {
        uint256 period = _timelock - block.timestamp;
        require(
            period >= lockConstraints.min && period <= lockConstraints.max,
            "Outside time range"
        );
        _;
    }

    modifier validKey(string memory _secret, bytes32 _hash) {
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        require(hash == _hash, "Invalid secret or hash");
        _;
    }

    modifier redeemable(uint256 amount) {
        require(balances[msg.sender] >= amount, "Insufficient funds");
        _;
    }

    function _calculateReward(uint256 _amount) private view returns (uint256) {
        return
            _amount -
            (_amount * (rates.burn / (type(uint16).max))) -
            (_amount * (rates.take / type(uint16).max));
    }

    function hide(
        bytes32 _hash,
        uint256 _amount,
        uint256 _timelock
    ) public payable fundingSecured(_amount) {
        uint256 reward = _calculateReward(_amount);
        _mount(_hash, _amount, _timelock, reward);
    }

    function _mount(
        bytes32 _hash,
        uint256 _amount,
        uint256 _timelock,
        uint256 _reward
    ) private isVacant(_hash) inTimezone(_timelock) {
        safes[_hash] = Safe(
            true,
            _amount,
            _timelock,
            _reward,
            msg.sender,
            address(0)
        );
        balances[msg.sender] += (msg.value - _amount);
        emit Mounted(msg.sender, _hash);
    }

    function crack(string memory _secret) public {
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        Safe storage safe = safes[hash];
        _loot(_secret, hash, safe);
    }

    function _loot(
        string memory _secret,
        bytes32 _hash,
        Safe storage safe
    ) private isMounted(safe) isLocked(safe.timelock) {
        safe.mounted = false;
        safe.thief = msg.sender;
        balances[msg.sender] += safe.reward;
        emit Cracked(_hash, _secret);
        emit Unmounted(_hash);
    }

    function reveal(string memory _secret, bytes32 _hash)
        public
        inByteRange(_secret)
        validKey(_secret, _hash)
        returns (string memory)
    {
        Safe storage safe = safes[_hash];
        return _dismount(_secret, _hash, safe);
    }

    function _dismount(
        string memory _secret,
        bytes32 _hash,
        Safe storage safe
    )
        private
        onlyOwner(safe.owner)
        isMounted(safe)
        isUnlocked(safe.timelock)
        returns (string memory)
    {
        safe.mounted = false;
        balances[safe.owner] += safe.amount;
        emit Unmounted(_hash);
        return _secret;
    }

    function withdraw(uint256 amount) public payable redeemable(amount) {
        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Redeemed(msg.sender, amount);
    }

    function checkBalance() public view returns (uint256) {
        return balances[msg.sender];
    }
}
