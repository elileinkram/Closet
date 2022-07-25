// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

contract Closet {
    struct Safe {
        bool empty;
        uint256 amount;
        uint256 reward;
        uint256 maturity;
        address owner;
        address thief;
    }

    mapping(bytes32 => Safe) public safes;

    mapping(address => uint256) public balances;

    event Mounted(address indexed _owner, bytes32 _hash);

    event Cracked(bytes32 indexed _hash, string _secret);

    event Emptied(bytes32 indexed _hash);

    event Dismounted(bytes32 indexed _hash);

    event Redeemed(address indexed _address, uint256 _amount);

    function mount(
        bytes32 _hash,
        uint256 amount,
        uint256 maturity
    ) public payable {
        require(maturity > block.timestamp, "Expired maturity");
        uint256 surplus = msg.value - amount;
        require(surplus >= 0, "Insufficient funds");
        uint256 reward = amount / 2;
        require(reward > 0, "Insufficient funds");
        Safe memory safe = safes[_hash];
        require(safe.reward == 0, "Existing hash");
        balances[msg.sender] += surplus;
        safes[_hash] = Safe(
            false,
            amount,
            reward,
            maturity,
            msg.sender,
            address(0)
        );
        emit Mounted(msg.sender, _hash);
    }

    function crack(string memory _secret) public {
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        Safe storage safe = safes[hash];
        uint256 reward = safe.reward;
        require(reward != 0, "Invalid secret or address");
        uint256 maturity = safe.maturity;
        require(maturity > block.timestamp, "Expired maturity");
        bool empty = safe.empty;
        require(!empty, "Safe emptied");
        safe.empty = true;
        safe.thief = msg.sender;
        balances[msg.sender] += reward;
        emit Cracked(hash, _secret);
        emit Emptied(hash);
    }

    function dismount(string memory _secret, bytes32 _hash)
        public
        returns (string memory)
    {
        uint256 sbs = bytes(_secret).length;
        require(sbs >= 16 && sbs <= 32, "Invalid byte size");
        Safe storage safe = safes[_hash];
        uint256 maturity = safe.maturity;
        require(maturity <= block.timestamp, "Unexpired maturity");
        address owner = safe.owner;
        require(owner == msg.sender, "Unauthorized");
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        require(hash == _hash, "Invalid secret or hash");
        bool empty = safe.empty;
        require(!empty, "Safe emptied");
        uint256 amount = safe.amount;
        safe.empty = true;
        balances[owner] += amount;
        emit Emptied(_hash);
        emit Dismounted(_hash);
        return _secret;
    }

    function withdraw(uint256 amount) public payable {
        uint256 balance = balances[msg.sender];
        uint256 surplus = balance - amount;
        require(surplus >= 0, "Insufficient funds");
        balances[msg.sender] = surplus;
        payable(msg.sender).transfer(amount);
        emit Redeemed(msg.sender, amount);
    }
}
