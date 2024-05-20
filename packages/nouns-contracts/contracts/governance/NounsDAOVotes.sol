// SPDX-License-Identifier: GPL-3.0

/// @title Library for Nouns DAO Logic containing all the voting related code

/*********************************
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░██░░░████░░██░░░████░░░ *
 * ░░██████░░░████████░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 *********************************/

pragma solidity ^0.8.19;

import './NounsDAOInterfaces.sol';
import { NounsDAOProposals } from './NounsDAOProposals.sol';
import { SafeCast } from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import { VotingBitMaps } from './VotingBitMaps.sol';
import { NounsDAODelegation } from './NounsDAODelegation.sol';

library NounsDAOVotes {
    using NounsDAOProposals for NounsDAOTypes.Storage;
    using VotingBitMaps for BitMaps.BitMap;

    error CanOnlyVoteAgainstDuringObjectionPeriod();

    /// @notice An event emitted when a vote has been cast on a proposal
    /// @param voter The address which casted a vote
    /// @param proposalId The proposal id which was voted on
    /// @param support Support value for the vote. 0=against, 1=for, 2=abstain
    /// @param votes Number of votes which were cast by the voter
    /// @param reason The reason given for the vote by the voter
    event VoteCast(
        address indexed voter,
        uint256[] tokenIds,
        uint256 proposalId,
        uint8 support,
        uint256 votes,
        string reason
    );

    /// @notice Emitted when a voter cast a vote requesting a gas refund.
    event RefundableVote(address indexed voter, uint256 refundAmount, bool refundSent);

    /// @notice Emitted when a proposal is set to have an objection period
    event ProposalObjectionPeriodSet(uint256 indexed id, uint256 objectionPeriodEndBlock);

    /// @notice The name of this contract
    string public constant name = 'Nouns DAO';

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256('EIP712Domain(string name,uint256 chainId,address verifyingContract)');

    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256('Ballot(uint256 proposalId,uint8 support)');

    /// @notice The maximum priority fee used to cap gas refunds in `castRefundableVote`
    uint256 public constant MAX_REFUND_PRIORITY_FEE = 2 gwei;

    /// @notice The vote refund gas overhead, including 7K for ETH transfer and 29K for general transaction overhead
    uint256 public constant REFUND_BASE_GAS = 36000;

    /// @notice The maximum gas units the DAO will refund voters on; supports about 9,190 characters
    uint256 public constant MAX_REFUND_GAS_USED = 200_000;

    /// @notice The maximum basefee the DAO will refund voters on
    uint256 public constant MAX_REFUND_BASE_FEE = 200 gwei;

    function votingReceipt(
        NounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint256 tokenId
    ) external view returns (bool hasVoted, uint8 support) {
        return ds.votingReceipts[proposalId].getVoting(tokenId);
    }

    /**
     * @notice Cast a vote for a proposal, asking the DAO to refund gas costs.
     * Users with > 0 votes receive refunds. Refunds are partial when using a gas priority fee higher than the DAO's cap.
     * Refunds are partial when the DAO's balance is insufficient.
     * No refund is sent when the DAO's balance is empty. No refund is sent to users with no votes.
     * Voting takes place regardless of refund success.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param clientId The ID of the client that faciliated posting the vote onchain
     * @dev Reentrancy is defended against in `castVoteInternal` at the `receipt.hasVoted == false` require statement.
     */
    function castRefundableVote(
        NounsDAOTypes.Storage storage ds,
        uint256[] calldata tokenIds,
        uint256 proposalId,
        uint8 support,
        uint32 clientId
    ) external {
        castRefundableVoteInternal(ds, tokenIds, proposalId, support, '', clientId);
    }

    /**
     * @notice Cast a vote for a proposal, asking the DAO to refund gas costs.
     * Users with > 0 votes receive refunds. Refunds are partial when using a gas priority fee higher than the DAO's cap.
     * Refunds are partial when the DAO's balance is insufficient.
     * No refund is sent when the DAO's balance is empty. No refund is sent to users with no votes.
     * Voting takes place regardless of refund success.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @dev Reentrancy is defended against in `castVoteInternal` at the `receipt.hasVoted == false` require statement.
     */
    function castRefundableVoteWithReason(
        NounsDAOTypes.Storage storage ds,
        uint256[] calldata tokenIds,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        uint32 clientId
    ) external {
        castRefundableVoteInternal(ds, tokenIds, proposalId, support, reason, clientId);
    }

    /**
     * @notice Internal function that carries out refundable voting logic
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param clientId The ID of the client that faciliated posting the vote onchain
     * @dev Reentrancy is defended against in `castVoteInternal` at the `receipt.hasVoted == false` require statement.
     */
    function castRefundableVoteInternal(
        NounsDAOTypes.Storage storage ds,
        uint256[] calldata tokenIds,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        uint32 clientId
    ) internal {
        uint256 startGas = gasleft();
        castVoteInternal(ds, tokenIds, proposalId, support, clientId);
        emit VoteCast(msg.sender, tokenIds, proposalId, support, tokenIds.length, reason);
        if (clientId > 0) emit NounsDAOEventsV3.VoteCastWithClientId(msg.sender, proposalId, clientId);
        if (tokenIds.length > 0) {
            _refundGas(startGas);
        }
    }

    /**
     * @notice Internal function that caries out voting logic
     * In case of a vote during the 'last minute window', which changes the proposal outcome from being defeated to
     * passing, and objection period is adding to the proposal's voting period.
     * During the objection period, only votes against a proposal can be cast.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param clientId The ID of the client that faciliated posting the vote onchain
     */
    function castVoteInternal(
        NounsDAOTypes.Storage storage ds,
        uint256[] calldata tokenIds,
        uint256 proposalId,
        uint8 support,
        uint32 clientId
    ) internal {
        NounsDAOTypes.ProposalState proposalState = ds.stateInternal(proposalId);
        NounsDAOTypes.Proposal storage proposal = ds._proposals[proposalId];
        require(
            NounsDAODelegation.isDelegate(msg.sender, tokenIds, proposal.startBlock),
            'msg.sender is not the delegate of provided tokenIds'
        );

        if (proposalState == NounsDAOTypes.ProposalState.Active) {
            castVoteDuringVotingPeriodInternal(ds, proposalId, tokenIds, support);
        } else if (proposalState == NounsDAOTypes.ProposalState.ObjectionPeriod) {
            if (support != 0) revert CanOnlyVoteAgainstDuringObjectionPeriod();
            castObjectionInternal(ds, proposalId, tokenIds);
        } else {
            revert('NounsDAO::castVoteInternal: voting is closed');
        }

        NounsDAOTypes.ClientVoteData memory voteData = ds._proposals[proposalId].voteClients[clientId];
        ds._proposals[proposalId].voteClients[clientId] = NounsDAOTypes.ClientVoteData({
            votes: uint32(voteData.votes + tokenIds.length),
            txs: voteData.txs + 1
        });
    }

    /**
     * @notice Internal function that handles voting logic during the voting period.
     * @dev Assumes it's only called by `castVoteInternal` which ensures the proposal is active.
     * @param proposalId The id of the proposal being voted on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function castVoteDuringVotingPeriodInternal(
        NounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint256[] calldata tokenIds,
        uint8 support
    ) internal {
        require(support <= 2, 'NounsDAO::castVoteDuringVotingPeriodInternal: invalid vote type');
        if (tokenIds.length == 0) return;
        NounsDAOTypes.Proposal storage proposal = ds._proposals[proposalId];
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (bool hasVoted, ) = ds.votingReceipts[proposalId].getVoting(tokenIds[i]);
            require(!hasVoted, 'NounsDAO::castVoteDuringVotingPeriodInternal: token already voted');

            ds.votingReceipts[proposalId].setVoting(tokenIds[i], support);
        }

        bool isForVoteInLastMinuteWindow = false;
        if (support == 1) {
            isForVoteInLastMinuteWindow = (proposal.endBlock - block.number < ds.lastMinuteWindowInBlocks);
        }

        bool isDefeatedBefore = false;
        if (isForVoteInLastMinuteWindow) isDefeatedBefore = ds.isDefeated(proposal);

        if (support == 0) {
            proposal.againstVotes = proposal.againstVotes + tokenIds.length;
        } else if (support == 1) {
            proposal.forVotes = proposal.forVotes + tokenIds.length;
        } else if (support == 2) {
            proposal.abstainVotes = proposal.abstainVotes + tokenIds.length;
        }

        if (
            // only for votes can trigger an objection period
            // we're in the last minute window
            isForVoteInLastMinuteWindow &&
            // first part of the vote flip check
            // separated from the second part to optimize gas
            isDefeatedBefore &&
            // haven't turn on objection yet
            proposal.objectionPeriodEndBlock == 0 &&
            // second part of the vote flip check
            !ds.isDefeated(proposal)
        ) {
            proposal.objectionPeriodEndBlock = SafeCast.toUint64(
                proposal.endBlock + ds.objectionPeriodDurationInBlocks
            );

            emit ProposalObjectionPeriodSet(proposal.id, proposal.objectionPeriodEndBlock);
        }
    }

    /**
     * @notice Internal function that handles against votes during an objection period.
     * @dev Assumes it's being called by `castVoteInternal` which ensures:
     * 1. The proposal is in the objection period state.
     * 2. The vote is an against vote.
     * @param proposalId The id of the proposal being voted on
     */
    function castObjectionInternal(
        NounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint256[] calldata tokenIds
    ) internal {
        NounsDAOTypes.Proposal storage proposal = ds._proposals[proposalId];
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (bool hasVoted, ) = ds.votingReceipts[proposalId].getVoting(tokenIds[i]);
            require(!hasVoted, 'already voted');

            ds.votingReceipts[proposalId].setVoting(tokenIds[i], 0);
        }

        proposal.againstVotes = proposal.againstVotes + tokenIds.length;
    }

    function _refundGas(uint256 startGas) internal {
        unchecked {
            uint256 balance = address(this).balance;
            if (balance == 0) {
                return;
            }
            uint256 basefee = min(block.basefee, MAX_REFUND_BASE_FEE);
            uint256 gasPrice = min(tx.gasprice, basefee + MAX_REFUND_PRIORITY_FEE);
            uint256 gasUsed = min(startGas - gasleft() + REFUND_BASE_GAS, MAX_REFUND_GAS_USED);
            uint256 refundAmount = min(gasPrice * gasUsed, balance);
            (bool refundSent, ) = tx.origin.call{ value: refundAmount }('');
            emit RefundableVote(tx.origin, refundAmount, refundSent);
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
