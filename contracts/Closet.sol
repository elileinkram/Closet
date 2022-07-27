// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

contract Closet {
    struct Safe {
        bool mounted;
        uint256 stake;
        uint256 expiry;
        uint256 reward;
        address owner;
        address thief;
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

    uint64 public minStake;

    ByteConstraints public byteConstraints;

    PeriodConstraints public periodConstraints;

    Rates public rates;

    mapping(bytes32 => Safe) public safes;

    mapping(address => uint256) public balances;

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
        periodConstraints = PeriodConstraints(
            _minLockupPeriod,
            _maxLockupPeriod
        );
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

    modifier fundingSecured(uint256 _stake) {
        require(
            _stake >= minStake && msg.value >= _stake,
            "Insufficient funds"
        );
        _;
    }

    modifier isLocked(uint256 _expiry) {
        require(_expiry > block.timestamp, "Unlocked safe");
        _;
    }

    modifier isUnlocked(uint256 _expiry) {
        require(block.timestamp >= _expiry, "Locked safe");
        _;
    }

    modifier isOwnerless(bytes32 _hash) {
        require(safes[_hash].owner == address(0), "Safe taken");
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

    modifier checkTimeFrame(uint256 _expiry) {
        uint256 period = _expiry - block.timestamp;
        require(
            period >= periodConstraints.min && period <= periodConstraints.max,
            "Outside time range"
        );
        _;
    }

    modifier checkPassword(string memory _secret, bytes32 _hash) {
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        require(hash == _hash, "Invalid secret or hash");
        _;
    }

    modifier redeemable(uint256 amount) {
        require(balances[msg.sender] >= amount, "Insufficient funds");
        _;
    }

    function _calculateReward(uint256 _stake) private view returns (uint256) {
        return
            _stake -
            (_stake * (rates.burn / (type(uint16).max))) -
            (_stake * (rates.take / type(uint16).max));
    }

    function hide(
        bytes32 _hash,
        uint256 _stake,
        uint256 _expiry
    ) public payable fundingSecured(_stake) {
        uint256 reward = _calculateReward(_stake);
        _mount(_hash, _stake, _expiry, reward);
    }

    function _mount(
        bytes32 _hash,
        uint256 _stake,
        uint256 _expiry,
        uint256 _reward
    ) private isOwnerless(_hash) checkTimeFrame(_expiry) {
        safes[_hash] = Safe(
            true,
            _stake,
            _expiry,
            _reward,
            msg.sender,
            address(0)
        );
        balances[msg.sender] += (msg.value - _stake);
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
    ) private isMounted(safe) isLocked(safe.expiry) {
        safe.mounted = false;
        safe.thief = msg.sender;
        balances[msg.sender] += safe.reward;
        emit Cracked(_hash, _secret);
        emit Unmounted(_hash);
    }

    function reveal(string memory _secret, bytes32 _hash)
        public
        inByteRange(_secret)
        checkPassword(_secret, _hash)
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
        isUnlocked(safe.expiry)
        returns (string memory)
    {
        safe.mounted = false;
        balances[safe.owner] += safe.stake;
        emit Unmounted(_hash);
        return _secret;
    }

    function withdraw(uint256 _amount) public payable redeemable(_amount) {
        balances[msg.sender] -= _amount;
        payable(msg.sender).transfer(_amount);
        emit Redeemed(msg.sender, _amount);
    }
}
