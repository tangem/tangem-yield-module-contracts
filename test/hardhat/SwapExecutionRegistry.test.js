const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SwapExecutionRegistry", function () {
  let registry;
  let admin, other, third;

  before(async function () {
    [admin, other, third] = await ethers.getSigners();
  });

  beforeEach(async function () {
    const SwapExecutionRegistry = await ethers.getContractFactory("SwapExecutionRegistry");
    registry = await SwapExecutionRegistry.deploy(admin.address);
    await registry.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Sets roles for admin", async function () {
      const defaultAdminRole = await registry.DEFAULT_ADMIN_ROLE();
      const allowlistRole = await registry.ALLOWLIST_ADMIN_ROLE();

      expect(await registry.hasRole(defaultAdminRole, admin.address)).to.equal(true);
      expect(await registry.hasRole(allowlistRole, admin.address)).to.equal(true);
    });

    it("Reverts with ZeroAddress when admin is zero", async function () {
      const SwapExecutionRegistry = await ethers.getContractFactory("SwapExecutionRegistry");

      await expect(SwapExecutionRegistry.deploy(ethers.ZeroAddress))
        .to.be.revertedWithCustomError(SwapExecutionRegistry, "ZeroAddress");
    });
  });

  describe("setTargetAllowed", function () {
    it("Sets target allowed and emits TargetAllowedSet", async function () {
      await expect(registry.connect(admin).setTargetAllowed(other.address, true))
        .to.emit(registry, "TargetAllowedSet")
        .withArgs(other.address, true);

      expect(await registry.allowedTargets(other.address)).to.equal(true);
    });

    it("Reverts with ZeroAddress when target is zero", async function () {
      await expect(registry.connect(admin).setTargetAllowed(ethers.ZeroAddress, true))
        .to.be.revertedWithCustomError(registry, "ZeroAddress");
    });

    it("Reverts when called without ALLOWLIST_ADMIN_ROLE", async function () {
      await expect(registry.connect(other).setTargetAllowed(third.address, true))
        .to.be.revertedWithCustomError(registry, "AccessControlUnauthorizedAccount")
        .withArgs(other.address, await registry.ALLOWLIST_ADMIN_ROLE());
    });
  });

  describe("setSpenderAllowed", function () {
    it("Sets spender allowed and emits SpenderAllowedSet", async function () {
      await expect(registry.connect(admin).setSpenderAllowed(other.address, true))
        .to.emit(registry, "SpenderAllowedSet")
        .withArgs(other.address, true);

      expect(await registry.allowedSpenders(other.address)).to.equal(true);
    });

    it("Reverts with ZeroAddress when spender is zero", async function () {
      await expect(registry.connect(admin).setSpenderAllowed(ethers.ZeroAddress, true))
        .to.be.revertedWithCustomError(registry, "ZeroAddress");
    });

    it("Reverts when called without ALLOWLIST_ADMIN_ROLE", async function () {
      await expect(registry.connect(other).setSpenderAllowed(third.address, true))
        .to.be.revertedWithCustomError(registry, "AccessControlUnauthorizedAccount")
        .withArgs(other.address, await registry.ALLOWLIST_ADMIN_ROLE());
    });
  });

  describe("setTargetsAllowed", function () {
    it("Sets many targets allowed and emits TargetAllowedSet for each", async function () {
      const targets = [other.address, third.address];

      const tx = await registry.connect(admin).setTargetsAllowed(targets, true);
      await expect(tx).to.emit(registry, "TargetAllowedSet").withArgs(other.address, true);
      await expect(tx).to.emit(registry, "TargetAllowedSet").withArgs(third.address, true);

      expect(await registry.allowedTargets(other.address)).to.equal(true);
      expect(await registry.allowedTargets(third.address)).to.equal(true);
    });

    it("Sets many targets disallowed and emits TargetAllowedSet for each", async function () {
      const targets = [other.address, third.address];

      const tx1 = await registry.connect(admin).setTargetsAllowed(targets, true);
      await tx1.wait();

      const tx2 = await registry.connect(admin).setTargetsAllowed(targets, false);
      await expect(tx2).to.emit(registry, "TargetAllowedSet").withArgs(other.address, false);
      await expect(tx2).to.emit(registry, "TargetAllowedSet").withArgs(third.address, false);

      expect(await registry.allowedTargets(other.address)).to.equal(false);
      expect(await registry.allowedTargets(third.address)).to.equal(false);
    });

    it("Reverts with ZeroAddress when any target is zero", async function () {
      const targets = [other.address, ethers.ZeroAddress, third.address];

      await expect(registry.connect(admin).setTargetsAllowed(targets, true))
        .to.be.revertedWithCustomError(registry, "ZeroAddress");
    });

    it("Allows empty array without reverting", async function () {
      const targets = [];

      await registry.connect(admin).setTargetsAllowed(targets, true);
    });

    it("Reverts when called without ALLOWLIST_ADMIN_ROLE", async function () {
      await expect(registry.connect(other).setTargetsAllowed([third.address], true))
        .to.be.revertedWithCustomError(registry, "AccessControlUnauthorizedAccount")
        .withArgs(other.address, await registry.ALLOWLIST_ADMIN_ROLE());
    });
  });

  describe("setSpendersAllowed", function () {
    it("Sets many spenders allowed and emits SpenderAllowedSet for each", async function () {
      const spenders = [other.address, third.address];

      const tx = await registry.connect(admin).setSpendersAllowed(spenders, true);
      await expect(tx).to.emit(registry, "SpenderAllowedSet").withArgs(other.address, true);
      await expect(tx).to.emit(registry, "SpenderAllowedSet").withArgs(third.address, true);

      expect(await registry.allowedSpenders(other.address)).to.equal(true);
      expect(await registry.allowedSpenders(third.address)).to.equal(true);
    });

    it("Sets many spenders disallowed and emits SpenderAllowedSet for each", async function () {
      const spenders = [other.address, third.address];

      const tx1 = await registry.connect(admin).setSpendersAllowed(spenders, true);
      await tx1.wait();

      const tx2 = await registry.connect(admin).setSpendersAllowed(spenders, false);
      await expect(tx2).to.emit(registry, "SpenderAllowedSet").withArgs(other.address, false);
      await expect(tx2).to.emit(registry, "SpenderAllowedSet").withArgs(third.address, false);

      expect(await registry.allowedSpenders(other.address)).to.equal(false);
      expect(await registry.allowedSpenders(third.address)).to.equal(false);
    });

    it("Reverts with ZeroAddress when any spender is zero", async function () {
      const spenders = [other.address, ethers.ZeroAddress, third.address];

      await expect(registry.connect(admin).setSpendersAllowed(spenders, true))
        .to.be.revertedWithCustomError(registry, "ZeroAddress");
    });

    it("Allows empty array without reverting", async function () {
      const spenders = [];

      await registry.connect(admin).setSpendersAllowed(spenders, true);
    });

    it("Reverts when called without ALLOWLIST_ADMIN_ROLE", async function () {
      await expect(registry.connect(other).setSpendersAllowed([third.address], true))
        .to.be.revertedWithCustomError(registry, "AccessControlUnauthorizedAccount")
        .withArgs(other.address, await registry.ALLOWLIST_ADMIN_ROLE());
    });
  });

  describe("setTargetsAllowedMany", function () {
    it("Sets targets with per-item statuses and emits TargetAllowedSet for each", async function () {
      const targets = [other.address, third.address];
      const statuses = [true, false];

      const tx = await registry.connect(admin).setTargetsAllowedMany(targets, statuses);
      await expect(tx).to.emit(registry, "TargetAllowedSet").withArgs(other.address, true);
      await expect(tx).to.emit(registry, "TargetAllowedSet").withArgs(third.address, false);

      expect(await registry.allowedTargets(other.address)).to.equal(true);
      expect(await registry.allowedTargets(third.address)).to.equal(false);
    });

    it("Reverts with LengthMismatch when arrays have different lengths", async function () {
      const targets = [other.address, third.address];
      const statuses = [true];

      await expect(registry.connect(admin).setTargetsAllowedMany(targets, statuses))
        .to.be.revertedWithCustomError(registry, "LengthMismatch");
    });

    it("Reverts with ZeroAddress when any target is zero", async function () {
      const targets = [other.address, ethers.ZeroAddress];
      const statuses = [true, false];

      await expect(registry.connect(admin).setTargetsAllowedMany(targets, statuses))
        .to.be.revertedWithCustomError(registry, "ZeroAddress");
    });

    it("Allows empty arrays without reverting", async function () {
      await registry.connect(admin).setTargetsAllowedMany([], []);
    });

    it("Reverts when called without ALLOWLIST_ADMIN_ROLE", async function () {
      await expect(registry.connect(other).setTargetsAllowedMany([third.address], [true]))
        .to.be.revertedWithCustomError(registry, "AccessControlUnauthorizedAccount")
        .withArgs(other.address, await registry.ALLOWLIST_ADMIN_ROLE());
    });
  });

  describe("setSpendersAllowedMany", function () {
    it("Sets spenders with per-item statuses and emits SpenderAllowedSet for each", async function () {
      const spenders = [other.address, third.address];
      const statuses = [false, true];

      const tx = await registry.connect(admin).setSpendersAllowedMany(spenders, statuses);
      await expect(tx).to.emit(registry, "SpenderAllowedSet").withArgs(other.address, false);
      await expect(tx).to.emit(registry, "SpenderAllowedSet").withArgs(third.address, true);

      expect(await registry.allowedSpenders(other.address)).to.equal(false);
      expect(await registry.allowedSpenders(third.address)).to.equal(true);
    });

    it("Reverts with LengthMismatch when arrays have different lengths", async function () {
      const spenders = [other.address, third.address];
      const statuses = [true];

      await expect(registry.connect(admin).setSpendersAllowedMany(spenders, statuses))
        .to.be.revertedWithCustomError(registry, "LengthMismatch");
    });

    it("Reverts with ZeroAddress when any spender is zero", async function () {
      const spenders = [other.address, ethers.ZeroAddress];
      const statuses = [true, false];

      await expect(registry.connect(admin).setSpendersAllowedMany(spenders, statuses))
        .to.be.revertedWithCustomError(registry, "ZeroAddress");
    });

    it("Allows empty arrays without reverting", async function () {
      await registry.connect(admin).setSpendersAllowedMany([], []);
    });

    it("Reverts when called without ALLOWLIST_ADMIN_ROLE", async function () {
      await expect(registry.connect(other).setSpendersAllowedMany([third.address], [true]))
        .to.be.revertedWithCustomError(registry, "AccessControlUnauthorizedAccount")
        .withArgs(other.address, await registry.ALLOWLIST_ADMIN_ROLE());
    });
  });

  describe("Views", function () {
    it("Returns false by default for unknown target and spender", async function () {
      expect(await registry.allowedTargets(other.address)).to.equal(false);
      expect(await registry.allowedSpenders(other.address)).to.equal(false);
    });
  });
});
