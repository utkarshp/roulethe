pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {Rouleth} from "contracts/Rouleth.sol";

contract RoulethTest is Test {
    Rouleth wheel;
    
    event Log(string message);

    function setUp() public {
	//	emit Log("Initing new contract");
	wheel = new Rouleth();
    }

    function makeBet(uint256 bet, uint256 amt) internal {
	bytes32 commitHash = keccak256(abi.encodePacked(uint256(1654), "hi"));
	bytes memory data = abi.encodeWithSignature("placeBet(uint256,bytes32)", bet, commitHash);
	(bool success, ) = address(wheel).call{value: amt}(data);
	require(success);
    }

    function test_transferAmountTo() public {
	vm.expectRevert(bytes("Only the house can call this function"));
	vm.prank(address(0));
	wheel.transferAmountTo(1, payable(address(1)));
	
	vm.expectRevert(bytes("Insufficient funds"));
	wheel.transferAmountTo(2, payable(address(2)));

	makeBet(wheel.encodeNumberBet(1, 10 gwei), 10 gwei);
	vm.expectRevert(bytes("Transfer would make payouts impossible"));
	wheel.transferAmountTo(1, payable(address(3)));

	vm.prank(address(1));
	makeBet(wheel.encodeColorBet(2, 350 gwei), 350 gwei);
	(bool success, ) = address(wheel).call{value: 1000 gwei}("");
	require(success);
	address payable recipient = payable(address(4));
	uint256 initBal = recipient.balance;
	wheel.transferAmountTo(3, payable(address(4)));
	assertEq(recipient.balance, initBal + 3);
    }

    function test_setBettingState() public {
	vm.expectRevert(bytes("Only the house can call this function"));
	vm.prank(address(0));
	wheel.setBettingState(false);
	
	wheel.setBettingState(false);
	uint256 bet = wheel.encodeNumberBet(1, 10 gwei);
	vm.expectRevert(bytes("Not open for bets"));
	makeBet(bet, 10 gwei);

	wheel.setBettingState(true);
	makeBet(bet, 10 gwei);
    }

    function test_setPayoutLimit() public {
	vm.expectRevert(bytes("Only the house can call this function"));
	vm.prank(address(0));
	wheel.setPayoutLimit(1 ether);

	wheel.setPayoutLimit(1 ether);
	uint256 bet = wheel.encodeNumberBet(1, uint256(1 ether) / 37);
	makeBet(bet, uint256(1 ether)/37);

	wheel.setPayoutLimit(0.1 ether);
	vm.expectRevert(bytes("Number bet payout exceeds current limit"));
	makeBet(bet, uint256(1 ether) / 37);
    }

    function getAllBets() public view returns (uint256[][] memory,
					  uint256[][] memory,
					  uint256[][] memory,
					  uint256[][] memory, uint256[][] memory) {
        uint256[2][39] memory numberBets;
	uint256[2][4] memory dozenBets;
        uint256[2][3] memory colorBets;
        uint256[2][3] memory halfBets;
        uint256[2][3] memory parityBets;

	for (uint256 i=0;i<39;i++) {
	    numberBets[i][0] = wheel.encodeNumberBet(i+1, uint256(0.1 ether) / 36);
	    numberBets[i][1] = uint256(0.1 ether) / 36;
	}

	for (uint256 i=0; i<4; i++) {
	    dozenBets[i][0] = wheel.encodeNumberBet(i+1, uint256(0.1 ether) / 3);
	    dozenBets[i][1] = uint256(0.1 ether) / 3;
	}

	for (uint256 i=0; i<3; i++) {
	    colorBets[i][0] = wheel.encodeColorBet(i+1, uint256(0.1 ether) / 2);
	    colorBets[i][1] = uint256(0.1 ether) / 2;	    
	}

	for (uint256 i=0; i<3; i++) {
	    halfBets[i][0] = wheel.encodeHalfBet(i+1, uint256(0.1 ether) / 2);
	    halfBets[i][1] = uint256(0.1 ether) / 2;
	}

	for (uint256 i=0; i<3; i++) {
	    parityBets[i][0] = wheel.encodeParityBet(i+1, uint256(0.1 ether) / 2);
	    parityBets[i][1] = uint256(0.1 ether) / 2;
	}
    }

    function test_betting() public {
	(bool success, ) = address(wheel).call{value: 1 ether}("");
	require(success);

	vm.expectRevert(bytes("No bets available"));
	wheel.spin();

	vm.expectRevert(bytes("Not spinning"));
	wheel.cashout(uint256(1654), "hi");

	uint256 maxBettors = 100;
	uint256 bettorsSoFar = 0;
	uint256[][][] memory arrayOfArrays = new uint256[][][](5);

	(uint256[][] memory numBets, uint256[][] memory dozenBets, uint256[][] memory colorBets,
	 uint256[][] memory halfBets, uint256[][] memory parityBets) = getAllBets();
	arrayOfArrays[0] = numBets;
	arrayOfArrays[1] = dozenBets;
	arrayOfArrays[2] = colorBets;
	arrayOfArrays[3] = halfBets;
	arrayOfArrays[4] = parityBets;

	// TODO: Implement different combinations of possible
	// bets and test spin and cashout functions.
    }
}