// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

contract Rouleth {
    uint8 private constant CASHOUT_REWARD_PERCENT = 5;
    
    uint8 private constant RESULT_MAX = 38;
    uint8 private constant SPIN_BLOCK_DIFF = 4;

    uint256 private constant BET_AMOUNT_MASK = 0xFFFFFFFFF; // Each bet+amount is encoded in 36 bits.
    uint256 private constant AMOUNT_MASK = 0xFFFFFFF; // Amount for each bet+amount is the last 28 bits of the 36 bits.

    uint8 private constant AMOUNT_SHIFT = 28;
    uint8 private constant NUMBER_SHIFT = 220;
    uint8 private constant DOZEN_SHIFT = 184;
    uint8 private constant COLOR_SHIFT = 148;
    uint8 private constant HALF_SHIFT = 112;
    uint8 private constant PARITY_SHIFT = 76;

    uint256 private constant NUMBER_MULT = 36;
    uint256 private constant DOZEN_MULT = 3;
    uint256 private constant COLOR_MULT = 2;
    uint256 private constant HALF_MULT = 2;
    uint256 private constant PARITY_MULT = 2;

    uint8[18][2] private COLORED_NUMBERS;

    bool openForBets;
    bool spinning;
    uint256 thisRoundAmount;
    uint256 spinBlockNum;
    uint256 private singleBetMaxPayout;
    
    address public house;
    address[] public bettors;
    
    mapping(address => uint) public userBets;
    mapping(address => uint) public userBetAmounts;
    mapping(uint => uint) public potentialPayouts;

    mapping(address => bytes32) private commits;
    
    event Bet(address from, uint betmask);
    event Log(string message, uint256 value);

    constructor() {
	house = msg.sender;
	openForBets = true;
	spinning = false;
	thisRoundAmount = 0;
	singleBetMaxPayout = 0.1 ether;

	uint8[18] memory RED_NUMBERS = [
            1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36
        ];
        
        uint8[18] memory BLACK_NUMBERS = [
            2, 4, 6, 8, 10, 11, 13, 15, 17, 20, 22, 24, 26, 28, 29, 31, 33, 35
        ];

        for (uint8 i = 0; i < 18; i++) {
            COLORED_NUMBERS[0][i] = RED_NUMBERS[i];
            COLORED_NUMBERS[1][i] = BLACK_NUMBERS[i];
        }
	
    }

    modifier onlyHouse() {
	require(msg.sender == house, "Only the house can call this function");
	_;
    }

    receive() external payable {}

    function transferAmountTo(uint256 amount, address payable _to) public onlyHouse {
	require(address(this).balance >= amount, "Insufficient funds");
	_to.transfer(amount);
	require(spinnable(), "Transfer would make payouts impossible");
    }

    function setBettingState(bool bettingAllowed) public onlyHouse {
	openForBets = bettingAllowed;
    }

    function setPayoutLimit(uint256 newLimit) public onlyHouse {
	singleBetMaxPayout = newLimit;
    }

    function decodeBet(uint256 bet, uint8 shift) internal pure returns (uint256 betval,
									uint256 amount) {
	uint256 betAmount = (bet >> shift) & BET_AMOUNT_MASK;
	betval = (betAmount >> AMOUNT_SHIFT);
	amount = (betAmount & AMOUNT_MASK) * 1 gwei;
    }

    function encodeBet(uint256 val, uint256 amount, uint8 shift)
	internal pure returns (uint256 bet) {
	return ((val << AMOUNT_SHIFT) | (amount / 1 gwei)) << shift;
    }

    function encodeNumberBet(uint256 num, uint256 amount) public pure returns (uint256 bet) {
	return encodeBet(num, amount, NUMBER_SHIFT);
    }

    function encodeDozenBet(uint256 dozenBet, uint256 amount) public pure returns (uint256 bet) {
	return encodeBet(dozenBet, amount, DOZEN_SHIFT);
    }

    function encodeColorBet(uint256 colorBet, uint256 amount) public pure returns (uint256 bet) {
	return encodeBet(colorBet, amount, COLOR_SHIFT);
    }
    
    function encodeHalfBet(uint256 halfBet, uint256 amount) public pure returns (uint256 bet) {
	return encodeBet(halfBet, amount, HALF_SHIFT);
    }
    
    function encodeParityBet(uint256 parityBet, uint256 amount) public pure returns (uint256 bet)
    {
	return encodeBet(parityBet, amount, PARITY_SHIFT);
    }

    function isRed(uint8 number) public pure returns (bool) {
        require(number >= 1 && number <= 36, "Invalid number");

        if (number <= 10 || (number >= 19 && number <= 28)) {
            // Segments where red starts with odds
            return (number % 2 != 0);
        } else {
            // Segments where black starts with odds
            return (number % 2 == 0);
        }
    }

    function spinnable() public view returns (bool) {
	uint256 maxPayout = 0;
 
	for (uint256 i=1; i<=RESULT_MAX; i++) {
	    if (potentialPayouts[i] > maxPayout) {
		maxPayout = potentialPayouts[i];
	    }
	}
	
	return maxPayout * (1 + CASHOUT_REWARD_PERCENT / 100) <= address(this).balance;
    }

    function spin() public {
	require(!spinning, "Already spinning");
	require(thisRoundAmount > 0, "No bets available");
	require(spinnable(), "Not enough funds to cover the bets");
	openForBets = false;
	spinning = true;
	spinBlockNum = block.number;
    }

    function cashout(uint256 secret, string memory salt) public {
	require(spinning, "Not spinning");
	require(block.number > spinBlockNum + SPIN_BLOCK_DIFF, "Spin too recent");

	// TODO: Explore enforcing more than one commits and a quorum requirement
	// for a successful cashout.
	require(keccak256(abi.encodePacked(secret, salt)) == commits[msg.sender],
		"Invalid reveal");

	uint8 outcome = uint8(determineOutcome(secret));
	uint256 payouts = redistributeBalances(outcome);
	readyForNextRound();
	
	// Pay the caller the cashout reward.
	payable(msg.sender).transfer(payouts * CASHOUT_REWARD_PERCENT / 100);
    }

    function readyForNextRound() internal {
	spinning = false;
	openForBets = true;
	for (uint256 i=1; i<=RESULT_MAX; i++) {
	    potentialPayouts[i] = 0;
	}
    }

    function determineOutcome(uint256 secret) private view returns (uint256) {
        bytes32 combinedHash;
        for (uint i = 1; i <= 4; i++) {
            combinedHash = keccak256(abi.encodePacked(combinedHash, blockhash(spinBlockNum + i)));
        }
        return uint256(keccak256(abi.encodePacked(combinedHash, secret))) % RESULT_MAX + 1; 
    }

    function calculatePayout(uint256 bet, uint8 outcome) public pure returns (uint256 payout) {
	payout = 0;
	(uint256 numberBet, uint256 numberBetAmount) = decodeBet(bet, NUMBER_SHIFT);
	if (outcome == numberBet) {
	    payout += numberBetAmount * NUMBER_MULT;
	}
	
	(uint256 dozenBetAmount, uint256 dozenBet)  = decodeBet(bet, DOZEN_SHIFT);
	if (outcome/12 + 1 == dozenBet) {
	    payout += dozenBetAmount * DOZEN_MULT;
	}
	
	(uint256 colorBetAmount, uint256 colorBet) = decodeBet(bet, COLOR_SHIFT);
	if ((colorBet==1 && isRed(outcome)) || (colorBet==2 && !isRed(outcome))) {
	    payout += colorBetAmount * COLOR_MULT;
	}
	
	(uint256 halfBetAmount, uint256 halfBet) = decodeBet(bet, HALF_SHIFT);
	if (halfBet/18 + 1 == halfBet) {
	    payout += halfBetAmount * HALF_MULT;
	}
	
	(uint256 parityBetAmount, uint256 parityBet) = decodeBet(bet, PARITY_SHIFT);
	if (parityBet % 2 == outcome % 2) {
	    payout += parityBetAmount * PARITY_MULT;
	}
    }

    function redistributeBalances(uint8 outcome) private returns (uint256 houseEarnings) {
        uint256 totalPayout = 0;
        address[] memory winningBettors = new address[](bettors.length);
        uint256 winningBettorCount = 0;

        for (uint i = 0; i < bettors.length; i++) {
            address bettor = bettors[i];
            uint256 bet = userBets[bettor];
	    if (bet == 0) {
		continue;  // This bettor did not do anything this round. Preserve their balance.
	    }

            uint256 payout = calculatePayout(bet, outcome);
	    userBetAmounts[bettor] = payout;
	    userBets[bettor] = 0;
            if (payout > 0) {
                totalPayout += payout;
                winningBettors[winningBettorCount] = bettor;
                winningBettorCount++;
            }
        }

        // Resize the winningBettors array and update the main bettors array
        bettors = new address[](winningBettorCount);
        for (uint i = 0; i < winningBettorCount; i++) {
            bettors[i] = winningBettors[i];
        }

        houseEarnings = thisRoundAmount - totalPayout;
	thisRoundAmount = 0;
        return houseEarnings;
    }

    function placeBet(uint256 bet, bytes32 commitHash) public payable {
	require(openForBets, "Not open for bets");

	uint256 totalBetAmount = 0;

	// Decode number bet
	(uint256 numberBet, uint256 numberBetAmount) = decodeBet(bet, NUMBER_SHIFT);
	if (numberBetAmount > 0) {
	    require(numberBet >= 1 && numberBet <= RESULT_MAX, "Invalid number bet");
	    uint payout = numberBetAmount * NUMBER_MULT;
	    require(payout <= singleBetMaxPayout, "Number bet payout exceeds current limit");
	    potentialPayouts[numberBet] += payout;
	    totalBetAmount += numberBetAmount;
	}
	
	// Decode dozen bet
	(uint256 dozenBet, uint256 dozenBetAmount)  = decodeBet(bet, DOZEN_SHIFT);
	if (dozenBetAmount > 0) {
	    require(dozenBet >=1 && dozenBet <= 3, "Invalid dozen bet");
	    uint payout = dozenBetAmount * DOZEN_MULT;
	    require(payout <= singleBetMaxPayout, "Dozen bet payout exceeds current limit");
	    for (uint256 i=(dozenBet-1)*12+1; i<=dozenBet*12; i++) {
		potentialPayouts[i] += payout;
	    }
	    totalBetAmount += dozenBetAmount;
	}

	// Decode color bet
	(uint256 colorBet, uint256 colorBetAmount) = decodeBet(bet, COLOR_SHIFT);
	if (colorBetAmount > 0) {
	    // 1 for red, 2 for black.
	    require(colorBet == 1 || colorBet == 2, "Invalid color bet");  
	    uint payout = colorBetAmount * COLOR_MULT;
	    require(payout <= singleBetMaxPayout, "Color bet payout exceeds current limit");
	    for (uint256 i=0; i<18; i++) {
		potentialPayouts[COLORED_NUMBERS[(colorBet-1)][i]] += payout;
	    }
	    totalBetAmount += colorBetAmount;
	}

	// Decode half bet
	(uint256 halfBet, uint256 halfBetAmount) = decodeBet(bet, HALF_SHIFT);
	if (halfBetAmount > 0) {
	    require(halfBet==1 || halfBet==2, "Invalid half bet");
	    uint payout = halfBetAmount * HALF_MULT;
	    require(payout <= singleBetMaxPayout, "Half bet payout exceeds current limit");
	    for (uint256 i=(halfBet-1)*18+1; i<=halfBet*18; i++) {
		potentialPayouts[i] += payout;
	    }
	    totalBetAmount += halfBetAmount;
	}

	// Decode parity bet
	(uint256 parityBet, uint256 parityBetAmount) = decodeBet(bet, PARITY_SHIFT);
	if (parityBetAmount > 0) {
	    // 1 for odd, 2 for even.
	    require(parityBet==1 || parityBet==2, "Invalid parity bet"); 
	    uint payout = parityBetAmount * PARITY_MULT;
	    require(payout <= singleBetMaxPayout, "Parity bet payout exceeds current limit");
	    for (uint256 i=0; i<=17; i++) {
		potentialPayouts[2*i+parityBet] += payout;
	    }
	    totalBetAmount += parityBetAmount;
	}

	// Housekeeping
	if (userBetAmounts[msg.sender] > 0) {
	    uint256 alreadyPresent = userBetAmounts[msg.sender];
	    if (totalBetAmount < alreadyPresent) {
		uint256 amountToSend = alreadyPresent - totalBetAmount;
		// This should never happen.
		require(address(this).balance >= amountToSend,
			"Contract does not have enough funds to refund"); 
		userBetAmounts[msg.sender] = msg.value;	
		payable(msg.sender).transfer(amountToSend);
	    }
	    else {
		uint256 needAmount = totalBetAmount - alreadyPresent;
		require(msg.value >= needAmount, "Sent ETH insufficient to cover the bet");
		userBetAmounts[msg.sender] = msg.value;	
	    }
	}
	else {
	    require(msg.value >= totalBetAmount, "Sent ETH must match the total bet amount");
	    bettors.push(msg.sender);
	    userBetAmounts[msg.sender] = msg.value;
	}
	
	userBets[msg.sender] = bet;
	thisRoundAmount += totalBetAmount;
	commits[msg.sender] = commitHash;

	//emit Bet(msg.sender, bet);
    }
}