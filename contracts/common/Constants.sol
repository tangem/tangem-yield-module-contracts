// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

uint constant PRECISION = 10000;

// minimum interval between two suspension episodes per token (escalation of an
// already-suspended token is not limited)
uint constant SUSPENSION_COOLDOWN = 24 hours;
