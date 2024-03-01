// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import { INounsDAOLogic } from '../interfaces/INounsDAOLogic.sol';

contract MaliciousVoter {
    INounsDAOLogic public dao;
    uint256 public proposalId;
    uint8 public support;
    bool useReason;
    uint256[] tokenIds;

    constructor(INounsDAOLogic dao_, uint256 proposalId_, uint8 support_, bool useReason_, uint256[] memory tokenIds_) {
        dao = dao_;
        proposalId = proposalId_;
        support = support_;
        useReason = useReason_;
        tokenIds = tokenIds_;
    }

    function castVote() public {
        if (useReason) {
            dao.castRefundableVoteWithReason(tokenIds, proposalId, support, 'some reason');
        } else {
            dao.castRefundableVote(tokenIds, proposalId, support);
        }
    }

    receive() external payable {
        castVote();
    }
}
