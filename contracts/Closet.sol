// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

contract Closet {
    struct Chest {
        bool empty;
        uint256 amount;
        uint256 reward;
        uint256 maturity;
        address owner;
        address thief;
    }

    mapping(bytes32 => Chest) public chests;

    mapping(address => uint256) public balances;

    event Start(address indexed _owner, bytes32 _hash);

    event End(address indexed _owner, bytes32 indexed _hash);

    event Exposure(
        string _secret,
        address indexed _thief,
        address indexed _owner,
        bytes32 indexed _hash
    );

    event Redeemable(address indexed _owner, uint256 _amount);

    event Withdrawal(address indexed _address, uint256 _amount);

    function stake(
        bytes32 _hash,
        uint256 amount,
        uint256 maturity
    ) public payable {
        require(maturity > block.timestamp, "Expired maturity");
        uint256 surplus = msg.value - amount;
        require(surplus >= 0, "Insufficient funds");
        uint256 reward = amount / 2;
        require(reward > 0, "Insufficient funds");
        Chest memory chest = chests[_hash];
        require(chest.reward == 0, "Existing hash");
        balances[msg.sender] += surplus;
        chests[_hash] = Chest(
            false,
            amount,
            reward,
            maturity,
            msg.sender,
            address(0)
        );
        emit Start(msg.sender, _hash);
    }

    function loot(string memory _secret) public {
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        Chest storage chest = chests[hash];
        uint256 reward = chest.reward;
        require(reward != 0, "Invalid secret or address");
        uint256 maturity = chest.maturity;
        require(maturity > block.timestamp, "Expired maturity");
        bool empty = chest.empty;
        require(!empty, "Treasure stolen");
        chest.empty = true;
        chest.thief = msg.sender;
        balances[msg.sender] += reward;
        emit Exposure(_secret, msg.sender, chest.owner, hash);
        emit End(chest.owner, hash);
    }

    function redeem(string memory _secret, bytes32 _hash) public {
        uint256 sbs = bytes(_secret).length;
        require(sbs >= 16 && sbs <= 32, "Invalid byte size");
        Chest storage chest = chests[_hash];
        uint256 maturity = chest.maturity;
        require(maturity <= block.timestamp, "Unexpired maturity");
        address owner = chest.owner;
        require(owner == msg.sender, "Fraudulent owner");
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        require(hash == _hash, "Invalid secret or hash");
        bool empty = chest.empty;
        require(!empty, "Empty chest");
        uint256 amount = chest.amount;
        chest.empty = true;
        balances[owner] += amount;
        emit Redeemable(owner, amount);
        emit End(owner, _hash);
    }

    function withdraw(uint256 amount) public payable {
        uint256 balance = balances[msg.sender];
        uint256 surplus = balance - amount;
        require(surplus >= 0, "Insufficient funds");
        balances[msg.sender] = surplus;
        payable(msg.sender).transfer(amount);
        emit Withdrawal(msg.sender, amount);
    }
}
