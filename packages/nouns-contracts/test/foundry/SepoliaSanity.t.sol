// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import { NounsToken } from '../../contracts/NounsToken.sol';
import { INounsDAOLogic } from '../../contracts/interfaces/INounsDAOLogic.sol';
import { INounsAuctionHouseV2 } from '../../contracts/interfaces/INounsAuctionHouseV2.sol';
import { DeployEverything } from '../../script/DeployEverything.s.sol';
import { NounsDAOTypes } from '../../contracts/governance/NounsDAOInterfaces.sol';

abstract contract SepoliaForkBaseTest is Test {
    DeployEverything.Contracts deployedContracts;
    NounsToken public nouns;
    INounsAuctionHouseV2 auctionHouse;
    INounsDAOLogic gov;

    address proposerAddr = vm.addr(0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb);
    address origin = makeAddr('origin');
    address newLogic;

    address[] targets;
    uint256[] values;
    string[] signatures;
    bytes[] calldatas;

    uint256[] proposerTokenIds;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString('RPC_SEPOLIA'), 5538777);
        vm.fee(50 gwei);
        vm.txGasPrice(50 gwei);

        // Deploy the latest DAO logic
        vm.setEnv('DEPLOYER_PRIVATE_KEY', '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
        deployedContracts = new DeployEverything().run();

        nouns = deployedContracts.nouns;
        auctionHouse = deployedContracts.ahProxy;
        gov = deployedContracts.govProxy;

        // Get votes
        for (uint256 i = 0; i < 3; i++) {
            proposerTokenIds.push(bidAndSettleAuction(proposerAddr));
        }
    }

    function setProposalTx(address target, uint256 value, string memory signature, bytes memory data) internal {
        address[] memory targets_ = new address[](1);
        targets_[0] = target;
        uint256[] memory values_ = new uint256[](1);
        values_[0] = value;
        string[] memory signatures_ = new string[](1);
        signatures_[0] = signature;
        bytes[] memory calldatas_ = new bytes[](1);
        calldatas_[0] = data;

        targets = targets_;
        values = values_;
        signatures = signatures_;
        calldatas = calldatas_;
    }

    function propose() internal returns (uint256 proposalId) {
        return propose(0);
    }

    function propose(uint32 clientId) internal returns (uint256 proposalId) {
        vm.prank(proposerAddr);
        proposalId = gov.propose(proposerTokenIds, targets, values, signatures, calldatas, 'my proposal', clientId);
    }

    function voteAndExecuteProposal(uint256 propId) internal {
        NounsDAOTypes.ProposalCondensedV3 memory propInfo = gov.proposalsV3(propId);

        vm.roll(propInfo.startBlock + 1);
        vm.prank(proposerAddr);
        gov.castRefundableVote(proposerTokenIds, propId, 1);

        vm.roll(propInfo.eta + 1);
        gov.execute(propId, targets, values, signatures, calldatas);
    }

    function bidAndSettleAuction(address buyer) internal returns (uint256 nounId) {
        INounsAuctionHouseV2.AuctionV2View memory auction = auctionHouse.auction();
        if (auction.endTime < block.timestamp) {
            auctionHouse.settleCurrentAndCreateNewAuction();
            auction = auctionHouse.auction();
        }

        vm.deal(buyer, buyer.balance + 0.1 ether);
        vm.startPrank(buyer);
        nounId = auction.nounId;
        auctionHouse.createBid{ value: 0.1 ether }(nounId);
        vm.warp(auction.endTime);
        auctionHouse.settleCurrentAndCreateNewAuction();
        vm.roll(block.number + 1);
        vm.stopPrank();
    }
}

contract SanitySepoliaForkTest is SepoliaForkBaseTest {
    address receiver = makeAddr('receiver');

    function setUp() public virtual override {
        super.setUp();
    }

    function test_propose_and_vote() public {
        setProposalTx(receiver, 0.1 ether, '', '');
        uint256 proposalId = propose();
        uint256 balanceBefore = receiver.balance;

        voteAndExecuteProposal(proposalId);

        assertEq(receiver.balance, balanceBefore + 0.1 ether);
    }
}
